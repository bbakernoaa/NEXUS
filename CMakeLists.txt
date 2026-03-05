cmake_minimum_required(VERSION 3.5)
if(POLICY CMP0074)
  cmake_policy(SET CMP0074 NEW)
endif()

# Set the project name and version
project(NEXUS
  VERSION 0.2.0
  LANGUAGES Fortran)

# FC should be used to set compiler
if(NOT DEFINED ENV{FC})
  message(WARNING "FC is not set. You may want to use it to specify a specific compiler.")
else()
  if("$ENV{FC}" STREQUAL "")
    message(WARNING "FC is set to empty string. You may want to use it to specify a specific compiler.")
  else()
    message(STATUS "FC is set: '$ENV{FC}'")
  endif()
endif()

# Include local macros
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

option(USE_MPI "Build with MPI" ON)
option(NEXUS_USE_INLINE_CDEPS "Use inline CDEPS (link to prebuilt CDEPS-interface)" ON)
option(NEXUS_ENABLE_EXTERNAL_DATM "Enable external DATM component/connector build-time linkage" OFF)
set(CDEPS_INTERFACE_DIR "/scratch4/NCEPDEV/naqfc/Barry.Baker/models/ufs-weather-model/build/CDEPS-interface" CACHE PATH "Path to prebuilt CDEPS-interface (include 'mod' and libraries)")
# Find and configure MPI
if(USE_MPI)
  find_package(MPI REQUIRED COMPONENTS Fortran)
  if(MPI_Fortran_FOUND)
    message(STATUS "MPI_Fortran_COMPILER: ${MPI_Fortran_COMPILER}")
    message(STATUS "MPI_Fortran_COMPILE_FLAGS: ${MPI_Fortran_COMPILE_FLAGS}")
    message(STATUS "MPI_Fortran_INCLUDE_PATH: ${MPI_Fortran_INCLUDE_PATH}")
    message(STATUS "MPI_Fortran_LINK_FLAGS: ${MPI_Fortran_LINK_FLAGS}")
    message(STATUS "MPI_Fortran_LIBRARIES: ${MPI_Fortran_LIBRARIES}")
  endif()
endif()
# Ensure Fortran modules are placed in a central directory expected by CDEPS
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/share CACHE PATH "Central module directory")
file(MAKE_DIRECTORY ${CMAKE_Fortran_MODULE_DIRECTORY})
set(CDEPS_SHARE_MOD_DIR ${CMAKE_Fortran_MODULE_DIRECTORY})

# Global Fortran flags to prevent line truncation in fetched dependencies (like CDEPS)
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -ffree-line-length-none" CACHE STRING "Global Fortran flags" FORCE)
endif()

# Control where the static and shared libraries are built
# so that on Windows we don't need to tinker with the path to run the executable
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")

# Do not build HEMCO standalone executable
set(HEMCO_EXTERNAL_CONFIG ON CACHE BOOL "Build HEMCO as an external component")
set(NUOPC_ESMF ON CACHE BOOL "Enable NUOPC interface for HEMCO" FORCE)
set(HEMCO_INTERFACE "esmf" CACHE STRING "HEMCO interface type" FORCE)

if(CMAKE_BUILD_TYPE)
  string(TOUPPER ${CMAKE_BUILD_TYPE} UPPER_CMAKE_BUILD_TYPE)
endif()
message(STATUS "CMAKE_BUILD_TYPE: '${UPPER_CMAKE_BUILD_TYPE}'")

if(UPPER_CMAKE_BUILD_TYPE STREQUAL "DEBUG")
  # HEMCO already sets `-ftrapuv` for Intel and similar options for GNU
  # https://github.com/geoschem/HEMCO/blob/main/CMakeLists.txt
  # and its options get applied to NEXUS as well.
  # Note HEMCO only support GNU and Intel.
  if(CMAKE_Fortran_COMPILER_ID STREQUAL "Intel")
    set(EXTRA_FLAGS "-check all")
  elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    set(EXTRA_FLAGS "-fcheck=all")
  endif()
  set(CMAKE_Fortran_FLAGS_DEBUG "${CMAKE_Fortran_FLAGS_DEBUG} ${EXTRA_FLAGS}")
  message(STATUS "CMAKE_Fortran_FLAGS_DEBUG: ${CMAKE_Fortran_FLAGS_DEBUG}")
endif()

if(CMAKE_Fortran_COMPILER_ID STREQUAL "Intel")
  string(APPEND CMAKE_Fortran_FLAGS " -diag-disable=10448")
endif()

# Add project's subdirectories
# add_subdirectory(src/external/CDEPS)

# Import or build external CDEPS
if(NEXUS_USE_INLINE_CDEPS)
  include(FetchContent)

  if(NOT TARGET cdeps)
    if(EXISTS "${CDEPS_INTERFACE_DIR}/cdeps-targets.cmake")
      include("${CDEPS_INTERFACE_DIR}/cdeps-targets.cmake")
      message(STATUS "Included external CDEPS targets from ${CDEPS_INTERFACE_DIR}")
    else()
      message(STATUS "CDEPS targets not found at ${CDEPS_INTERFACE_DIR}. Fetching and building from source.")
      FetchContent_Declare(
        cdeps
        GIT_REPOSITORY https://github.com/bbakernoaa/CDEPS.git
        GIT_TAG feature/demis
        SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/cdeps-src
        BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/cdeps-build
        PATCH_COMMAND git submodule update --init --recursive
      )
      # Suppress CDEPS internal library builds that we don't need
      set(CDEPS_BUILD_TESTS OFF CACHE BOOL "" FORCE)
      set(DISABLE_FoX ON CACHE BOOL "" FORCE)
      set(ESMF_F90COMPILEPATHS "${ESMF_INCLUDE_DIRS}")

      FetchContent_MakeAvailable(cdeps)
    endif()
  endif()
endif()

add_subdirectory(src)
