#ifndef MULTI_BSPLINE_STRUCTS_CUDA_H
#define MULTI_BSPLINE_STRUCTS_CUDA_H

#define SPLINE_BLOCK_SIZE 64

__constant__ float Acuda[48];

////////
// 2D //
////////

typedef struct
{
  float *coefs;
  uint2 stride;
  float2 gridInv;
  int num_splines;
} multi_UBspline_2d_s_cuda;

typedef struct
{
  float *coefs_real, *coefs_imag;
  uint2 stride;
  float2 gridInv;
  int num_splines;
} multi_UBspline_2d_c_cuda;

typedef struct
{
  double *coefs;
  uint2 stride;
  double gridInv[2];
  int num_splines;
} multi_UBspline_2d_d_cuda;

typedef struct
{
  double *coefs_real, *coefs_imag;
  uint2 stride;
  double gridInv[2];
  int num_splines;
} multi_UBspline_2d_z_cuda;

////////
// 3D //
////////

typedef struct
{
  float *coefs;
  uint3 stride;
  float3 gridInv;
  int num_splines;
} multi_UBspline_3d_s_cuda;

typedef struct
{
  float *coefs_real, *coefs_imag;
  uint3 stride;
  float3 gridInv;
  int num_splines;
} multi_UBspline_3d_c_cuda;

typedef struct
{
  double *coefs;
  uint3 stride;
  double gridInv[3];
  int num_splines;
} multi_UBspline_3d_d_cuda;

typedef struct
{
  double *coefs_real, *coefs_imag;
  uint3 stride;
  double gridInv[3];
  int num_splines;
} multi_UBspline_3d_z_cuda;



#endif
