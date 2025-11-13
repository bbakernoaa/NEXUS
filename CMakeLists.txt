cmake_minimum_required(VERSION 3.5)

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

# Control where the static and shared libraries are built
# so that on Windows we don't need to tinker with the path to run the executable
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")

# Default: build both NEXUS and HEMCO standalone.
# - By default we *enable* the internal HEMCO standalone configuration so that
#   `hemco_standalone` is built from this superproject.
# - If you want the old behavior (no standalone exe; external HEMCO config),
#   configure with: -DHEMCO_EXTERNAL_CONFIG=ON (or set it in your cache).
#
# NOTE:
# - When HEMCO_EXTERNAL_CONFIG=OFF (default here), HEMCO/CMakeLists.txt
#   enters its standalone block, sets HEMCO_INTERFACE=standalone, and
#   sets HEMCO_EXE_TARGETS to include hemco_standalone, so `make` will
#   build both NEXUS and hemco_standalone.
# - When HEMCO_EXTERNAL_CONFIG=ON, HEMCO is treated as externally
#   configured (e.g., GCClassic/MAPL wrapper mode) and hemco_standalone
#   is not built.
include(CheckCXXSymbolExists) # harmless no-op; ensures policy consistency on some systems

if(NOT DEFINED HEMCO_EXTERNAL_CONFIG)
  # Default to standalone mode: build hemco_standalone.
  set(HEMCO_EXTERNAL_CONFIG OFF CACHE BOOL "Use external HEMCO config (no standalone exe)" FORCE)
endif()

# If external-config mode is explicitly requested, enable GCClassic wrapper;
# otherwise leave GCCLASSIC_WRAPPER off by default.
if(HEMCO_EXTERNAL_CONFIG)
  set(GCCLASSIC_WRAPPER TRUE CACHE BOOL "Build HEMCO in GCClassic-wrapper mode" FORCE)
else()
  set(GCCLASSIC_WRAPPER FALSE CACHE BOOL "GCClassic wrapper disabled in standalone mode" FORCE)
endif()

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
add_subdirectory(HEMCO)
add_subdirectory(src)
