!> @brief NUOPC Field Advertisement Module
!> @details Standard NUOPC field advertisement for inline CDEPS mode.
!> Only advertises export fields since data reading is handled internally
!> via shr_strdata rather than external component dependencies.
!> @authors Barry Baker
!> @version 2.0
!> @date 2026-01-06

module nexus_field_advertisement_mod

  use ESMF
  use NUOPC
  use NUOPC_Model, only: NUOPC_ModelGet
  use nexus_config_mod, only: nxs_read_full_config

  implicit none
  private

  public :: AdvertiseFields

contains

  !> @brief Advertise import and export fields following NUOPC standards
  !> @details This subroutine dynamically identifies required import fields
  !> based on the HEMCO configuration and advertises them.
  subroutine AdvertiseFields(model, HcoConfig, rc)
    use HCO_STATE_MOD,     only: HCO_State
    use HCO_TYPES_MOD
    use HCO_DATACONT_MOD,  only: ListCont_NextCont

    type(ESMF_GridComp), intent(inout) :: model
    type(ConfigObj), pointer, intent(in) :: HcoConfig
    integer, intent(out) :: rc

    type(ESMF_State) :: importState, exportState
    integer :: localrc
    type(ESMF_VM) :: vm
    integer :: localPet
    character(len=256) :: fieldName
    type(ListCont), pointer :: Lct

    ! Check for standalone mode
    logical :: standalone_mode
    character(len=255) :: hemco_config_file, grid_file, regrid_file
    integer :: config_rc

    ! Get VM info for messaging
    call ESMF_VMGetCurrent(vm, rc=localrc)
    if (ESMF_LogFoundError(rcToCheck=localrc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, file=__FILE__, rcToReturn=rc)) return
    call ESMF_VMGet(vm, localPet=localPet, rc=localrc)
    if (ESMF_LogFoundError(rcToCheck=localrc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, file=__FILE__, rcToReturn=rc)) return

    ! Check if we're in standalone mode
    call nxs_read_full_config('nexus.rc', hemco_config_file, grid_file, standalone_mode, regrid_file, config_rc)
    if (config_rc /= 0) then
      if (localPet == 0) then
        call ESMF_LogWrite("NEXUS: Warning - could not read config, defaulting to standalone mode for field advertisement", ESMF_LOGMSG_WARNING)
      endif
      standalone_mode = .true.
    endif

    if (standalone_mode) then
      if (localPet == 0) then
        call ESMF_LogWrite("NEXUS: Running in standalone mode - skipping import field advertisement", ESMF_LOGMSG_INFO)
        call ESMF_LogWrite("NEXUS: NEXUS will provide all its own data internally via inline CDEPS", ESMF_LOGMSG_INFO)
      endif
      ! Skip all import field advertisement - NEXUS provides its own data
      rc = ESMF_SUCCESS
      return
    endif

    ! Get import and export states
    call ESMF_GridCompGet(model, importState=importState, exportState=exportState, rc=localrc)
    if (ESMF_LogFoundError(rcToCheck=localrc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, file=__FILE__, rcToReturn=rc)) return

    if (localPet == 0) then
      call ESMF_LogWrite("NEXUS: Dynamically advertising import fields from HEMCO configuration...", ESMF_LOGMSG_INFO)
    end if

    ! Identify import fields from HEMCO configuration
    if (associated(HcoConfig)) then
        Lct => HcoConfig%ConfigList
        do while (associated(Lct))
            if (associated(Lct%Dct)) then
                ! Advertise any field that is read from a file as a potential import
                if (Lct%Dct%DctType == HCO_DCTTYPE_BASE .and. Lct%Dct%Dta%ncRead .and. &
                    trim(Lct%Dct%Dta%ncFile) /= '-' .and. trim(Lct%Dct%Dta%ncPara) /= '-') then

                    fieldName = trim(Lct%Dct%cName) // ':' // trim(Lct%Dct%Dta%ncPara)
                    call NUOPC_Advertise(importState, StandardName=trim(fieldName), rc=localrc)
                    if (localPet == 0) print *, "  + Advertised import: ", trim(fieldName)
                endif
            endif
            Lct => Lct%NextCont
        enddo
    else
        if (localPet == 0) call ESMF_LogWrite("NEXUS: WARNING - HcoConfig not associated in Advertise phase", ESMF_LOGMSG_WARNING)
    endif

    if (localPet == 0) then
      call ESMF_LogWrite("NEXUS: Field advertisement completed successfully", ESMF_LOGMSG_INFO)
    end if

    rc = ESMF_SUCCESS

  end subroutine AdvertiseFields

  !> @brief Advertise import fields from configuration
  subroutine AdvertiseImportFieldsFromConfig(importState, streamNames, varNames, numStreams, rc)
    type(ESMF_State), intent(inout) :: importState
    character(len=*), intent(in) :: streamNames(:)
    character(len=*), intent(in) :: varNames(:)
    integer, intent(in) :: numStreams
    integer, intent(out) :: rc

    integer :: i
    character(len=256) :: fieldName

    rc = ESMF_SUCCESS

    ! Advertise each variable as an import field using STREAM:VARIABLE naming
    do i = 1, numStreams
      if (len_trim(streamNames(i)) > 0 .and. len_trim(varNames(i)) > 0) then
        fieldName = trim(streamNames(i)) // ':' // trim(varNames(i))
        call NUOPC_Advertise(importState, StandardName=trim(fieldName), rc=rc)
        if (rc /= ESMF_SUCCESS) return
      end if
    end do

  end subroutine AdvertiseImportFieldsFromConfig

  !> @brief Helper to advertise a single import field
  subroutine AdvertiseImportField(importState, fieldName, rc)
    type(ESMF_State), intent(inout) :: importState
    character(len=*), intent(in) :: fieldName
    integer, intent(out) :: rc

    ! Standard NUOPC field advertisement - just the name, no data
    call NUOPC_Advertise(importState, StandardName=fieldName, rc=rc)
    if (ESMF_LogFoundError(rcToCheck=rc, msg=ESMF_LOGERR_PASSTHRU, &
      line=__LINE__, file=__FILE__, rcToReturn=rc)) return

    rc = ESMF_SUCCESS

  end subroutine AdvertiseImportField

  !> @brief Read input streams configuration from YAML file
  !> @details Parses nexus_input_streams.yaml to extract stream names and variable names
  subroutine ReadInputStreamsConfig(filename, streamNames, varNames, numStreams, rc)
    character(len=*), intent(in) :: filename
    character(len=64), allocatable, intent(out) :: streamNames(:)
    character(len=64), allocatable, intent(out) :: varNames(:)
    integer, intent(out) :: numStreams
    integer, intent(out) :: rc

    integer, parameter :: MAX_STREAMS = 50, MAX_VARS_PER_STREAM = 20
    integer :: unit, ios, i, varCount
    character(len=256) :: line
    character(len=64) :: streamName
    logical :: inStream, inDatavars

    numStreams = 0
    varCount = 0

    ! Allocate arrays for maximum possible size
    allocate(streamNames(MAX_STREAMS * MAX_VARS_PER_STREAM))
    allocate(varNames(MAX_STREAMS * MAX_VARS_PER_STREAM))

    ! Open YAML file
    open(newunit=unit, file=filename, status='old', action='read', iostat=ios)
    if (ios /= 0) then
      rc = ESMF_FAILURE
      return
    end if

    inStream = .false.
    inDatavars = .false.
    streamName = ""

    ! Parse YAML file
    do
      read(unit, '(A)', iostat=ios) line
      if (ios /= 0) exit

      line = adjustl(line)

      ! Check for stream name
      if (index(line, '- name:') > 0) then
        inStream = .true.
        inDatavars = .false.
        ! Extract stream name
        i = index(line, 'name:') + 5
        streamName = trim(adjustl(line(i:)))
      end if

      ! Check for datavars section
      if (inStream .and. index(line, 'datavars:') > 0) then
        inDatavars = .true.
      end if

      ! Extract variable names from datavars section
      if (inStream .and. inDatavars .and. index(line, '- ') == 1) then
        varCount = varCount + 1
        streamNames(varCount) = streamName
        ! Extract variable name (remove leading '- ' and any trailing spaces)
        varNames(varCount) = trim(adjustl(line(3:)))
      end if
    end do

    close(unit)
    numStreams = varCount
    rc = ESMF_SUCCESS

  end subroutine ReadInputStreamsConfig

  !> @brief Skip default field advertising for inline CDEPS mode
  subroutine AdvertiseDefaultFields(importState, rc)
    type(ESMF_State), intent(inout) :: importState
    integer, intent(out) :: rc

    ! For inline CDEPS mode, skip all import field advertising
    ! Data reading is handled internally

    rc = ESMF_SUCCESS

  end subroutine AdvertiseDefaultFields

end module nexus_field_advertisement_mod
