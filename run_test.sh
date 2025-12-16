#!/bin/bash
set -ex

# 1. Install dependencies
sudo apt-get update && sudo apt-get install -y \
  gfortran-12 \
  libnetcdf-dev libnetcdff-dev liblapack-dev libopenblas-dev \
  libopenmpi-dev openmpi-bin libstdc++-12-dev

# 2. Fetch pre-built ESMF
v="8.3.1"
gcc="12"
esmf_base=$HOME/esmf
esmf=${v}-gcc-${gcc}-mpi

export ESMF_DIR=${esmf_base}/${esmf}
mkdir -p $ESMF_DIR
cd $ESMF_DIR
wget https://github.com/zmoon/gha-esmf/releases/download/v0.0.8/${esmf}.tar.gz
tar xzvf ${esmf}.tar.gz
cd /app

# 3. Set environment variables
export ESMFMKFILE="${ESMF_DIR}/lib/libO/Linux.gfortran.64.mpi.default/esmf.mk"

# 4. Fix hardcoded paths in esmf.mk
sed -i "s|/github/home|$HOME|g" "$ESMFMKFILE"
sed -i "s|/home/runner|$HOME|g" "$ESMFMKFILE"

# 5. Configure and Build
export FC=gfortran-12
cmake -S . -B build -D ESMF_DIR=$ESMF_DIR
cmake --build build

# 6. Run tests
bin="$PWD/build/bin/nexus"
failed=0
cd tests/cases/ncwcp_anthro_pm
$bin -c NEXUS_Config.rc -r grid_spec.nc || failed=1
if [[ "$failed" == 1 ]]; then
  echo "TEST FAILED"
  tail -n 20 NEXUS.log
  # The ESMF log file might not exist if it fails early, so check first
  if [ -f PET0.ESMF_LogFile ]; then
    cat PET0.ESMF_LogFile
  fi
else
  echo "TEST PASSED"
fi
cd /app
