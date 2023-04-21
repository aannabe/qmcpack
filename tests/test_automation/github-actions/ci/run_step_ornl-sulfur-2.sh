#!/bin/bash

set -x
HOST_NAME=$(hostname -s)

# Current local LLVM version on sulfur
LLVM_VERSION=16.0.2

case "$1" in 

  # Configure qmcpack using cmake out-of-source builds 
  configure)
  
    echo "Use recent CMake v3.26.3"
    export PATH=$HOME/opt/cmake/3.26.3/bin:$PATH
    # Make current environment variables available to subsequent steps, ctest
    echo "PATH=$PATH" >> $GITHUB_ENV

    QMC_DATA_DIR=/scratch/ci/QMC_DATA_FULL

    if [ -d ${GITHUB_WORKSPACE}/../qmcpack-build ]
    then
      echo "Found existing out-of-source build directory ${GITHUB_WORKSPACE}/../qmcpack-build, removing"
      rm -fr ${GITHUB_WORKSPACE}/../qmcpack-build
    fi

    echo "Creating new out-of-source build directory ${GITHUB_WORKSPACE}/../qmcpack-build"
    cd ${GITHUB_WORKSPACE}/.. && mkdir qmcpack-build && cd qmcpack-build
    
    # Build variants
    # Real or Complex configuration
    case "${GH_JOBNAME}" in
      *"Real"*)
        echo 'Configure for real build -DQMC_COMPLEX=0'
        IS_COMPLEX=0
      ;;
      *"Complex"*)
        echo 'Configure for complex build -DQMC_COMPLEX=1'
        IS_COMPLEX=1
      ;; 
    esac

    # Mixed or Non-Mixed (default, full) precision, used with GPU code
    case "${GH_JOBNAME}" in
      *"Mixed"*)
        echo 'Configure for mixed precision build -DQMC_MIXED_PRECISION=1'
        IS_MIXED_PRECISION=1
      ;; 
      *)
        IS_MIXED_PRECISION=0
      ;;
    esac

    case "${GH_JOBNAME}" in
      *"TeslaV100-Clang16-MPI-CUDA-AFQMC-Offload"*)
        echo "Configure for building with CUDA and AFQMC using OpenMP offload"

        echo "Set PATH to cuda-11.2 due to a CUDA regression bug in 11.6"
        export PATH=/usr/local/cuda-11.2/bin:$PATH
        echo "Set CUDACXX CMake environment variable to nvcc cuda 11.2"
        export CUDACXX=/usr/local/cuda-11.2/bin/nvcc

        export OMPI_CC=$HOME/opt/llvm/$LLVM_VERSION/bin/clang
        export OMPI_CXX=$HOME/opt/llvm/$LLVM_VERSION/bin/clang++

        # Make current environment variables available to subsequent steps
        echo "PATH=$PATH" >> $GITHUB_ENV
        echo "CUDACXX=/usr/local/cuda-11.2/bin/nvcc" >> $GITHUB_ENV        
        echo "OMPI_CC=$OMPI_CC" >> $GITHUB_ENV
        echo "OMPI_CXX=$OMPI_CXX" >> $GITHUB_ENV

        # Confirm that cuda 11.2 gets picked up by the compiler
        $OMPI_CXX -v

        cmake -GNinja \
              -DCMAKE_C_COMPILER=/usr/lib64/openmpi/bin/mpicc \
              -DCMAKE_CXX_COMPILER=/usr/lib64/openmpi/bin/mpicxx \
              -DMPIEXEC_EXECUTABLE=/usr/lib64/openmpi/bin/mpirun \
              -DBUILD_AFQMC=ON \
              -DENABLE_CUDA=ON \
              -DQMC_GPU_ARCHS=sm_70 \
              -DENABLE_OFFLOAD=ON \
              -DQMC_COMPLEX=$IS_COMPLEX \
              -DQMC_MIXED_PRECISION=$IS_MIXED_PRECISION \
              -DCMAKE_BUILD_TYPE=RelWithDebInfo \
              -DQMC_DATA=$QMC_DATA_DIR \
              ${GITHUB_WORKSPACE}
      ;;
      *"TeslaV100-ICX23-MPI-CUDA-AFQMC"*)
        echo "Configure for building with CUDA and AFQMC  " \
             "using OneAPI ICX23 " \
        
        source /opt/intel/oneapi/setvars.sh

        echo "Set PATH to cuda-12.1"
        export PATH=/usr/local/cuda-12.1/bin:$PATH
        echo "Set CUDACXX CMake environment variable to nvcc cuda 12.1"
        export CUDACXX=/usr/local/cuda-12.1/bin/nvcc

        export OMPI_CC=/opt/intel/oneapi/compiler/2023.1.0/linux/bin/icx
        export OMPI_CXX=/opt/intel/oneapi/compiler/2023.1.0/linux/bin/icpx

        # Confirm that cuda 12.1 gets picked up by the compiler
        $OMPI_CXX -v

        # Make current environment variables available to subsequent steps
        echo "PATH=$PATH" >> $GITHUB_ENV
        echo "CUDACXX=/usr/local/cuda-12.1/bin/nvcc" >> $GITHUB_ENV        
        echo "OMPI_CC=/opt/intel/oneapi/compiler/2023.1.0/linux/bin/icx" >> $GITHUB_ENV
        echo "OMPI_CXX=/opt/intel/oneapi/compiler/2023.1.0/linux/bin/icpx" >> $GITHUB_ENV

        cmake -GNinja \
              -DCMAKE_C_COMPILER=/usr/lib64/openmpi/bin/mpicc \
              -DCMAKE_CXX_COMPILER=/usr/lib64/openmpi/bin/mpicxx \
              -DMPIEXEC_EXECUTABLE=/usr/lib64/openmpi/bin/mpirun \
              -DBUILD_AFQMC=ON \
              -DENABLE_CUDA=ON \
              -DQMC_GPU_ARCHS=sm_70 \
              -DQMC_COMPLEX=$IS_COMPLEX \
              -DQMC_MIXED_PRECISION=$IS_MIXED_PRECISION \
              -DCMAKE_BUILD_TYPE=RelWithDebInfo \
              -DQMC_DATA=$QMC_DATA_DIR \
              ${GITHUB_WORKSPACE}
      ;;
    esac
    ;;

  build)
    # Verify nvcc 
    which nvcc
    cd ${GITHUB_WORKSPACE}/../qmcpack-build
    ninja
    ;;
   
  test)
    echo "Enabling OpenMPI oversubscription"
    export OMPI_MCA_rmaps_base_oversubscribe=1
    export OMPI_MCA_hwloc_base_binding_policy=none
    echo "Set the management layer to ucx"
    export OMPI_MCA_pml=ucx
    # Avoid polluting the stderr output with libfabric error message
    export OMPI_MCA_btl=self
    # Clang helper threads used by target nowait is very broken. Disable this feature
    export LIBOMP_USE_HIDDEN_HELPER_TASK=0

    if [[ "${GH_JOBNAME}" =~ (-Offload) ]]
    then
      export LD_LIBRARY_PATH=/usr/local/cuda-11.2/lib64:${LD_LIBRARY_PATH}
    else
      export LD_LIBRARY_PATH=/usr/local/cuda-21.1/lib64:${LD_LIBRARY_PATH}
    fi

    if [[ "${GH_JOBNAME}" =~ (ICX23) ]]
    then
       source /opt/intel/oneapi/setvars.sh
    fi

    echo "Running deterministic tests"
    cd ${GITHUB_WORKSPACE}/../qmcpack-build
    ctest --output-on-failure -L deterministic -j 32
    ;;
    
esac
