//////////////////////////////////////////////////////////////////////////////////////
// This file is distributed under the University of Illinois/NCSA Open Source License.
// See LICENSE file in top directory for details.
//
// Copyright (c) 2016 Jeongnim Kim and QMCPACK developers.
//
// File developed by: 
//
// File created by: Jeongnim Kim, jeongnim.kim@intel.com, Intel Corp.
//////////////////////////////////////////////////////////////////////////////////////
// -*- C++ -*-
/** @file algorithm.hpp
 *
 * SIMD version of functions in algorithm
 */
#ifndef QMCPLUSPLUS_SIMD_ALGORITHM_HPP
#define QMCPLUSPLUS_SIMD_ALGORITHM_HPP

namespace qmcplusplus {

  namespace simd 
  {

    /** simd version of copy_n( InputIt first, Size count, OutputIt result)
     * @param first starting address of the input
     * @param count number of elements to copy
     * @param result starting address of the output
     */
    template<typename T>
      inline T* copy_n(const T* restrict first, size_t count, T* restrict result)
      {
        ASSUME_ALIGNED(first); ASSUME_ALIGNED(result);
#pragma omp simd 
        for(size_t i=0; i<count;  ++i) result[i]=first[i];
        return result; 
      }

    template<typename T1, typename T2>
    inline T2 accumulate_n(const T1* restrict in, int n, T2 res)
      {
#pragma omp simd reduction(+:res)
        for(int i=0; i<n; ++i)
          res += in[i];
        return res;
      }
  } //simd namepsace

}
#endif
