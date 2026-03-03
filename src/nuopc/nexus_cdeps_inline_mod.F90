!> @file nexus_cdeps_inline_mod.F90
!> @brief NEXUS inline CDEPS module for direct data stream reading
!> @details Implements inline CDEPS capability using high-level CDEPS API.
!> Provides a bridge between HEMCO configuration and CDEPS streams.

module nexus_cdeps_inline_mod

  use ESMF
  use NUOPC
  use dshr_mod,          only: dshr_pio_init
  use dshr_strdata_mod,  only: shr_strdata_type, &
                               shr_strdata_init_from_inline, &
                               shr_strdata_advance
  use dshr_stream_mod,   only: shr_stream_init_from_esmfconfig
  use dshr_methods_mod,  only: dshr_fldbun_getfldptr, chkerr
  use shr_kind_mod,      only: r8 => shr_kind_r8

  ! HEMCO core modules for bridge
  use HCO_STATE_MOD,     only: HCO_State
  use HCO_TYPES_MOD
  use HCO_DATACONT_MOD,  only: ListCont_NextCont

  implicit none

  private

  public :: nexus_cdeps_init
  public :: nexus_cdeps_run
  public :: nexus_cdeps_advance
  public :: nexus_cdeps_get_field_ptr
  public :: nexus_cdeps_get_data_pointer
  public :: nexus_cdeps_get_available_fields
  public :: nexus_cdeps_init_from_hemco
  public :: nexus_cdeps_finalize

  !> Stream data configuration and instances
  type(shr_strdata_type), allocatable, save :: sdat(:)
  integer, save :: num_cdeps_streams = 0

  !> Module state
  integer, save :: logunit = 6
  logical, save :: initialized = .false.

  character(len=*), parameter :: u_FILE_u = "nexus_cdeps_inline_mod.F90"

contains

  !> @brief Initialize inline CDEPS from a stream configuration file
  !> @param[in] gcomp ESMF Grid Component
  !> @param[in] clock Model clock
  !> @param[in] mesh ESMF Mesh
  !> @param[in] stream_file Path to CDEPS stream configuration file
  !> @param[out] rc Return code
  subroutine nexus_cdeps_init(gcomp, clock, mesh, stream_file, rc)
    type(ESMF_GridComp), intent(in)  :: gcomp
    type(ESMF_Clock),    intent(in)  :: clock
    type(ESMF_Mesh),     intent(in)  :: mesh
    character(len=*),    intent(in)  :: stream_file
    integer,             intent(out) :: rc

    type(shr_strdata_type) :: sdatconfig
    character(len=ESMF_MAXSTR), allocatable :: f_list(:), v_list(:,:)
    integer :: ns, l, nstreams, mytask
    type(ESMF_VM) :: vm
    logical :: isPresent, isSet
    character(len=ESMF_MAXSTR) :: compname = 'NEXUS'
    character(len=ESMF_MAXSTR) :: cvalue, stream_name

    rc = ESMF_SUCCESS

    call ESMF_GridCompGet(gcomp, vm=vm, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    call ESMF_VMGet(vm, localPet=mytask, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return

    call NUOPC_CompAttributeGet(gcomp, name='component_name', value=cvalue, isPresent=isPresent, isSet=isSet, rc=rc)
    if (rc == ESMF_SUCCESS .and. isPresent .and. isSet) then
       compname = trim(cvalue)
    endif

    ! Initialize PIO via CDEPS helper
    call dshr_pio_init(gcomp, sdatconfig, logunit, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return

    ! Load stream definitions from configuration
    call shr_stream_init_from_esmfconfig(trim(stream_file), sdatconfig%stream, logunit, &
         sdatconfig%pio_subsystem, sdatconfig%io_type, sdatconfig%io_format, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return

    if (.not. associated(sdatconfig%stream)) then
       if (mytask == 0) print *, "nexus_cdeps_init: No streams found in ", trim(stream_file)
       rc = ESMF_SUCCESS
       return
    endif

    nstreams = size(sdatconfig%stream)
    if (allocated(sdat)) deallocate(sdat)
    allocate(sdat(nstreams))
    num_cdeps_streams = nstreams

    do ns = 1, nstreams
      sdat(ns)%model_clock = clock
      sdat(ns)%model_mesh  = mesh
      sdat(ns)%pio_subsystem => sdatconfig%pio_subsystem
      sdat(ns)%io_type = sdatconfig%io_type
      sdat(ns)%io_format = sdatconfig%io_format

      allocate(f_list(sdatconfig%stream(ns)%nfiles))
      allocate(v_list(sdatconfig%stream(ns)%nvars, 2))

      do l = 1, sdatconfig%stream(ns)%nfiles
        f_list(l) = trim(sdatconfig%stream(ns)%file(l)%name)
      end do
      do l = 1, sdatconfig%stream(ns)%nvars
        v_list(l,1) = trim(sdatconfig%stream(ns)%varlist(l)%nameinfile)
        v_list(l,2) = trim(sdatconfig%stream(ns)%varlist(l)%nameinmodel)
      end do

      write(stream_name,fmt='(a,i2.2)') 'stream_', ns
      call shr_strdata_init_from_inline(sdat(ns), &
           my_task             = mytask, &
           logunit             = logunit, &
           compname            = trim(compname), &
           model_clock         = clock, &
           model_mesh          = mesh, &
           stream_name         = trim(stream_name), &
           stream_meshfile     = trim(sdatconfig%stream(ns)%meshfile), &
           stream_filenames    = f_list, &
           stream_fldlistFile  = v_list(:,1), &
           stream_fldListModel = v_list(:,2), &
           stream_yearFirst    = sdatconfig%stream(ns)%yearFirst, &
           stream_yearLast     = sdatconfig%stream(ns)%yearLast, &
           stream_yearAlign    = sdatconfig%stream(ns)%yearAlign, &
           stream_offset       = sdatconfig%stream(ns)%offset, &
           stream_taxmode      = trim(sdatconfig%stream(ns)%taxmode), &
           stream_dtlimit      = sdatconfig%stream(ns)%dtlimit, &
           stream_tintalgo     = trim(sdatconfig%stream(ns)%tInterpAlgo), &
           stream_lev_dimname  = trim(sdatconfig%stream(ns)%lev_dimname), &
           stream_mapalgo      = trim(sdatconfig%stream(ns)%mapalgo), &
           stream_src_mask     = sdatconfig%stream(ns)%src_mask_val, &
           stream_dst_mask     = sdatconfig%stream(ns)%dst_mask_val, &
           rc                  = rc)

      deallocate(f_list, v_list)
      if (chkerr(rc,__LINE__,u_FILE_u)) return
    end do

    initialized = .true.
    if (mytask == 0) print *, "nexus_cdeps_init: Completed initialization of ", nstreams, " streams"

  end subroutine nexus_cdeps_init

  !> @brief Initialize inline CDEPS by bridging from HEMCO configuration
  !> @param[in] HcoState HEMCO State object containing configuration
  !> @param[in] gcomp ESMF Grid Component
  !> @param[in] clock Model clock
  !> @param[in] mesh ESMF Mesh
  !> @param[out] rc Return code
  subroutine nexus_cdeps_init_from_hemco(HcoState, gcomp, clock, mesh, rc)
    type(HCO_State),     pointer     :: HcoState
    type(ESMF_GridComp), intent(in)  :: gcomp
    type(ESMF_Clock),    intent(in)  :: clock
    type(ESMF_Mesh),     intent(in)  :: mesh
    integer,             intent(out) :: rc

    type(ListCont), pointer :: Lct
    integer :: unit, ios, localPet
    type(ESMF_VM) :: vm
    character(len=255) :: stream_file = "cdeps_streams_from_hemco.yaml"
    character(len=1024) :: ncFile, ncPara

    rc = ESMF_SUCCESS
    if (.not. associated(HcoState)) then
        rc = ESMF_RC_ARG_BAD
        return
    endif

    call ESMF_VMGetCurrent(vm, rc=rc)
    call ESMF_VMGet(vm, localPet=localPet, rc=rc)

    if (localPet == 0) then
        print *, "nexus_cdeps_init_from_hemco: Bridging HEMCO to CDEPS"

        ! 1. Open a temporary file to write CDEPS configuration
        open(newunit=unit, file=trim(stream_file), status='replace', action='write', iostat=ios)
        if (ios /= 0) then
            rc = ESMF_FAILURE
            return
        endif

        write(unit, '(A)') "input_streams:"

        ! 2. Iterate through HEMCO ConfigList
        Lct => HcoState%Config%ConfigList
        do while (associated(Lct))
            if (associated(Lct%Dct)) then
                ! We only care about base emissions that are read from files
                ! Filter out non-file based entries (e.g. '-' or single values)
                ncFile = Lct%Dct%Dta%ncFile
                ncPara = Lct%Dct%Dta%ncPara

                if (Lct%Dct%DctType == HCO_DCTTYPE_BASE .and. Lct%Dct%Dta%ncRead .and. &
                    trim(ncFile) /= '-' .and. trim(ncFile) /= '0.0' .and. trim(ncPara) /= '-') then

                    ! Basic stream info
                    write(unit, '(A,A)') "  - name: ", trim(Lct%Dct%cName)

                    ! Handle $ROOT token in filename if not already resolved by HEMCO
                    ! (HEMCO usually resolves tokens during Config_ReadFile)
                    write(unit, '(A,A)') "    datafiles: ", trim(ncFile)
                    write(unit, '(A)')    "    datavars:"
                    write(unit, '(A,A)') "      - ", trim(ncPara)

                    ! Taxmode
                    select case(Lct%Dct%Dta%CycleFlag)
                    case(HCO_CFLAG_CYCLE)
                        write(unit, '(A)') "    taxmode: cycle"
                    case(HCO_CFLAG_RANGE, HCO_CFLAG_EXACT, HCO_CFLAG_RANGEAVG)
                        write(unit, '(A)') "    taxmode: extend"
                    case default
                        write(unit, '(A)') "    taxmode: cycle"
                    end select

                    ! Time range
                    write(unit, '(A,I0)') "    year_first: ", Lct%Dct%Dta%ncYrs(1)
                    write(unit, '(A,I0)') "    year_last: ",  Lct%Dct%Dta%ncYrs(2)
                    write(unit, '(A,I0)') "    year_align: ", Lct%Dct%Dta%ncYrs(1)

                    ! Interpolation and mapping
                    ! Use reasonable defaults for NEXUS
                    write(unit, '(A)') "    mapalgo: bilinear"
                    write(unit, '(A)') "    tintalgo: linear"

                    ! Handle vertical dimension
                    if (Lct%Dct%Dta%SpaceDim == 3) then
                        ! If levels are specified, we might need lev_dimname
                        ! For now assume 'lev' or 'level' or handled by netCDF-PIO
                        write(unit, '(A)') "    lev_dimname: lev"
                    else
                        write(unit, '(A)') "    lev_dimname: none"
                    endif

                    ! Meshfile
                    write(unit, '(A)') "    meshfile: none"

                    if (localPet == 0) then
                        print *, "  + Bridged stream: ", trim(Lct%Dct%cName), " (", trim(ncPara), ")"
                    endif
                endif
            endif
            Lct => Lct%NextCont
        enddo
        close(unit)
    endif

    ! Sync before all PETs read the file
    call ESMF_VMBarrier(vm, rc=rc)

    ! 3. Call the regular init with this file
    call nexus_cdeps_init(gcomp, clock, mesh, stream_file, rc)

  end subroutine nexus_cdeps_init_from_hemco

  !> @brief Advance inline CDEPS streams to current model time
  !> @param[in] clock Model clock
  !> @param[out] rc Return code
  subroutine nexus_cdeps_advance(clock, rc)
    type(ESMF_Clock), intent(in)  :: clock
    integer,          intent(out) :: rc

    type(ESMF_Time) :: currTime
    integer :: yy, mm, dd, h, m, s, mcdate, tod, ns
    character(len=ESMF_MAXSTR) :: stream_name

    rc = ESMF_SUCCESS
    if (.not. initialized .or. .not. allocated(sdat)) return

    call ESMF_ClockGet(clock, currTime=currTime, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    call ESMF_TimeGet(currTime, yy=yy, mm=mm, dd=dd, h=h, m=m, s=s, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    mcdate = yy*10000 + mm*100 + dd
    tod = h*3600 + m*60 + s

    do ns = 1, size(sdat)
      write(stream_name,fmt='(a,i2.2)') 'stream_', ns
      call shr_strdata_advance(sdat(ns), ymd=mcdate, tod=tod, logunit=logunit, istr=trim(stream_name), rc=rc)
      if (chkerr(rc,__LINE__,u_FILE_u)) return
    end do
  end subroutine nexus_cdeps_advance

  !> @brief Run CDEPS (wrapper for advance)
  subroutine nexus_cdeps_run(clock, rc)
    type(ESMF_Clock), intent(in)  :: clock
    integer,          intent(out) :: rc
    call nexus_cdeps_advance(clock, rc)
  end subroutine nexus_cdeps_run

  !> @brief Get data pointer for a field from a CDEPS stream
  !> @param[in] stream_idx Stream index
  !> @param[in] fldname Field name to retrieve
  !> @param[out] data_ptr Pointer to data array
  !> @param[out] rc Return code
  subroutine nexus_cdeps_get_field_ptr(stream_idx, fldname, data_ptr, rc)
    integer,            intent(in)  :: stream_idx
    character(len=*),   intent(in)  :: fldname
    real(r8),           pointer     :: data_ptr(:)
    integer,            intent(out) :: rc

    rc = ESMF_SUCCESS
    data_ptr => null()

    if (.not. initialized .or. .not. allocated(sdat)) then
       rc = ESMF_RC_NOT_INIT
       return
    endif
    if (stream_idx < 1 .or. stream_idx > size(sdat)) then
       rc = ESMF_RC_ARG_OUTOFRANGE
       return
    endif

    call dshr_fldbun_getfldptr(sdat(stream_idx)%pstrm(1)%fldbun_model, &
                               trim(fldname), data_ptr, rc=rc)
  end subroutine nexus_cdeps_get_field_ptr

  !> @brief Get data pointer for a field (searches all streams)
  subroutine nexus_cdeps_get_data_pointer(field_name, data_ptr, rc)
    character(len=*), intent(in) :: field_name
    real(r8), pointer, intent(out) :: data_ptr(:)
    integer, intent(out) :: rc
    integer :: i
    rc = ESMF_RC_NOT_FOUND
    do i = 1, num_cdeps_streams
        call nexus_cdeps_get_field_ptr(i, field_name, data_ptr, rc)
        if (rc == ESMF_SUCCESS) return
    enddo
  end subroutine nexus_cdeps_get_data_pointer

  !> @brief Get list of available fields from CDEPS
  subroutine nexus_cdeps_get_available_fields(field_names, num_fields, rc)
    character(len=ESMF_MAXSTR), allocatable, intent(out) :: field_names(:)
    integer, intent(out) :: num_fields
    integer, intent(out) :: rc
    integer :: i, j, total_vars, count

    rc = ESMF_SUCCESS
    num_fields = 0
    if (.not. initialized) return

    total_vars = 0
    do i = 1, num_cdeps_streams
        if (allocated(sdat(i)%pstrm(1)%fldlist_model)) then
            total_vars = total_vars + size(sdat(i)%pstrm(1)%fldlist_model)
        endif
    enddo

    if (total_vars == 0) return
    allocate(field_names(total_vars))
    count = 0
    do i = 1, num_cdeps_streams
        if (allocated(sdat(i)%pstrm(1)%fldlist_model)) then
            do j = 1, size(sdat(i)%pstrm(1)%fldlist_model)
                count = count + 1
                field_names(count) = sdat(i)%pstrm(1)%fldlist_model(j)
            enddo
        endif
    enddo
    num_fields = count
  end subroutine nexus_cdeps_get_available_fields

  !> @brief Finalize inline CDEPS
  !> @param[out] rc Return code
  subroutine nexus_cdeps_finalize(rc)
    integer, intent(out) :: rc
    rc = ESMF_SUCCESS
    if (allocated(sdat)) deallocate(sdat)
    initialized = .false.
  end subroutine nexus_cdeps_finalize

end module nexus_cdeps_inline_mod
