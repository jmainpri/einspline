#define BLOCK_SIZE 64

#include <stdio.h>
#include "multi_bspline.h"

__constant__ float A[48];

typedef struct
{
  float *coefs_real, *coefs_imag;
  uint3 stride;
  float3 gridInv;
  int num_splines;
} multi_UBspline_3d_c_cuda;


multi_UBspline_3d_c_cuda*
create_CUDA_multi_UBspline_3d_c (multi_UBspline_3d_c* spline)
{
  multi_UBspline_3d_c_cuda *cuda_spline =
    (multi_UBspline_3d_c_cuda*) malloc (sizeof (multi_UBspline_3d_c_cuda*));
  
  cuda_spline->num_splines = spline->num_splines;

  int Nx = spline->x_grid.num+3;
  int Ny = spline->y_grid.num+3;
  int Nz = spline->z_grid.num+3;

  int N = spline->num_splines;
  if ((N%BLOCK_SIZE) != 0)
    N += 64 - (N%BLOCK_SIZE);
  cuda_spline->stride.x = Ny*Nz*N;
  cuda_spline->stride.y = Nz*N;
  cuda_spline->stride.z = N;

  size_t size = Nx*Ny*Nz+N*sizeof(float);

  cudaMalloc((void**)&(cuda_spline->coefs_real), size);
  cudaMalloc((void**)&(cuda_spline->coefs_imag), size);
  
  float *spline_buff = (float*)malloc(size);

  for (int ix=0; ix<Nx; ix++)
    for (int iy=0; iy<Ny; iy++)
      for (int iz=0; iz<Nz; iz++) 
	for (int isp=0; isp<spline->num_splines; isp++) {
	  spline_buff[ix*cuda_spline->stride.x +
		      iy*cuda_spline->stride.y +
		      iz*cuda_spline->stride.z + isp] =
	    spline->coefs[ix*spline->x_stride +
			  iy*spline->y_stride +
			  iz*spline->z_stride + isp].real();
	}
  cudaMemcpy(cuda_spline->coefs_real, spline_buff, size, cudaMemcpyHostToDevice);

  for (int ix=0; ix<Nx; ix++)
    for (int iy=0; iy<Ny; iy++)
      for (int iz=0; iz<Nz; iz++) 
	for (int isp=0; isp<spline->num_splines; isp++) {
	  spline_buff[ix*cuda_spline->stride.x +
		      iy*cuda_spline->stride.y +
		      iz*cuda_spline->stride.z + isp] =
	    spline->coefs[ix*spline->x_stride +
			  iy*spline->y_stride +
			  iz*spline->z_stride + isp].imag();
	}
  cudaMemcpy(cuda_spline->coefs_imag, spline_buff, size, cudaMemcpyHostToDevice);

  free(spline_buff);

  return cuda_spline;
}



__global__ static void
eval_multi_multi_UBspline_3d_c_cuda (float *pos, float3 drInv, 
				     float *coefs_real, float *coefs_imag,
				     float *vals[], uint3 strides)
{
  int block = blockIdx.x;
  int thr   = threadIdx.x;
  int ir    = blockIdx.y;
  int off   = block*BLOCK_SIZE+thr;

  __shared__ float *myval;
  __shared__ float abc[64], coefs[2*BLOCK_SIZE];

  // __shared__ float pos_s[BLOCK_SIZE];
  // int ir1 = (ir >> 4)*64;
  // int ir2 = (ir & 15)*4;
  // pos_s[thr] = pos[ir1+thr];
  // __syncthreads();
  // float3 r;
  // r.x = pos_s[ir2+0];
  // r.y = pos_s[ir2+1];
  // r.z = pos_s[ir2+2];
  __shared__ float3 r;
  if (thr == 0) {
    r.x = pos[4*ir+0];
    r.y = pos[4*ir+1];
    r.z = pos[4*ir+2];
    myval = vals[ir];
  }
  __syncthreads();
  
  int3 index;
  float3 t;
  float s, sf;
  float4 tp[3];

  s = r.x * drInv.x;
  sf = floor(s);
  index.x = (int)sf;
  t.x = s - sf;

  s = r.y * drInv.y;
  sf = floor(s);
  index.y = (int)sf;
  t.y = s - sf;

  s = r.z * drInv.z;
  sf = floor(s);
  index.z = (int)sf;
  t.z = s - sf;
  
  tp[0] = make_float4(1.0, t.x, t.x*t.x, t.x*t.x*t.x);
  tp[1] = make_float4(1.0, t.y, t.y*t.y, t.y*t.y*t.y);
  tp[2] = make_float4(1.0, t.z, t.z*t.z, t.z*t.z*t.z);

  __shared__ float a[4], b[4], c[4];
  if (thr < 4) {
    a[thr] = A[4*thr+0]*tp[0].x + A[4*thr+1]*tp[0].y + A[4*thr+2]*tp[0].z + A[4*thr+3]*tp[0].z;
    b[thr] = A[4*thr+0]*tp[1].x + A[4*thr+1]*tp[1].y + A[4*thr+2]*tp[1].z + A[4*thr+3]*tp[1].z;
    c[thr] = A[4*thr+0]*tp[2].x + A[4*thr+1]*tp[2].y + A[4*thr+2]*tp[2].z + A[4*thr+3]*tp[2].z;
//     a[0] = A[ 0]*tp[0].x + A[ 1]*tp[0].y + A[ 2]*tp[0].z + A[ 3]*tp[0].w;
//     a[1] = A[ 4]*tp[0].x + A[ 5]*tp[0].y + A[ 6]*tp[0].z + A[ 7]*tp[0].w;
//     a[2] = A[ 8]*tp[0].x + A[ 9]*tp[0].y + A[10]*tp[0].z + A[11]*tp[0].w;
//     a[3] = A[12]*tp[0].x + A[13]*tp[0].y + A[14]*tp[0].z + A[15]*tp[0].w;
    
//     b[0] = A[ 0]*tp[1].x + A[ 1]*tp[1].y + A[ 2]*tp[1].z + A[ 3]*tp[1].w;
//     b[1] = A[ 4]*tp[1].x + A[ 5]*tp[1].y + A[ 6]*tp[1].z + A[ 7]*tp[1].w;
//     b[2] = A[ 8]*tp[1].x + A[ 9]*tp[1].y + A[10]*tp[1].z + A[11]*tp[1].w;
//     b[3] = A[12]*tp[1].x + A[13]*tp[1].y + A[14]*tp[1].z + A[15]*tp[1].w;
    
//     c[0] = A[ 0]*tp[2].x + A[ 1]*tp[2].y + A[ 2]*tp[2].z + A[ 3]*tp[2].w;
//     c[1] = A[ 4]*tp[2].x + A[ 5]*tp[2].y + A[ 6]*tp[2].z + A[ 7]*tp[2].w;
//     c[2] = A[ 8]*tp[2].x + A[ 9]*tp[2].y + A[10]*tp[2].z + A[11]*tp[2].w;
//     c[3] = A[12]*tp[2].x + A[13]*tp[2].y + A[14]*tp[2].z + A[15]*tp[2].w;
  }
  __syncthreads();

  int i = (thr>>4)&3;
  int j = (thr>>2)&3;
  int k = (thr & 3);
  
  abc[thr] = a[i]*b[j]*c[k];
  __syncthreads();


  float val_real = 0.0;
  float val_imag = 0.0;
  val_real = val_imag = 0.0;
  for (int i=0; i<4; i++) {
    for (int j=0; j<4; j++) {
      float *base_real = coefs_real + (index.x+i)*strides.x + (index.y+j)*strides.y + index.z*strides.z;
      float *base_imag = coefs_imag + (index.x+i)*strides.x + (index.y+j)*strides.y + index.z*strides.z;
      for (int k=0; k<4; k++) {
  	val_real += abc[16*i+4*j+k] * base_real[off+k*strides.z];
  	val_imag += abc[16*i+4*j+k] * base_imag[off+k*strides.z];
      }
    }
  }
  // for (int i=0; i<4; i++) {
  //   for (int j=0; j<4; j++) {
  //     float *base_real = coefs_real + (index.x+i)*strides.x + (index.y+j)*strides.y + index.z*strides.z;
  //     float *base_imag = coefs_imag + (index.x+i)*strides.x + (index.y+j)*strides.y + index.z*strides.z;
  //     for (int k=0; k<4; k++) {
  // 	coefs[thr]            = base_real[(2*block+0)*BLOCK_SIZE+thr];
  // 	coefs[thr+BLOCK_SIZE] = base_real[(2*block+1)*BLOCK_SIZE+thr];
  // 	__syncthreads();
  // 	val_real += abc[16*i+4*j+k] * coefs[2*thr+0];
  // 	val_imag += abc[16*i+4*j+k] * coefs[2*thr+1];
  //     }
  //   }
  // }
  __shared__ float buff[2*BLOCK_SIZE];
  buff[2*thr+0] = val_real;
  buff[2*thr+1] = val_imag;
  __syncthreads();
  myval[off] = buff[thr];
  myval[off+BLOCK_SIZE] = buff[thr+BLOCK_SIZE];

//   myval[2*off+0] = val_real;
//   myval[2*off+1] = val_imag;
  //myval[off+BLOCK_SIZE] = val_imag;
  //vals_real[ir][offset] = val_real;
  //vals_imag[ir][offset] = val_imag;
}



__global__ static void
eval_multi_multi_UBspline_3d_c_vgh_cuda (float *pos, float3 drInv, 
					 float *coefs_real, float *coefs_imag,
					 float *vals[], float *grads[], float *hess[],
					 uint3 strides)
{
  int block = blockIdx.x;
  int thr   = threadIdx.x;
  int ir    = blockIdx.y;
  int off   = block*BLOCK_SIZE+thr;

  __shared__ float *myval, *mygrad, *myhess;
  __shared__ float3 r;
  if (thr == 0) {
    r.x = pos[4*ir+0];
    r.y = pos[4*ir+1];
    r.z = pos[4*ir+2];
    myval  = vals[ir];
    mygrad = grads[ir];
    myhess = hess[ir];
  }
  __syncthreads();
  
  int3 index;
  float3 t;
  float s, sf;
  float4 tp[3];

  s = r.x * drInv.x;
  sf = floor(s);
  index.x = (int)sf;
  t.x = s - sf;

  s = r.y * drInv.y;
  sf = floor(s);
  index.y = (int)sf;
  t.y = s - sf;

  s = r.z * drInv.z;
  sf = floor(s);
  index.z = (int)sf;
  t.z = s - sf;
  
  tp[0] = make_float4(1.0, t.x, t.x*t.x, t.x*t.x*t.x);
  tp[1] = make_float4(1.0, t.y, t.y*t.y, t.y*t.y*t.y);
  tp[2] = make_float4(1.0, t.z, t.z*t.z, t.z*t.z*t.z);

  // First 4 of a are value, second 4 are derivative, last four are
  // second derivative.
  __shared__ float a[12], b[12], c[12];
  if (thr < 12) {
    a[thr] = A[4*thr+0]*tp[0].x + A[4*thr+1]*tp[0].y + A[4*thr+2]*tp[0].z + A[4*thr+3]*tp[0].z;
    b[thr] = A[4*thr+0]*tp[1].x + A[4*thr+1]*tp[1].y + A[4*thr+2]*tp[1].z + A[4*thr+3]*tp[1].z;
    c[thr] = A[4*thr+0]*tp[2].x + A[4*thr+1]*tp[2].y + A[4*thr+2]*tp[2].z + A[4*thr+3]*tp[2].z;
  }
  __syncthreads();

  float v_r = 0.0;
  float v_i = 0.0;
  float g0_r=0.0, g0_i=0.0, g1_r=0.0, g1_i=0.0, g2_r=0.0, g2_i=0.0, 
    h00_r=0.0, h00_i=0.0, h01_r=0.0, h01_i=0.0, h02_r=0.0, h02_i=0.0, 
    h11_r=0.0, h11_i=0.0, h12_r=0.0, h12_i=0.0, h22_r=0.0, h22_i=0.0;
  for (int i=0; i<4; i++) {
    for (int j=0; j<4; j++) {
      float *base_real = coefs_real + (index.x+i)*strides.x + (index.y+j)*strides.y + index.z*strides.z;
      float *base_imag = coefs_imag + (index.x+i)*strides.x + (index.y+j)*strides.y + index.z*strides.z;
      for (int k=0; k<4; k++) {
	float cr = base_real[off+k*strides.z];
	float ci = base_imag[off+k*strides.z];
	float abc;
	abc = a[i+0] * b[j+0] * c[k+0];  v_r   += abc * cr;  v_i   += abc * ci;
	abc = a[i+4] * b[j+0] * c[k+0];  g0_r  += abc * cr;  g0_i  += abc * ci;
	abc = a[i+0] * b[j+4] * c[k+0];  g1_r  += abc * cr;  g1_i  += abc * ci;
	abc = a[i+0] * b[j+0] * c[k+4];  g2_r  += abc * cr;  g2_i  += abc * ci;
	abc = a[i+8] * b[j+0] * c[k+0];  h00_r += abc * cr;  h00_i += abc * ci;
	abc = a[i+4] * b[j+4] * c[k+0];  h01_r += abc * cr;  h01_i += abc * ci;
	abc = a[i+4] * b[j+0] * c[k+4];  h02_r += abc * cr;  h02_i += abc * ci;
	abc = a[i+0] * b[j+8] * c[k+0];  h11_r += abc * cr;  h11_i += abc * ci;
	abc = a[i+0] * b[j+4] * c[k+4];  h12_r += abc * cr;  h12_i += abc * ci;
	abc = a[i+0] * b[j+0] * c[k+8];  h22_r += abc * cr;  h22_i += abc * ci; 

	// g0_r  +=     a[i+4] * b[j+0] * c[k+0] * cr;	g0_i  += a[i+4] * b[j+0] * c[k+0] * ci;
	// g1_r  +=     a[i+0] * b[j+4] * c[k+0] * cr;	g1_i  += a[i+0] * b[j+4] * c[k+0] * ci;
	// g2_r  +=     a[i+0] * b[j+0] * c[k+4] * cr;	g2_i  += a[i+0] * b[j+0] * c[k+4] * ci;

	// h00_r +=     a[i+8] * b[j+0] * c[k+0] * cr;     h00_i += a[i+8] * b[j+0] + c[k+0] * ci;
	// h01_r +=     a[i+4] * b[j+4] * c[k+0] * cr;     h01_i += a[i+4] * b[j+4] + c[k+0] * ci;
	// h02_r +=     a[i+4] * b[j+0] * c[k+4] * cr;     h02_i += a[i+4] * b[j+0] + c[k+4] * ci;
	// h11_r +=     a[i+0] * b[j+8] * c[k+0] * cr;     h11_i += a[i+0] * b[j+8] + c[k+0] * ci;
	// h12_r +=     a[i+0] * b[j+4] * c[k+4] * cr;     h12_i += a[i+0] * b[j+4] + c[k+4] * ci;
	// h22_r +=     a[i+0] * b[j+0] * c[k+8] * cr;     h22_i += a[i+0] * b[j+0] + c[k+8] * ci;
      }
    }
  }
  g0_r *= drInv.x; g0_i *= drInv.x;
  g1_r *= drInv.y; g1_i *= drInv.y;
  g2_r *= drInv.z; g2_i *= drInv.z;

  h00_r *= drInv.x * drInv.x;  h00_i *= drInv.x * drInv.x;
  h01_r *= drInv.x * drInv.y;  h01_i *= drInv.x * drInv.y;
  h02_r *= drInv.x * drInv.z;  h02_i *= drInv.x * drInv.z;
  h11_r *= drInv.y * drInv.y;  h11_i *= drInv.y * drInv.y;
  h12_r *= drInv.y * drInv.z;  h12_i *= drInv.y * drInv.z;
  h22_r *= drInv.z * drInv.z;  h22_i *= drInv.z * drInv.z;

  __shared__ float buff[6*BLOCK_SIZE];

  buff[2*thr+0] = v_r;  buff[2*thr+1] = v_i;
  __syncthreads();
  myval[off] = buff[thr];    
  myval[off+BLOCK_SIZE] = buff[thr+BLOCK_SIZE];

  buff[6*thr+0] = g0_r;  buff[6*thr+1] = g0_i;
  buff[6*thr+2] = g1_r;  buff[6*thr+3] = g1_i;
  buff[6*thr+4] = g2_r;  buff[6*thr+5] = g2_i;
  __syncthreads();
  for (int i=0; i<6; i++) 
    mygrad[(6*block+i)*BLOCK_SIZE+thr] = buff[i*BLOCK_SIZE+thr]; 
  __syncthreads();

  // Write first half of Hessians
  if (thr < 32) {
    buff[12*thr+0]  = h00_r;    buff[12*thr+1]  = h00_i;
    buff[12*thr+2]  = h01_r;    buff[12*thr+3]  = h01_i;
    buff[12*thr+4]  = h02_r;    buff[12*thr+5]  = h02_i;
    buff[12*thr+6]  = h11_r;    buff[12*thr+7]  = h11_i;
    buff[12*thr+8]  = h12_r;    buff[12*thr+9]  = h12_i;
    buff[12*thr+10] = h22_r;    buff[12*thr+11] = h22_i;
    __syncthreads();
    for (int i=0; i<6; i++) 
      myhess[(12*block+i)*BLOCK_SIZE+thr] = buff[i*BLOCK_SIZE+thr];
  }
//   __syncthreads();
//   if (thr >= 32) {
//     int t = thr-32;
//     buff[12*t+0]  = h00_r;    buff[12*t+1]  = h00_i;
//     buff[12*t+2]  = h01_r;    buff[12*t+3]  = h01_i;
//     buff[12*t+4]  = h02_r;    buff[12*t+5]  = h02_i;
//     buff[12*t+6]  = h11_r;    buff[12*t+7]  = h11_i;
//     buff[12*t+8]  = h12_r;    buff[12*t+9]  = h12_i;
//     buff[12*t+10] = h22_r;    buff[12*t+11] = h22_i;
//     for (int i=0; i<6; i++) 
//       myhess[12*((i+6+block)*BLOCK_SIZE)+t] = buff[i*BLOCK_SIZE+t];
//   }

}

				    


static void *
test_multi_cuda(void *thread)
{
//   CUcontext ctx;
//   CUdevice dev;
//   cuDeviceGet (&dev, (int)(size_t)thread);
//   cuCtxCreate(&ctx, CU_CTX_SCHED_YIELD, dev);

//   int deviceCount;
//   cudaGetDeviceCount(&deviceCount);

  cudaSetDevice((int)(size_t)thread);
  fprintf (stderr, "In thread %p\n", thread);

  int numWalkers = 500;
  float *coefs  ,  __device__ *vals[numWalkers], *grads[numWalkers], *hess[numWalkers];
  float *coefs_real_d, *coefs_imag_d, __device__ **vals_d, **grads_d, **hess_d;
  float *r_d, *r_h;
  int xs, ys, zs, N;
  int Nx, Ny, Nz;

  N = 128;
  Nx = Ny = Nz = 16;
  xs = Ny*Nz*N;
  ys = Nz*N;
  zs = N;

  float3 drInv;
  drInv.x = 1.0/float(Nx);
  drInv.y = 1.0/float(Ny);
  drInv.z = 1.0/float(Nz);

  // Setup Bspline coefficients
  int size = Nx*Ny*Nz*N*sizeof(float);
  posix_memalign((void**)&coefs, 16, size);
  for (int ix=0; ix<Nx; ix++)
    for (int iy=0; iy<Ny; iy++)
      for (int iz=0; iz<Nz; iz++)
	for (int n=0; n<N; n++)
	  coefs[ix*xs + iy*ys + iz*zs + n] = drand48();


  fprintf (stderr, "Filled in coefs.\n");

  // Setup values
  //posix_memalign((void**)&vals, 16, N*sizeof(float));

  // cudaMemcpy(r_d, r, numWalkers*sizeof(float3), cudaMemcpyHostToDevice);

  
  fprintf (stderr, "size = %d\n", size);
  
  // Setup CUDA coefficients
  fprintf (stderr, "Before first CUDA mallocs.\n");
  cudaMalloc((void**)&coefs_real_d, 2*size);
  cudaMalloc((void**)&coefs_imag_d, 2*size);
  fprintf (stderr, "Before Memcpy.\n");
  cudaMemcpy(coefs_real_d, coefs, size, cudaMemcpyHostToDevice);
  cudaMemcpy(coefs_imag_d, coefs, size, cudaMemcpyHostToDevice);
  fprintf (stderr, "After Memcpy.\n");  

  // Setup device value storage
  int numVals = 2*N*numWalkers*10;
  float *valBlock_d, *valBlock_h;
  cudaMalloc((void**)&(valBlock_d),     numVals*sizeof(float));
  cudaMallocHost((void**)&(valBlock_h), numVals*sizeof(float));
  cudaMalloc((void**)&(vals_d), 2*numWalkers*sizeof(float*));
  cudaMalloc((void**)&(grads_d), 2*numWalkers*sizeof(float*));
  cudaMalloc((void**)&(hess_d), 2*numWalkers*sizeof(float*));
  fprintf (stderr, "valBlock_d = %p\n", valBlock_d);
  for (int i=0; i<numWalkers; i++) {
    vals[i]  = valBlock_d + 2*i*N;
    grads[i] = valBlock_d + 2*N*numWalkers + 6*i*N;
    hess[i]  = valBlock_d + 8*N*numWalkers + 12*i*N;
  }
  cudaMemcpy(vals_d,  vals,  numWalkers*sizeof(float*), cudaMemcpyHostToDevice);
  cudaMemcpy(grads_d, grads, numWalkers*sizeof(float*), cudaMemcpyHostToDevice);
  cudaMemcpy(hess_d,  hess,  numWalkers*sizeof(float*), cudaMemcpyHostToDevice);
  
  fprintf (stderr, "Finished cuda allocations.\n");


  // Setup walker positions
  cudaMalloc((void**)&(r_d),     4*numWalkers*sizeof(float));
  cudaMallocHost((void**)&(r_h), 4*numWalkers*sizeof(float));

  for (int ir=0; ir<numWalkers; ir++) {
    r_h[4*ir+0] = 0.5*drand48();
    r_h[4*ir+1] = 0.5*drand48();
    r_h[4*ir+2] = 0.5*drand48();
  }

  uint3 strides;
  strides.x = xs;
  strides.y = ys;
  strides.z = zs;

  dim3 dimBlock(BLOCK_SIZE);
  dim3 dimGrid(N/BLOCK_SIZE,numWalkers);
  
  clock_t start, end;

  start = clock();
  for (int i=0; i<10000; i++) {
    if ((i%1000) == 0) 
      fprintf (stderr, "i = %d\n", i);
    cudaMemcpy(r_d, r_h, 4*numWalkers*sizeof(float), cudaMemcpyHostToDevice);
    eval_multi_multi_UBspline_3d_c_cuda<<<dimGrid,dimBlock>>> 
       (r_d, drInv, coefs_real_d, coefs_imag_d, 
        vals_d, strides);
    // eval_multi_multi_UBspline_3d_cuda_c<<<dimGrid,dimBlock>>> 
    //   (r_d, drInv, coefs_real_d, coefs_imag_d, 
    //    valBlock_d, valBlock_d+numVals/2, strides);
    //cudaMemcpy(valBlock_h, valBlock_d, numVals*sizeof(float), cudaMemcpyDeviceToHost);
  }
  end = clock();
  double time = (double)(end-start)/(double)((double)CLOCKS_PER_SEC*(double)10000*N*numWalkers);
  fprintf (stderr, "VGH evals per second = %1.8e\n", 1.0/time);


  start = clock();
  for (int i=0; i<10000; i++) {
    if ((i%1000) == 0) 
      fprintf (stderr, "i = %d\n", i);
    cudaMemcpy(r_d, r_h, 4*numWalkers*sizeof(float), cudaMemcpyHostToDevice);
    eval_multi_multi_UBspline_3d_c_vgh_cuda<<<dimGrid,dimBlock>>> 
       (r_d, drInv, coefs_real_d, coefs_imag_d, 
        vals_d, grads_d, hess_d, strides);
  }
  end = clock();
  time = (double)(end-start)/(double)((double)CLOCKS_PER_SEC*(double)10000*N*numWalkers);
  fprintf (stderr, "Evals per second = %1.8e\n", 1.0/time);
  
  cudaFree (valBlock_d);
  cudaFree (vals_d);
  cudaFree (coefs_real_d);
  cudaFree (coefs_imag_d);
  cudaFree (r_d);

  return NULL;

  // cudaMemcpy (vals, vals_d, N*sizeof(float), cudaMemcpyDeviceToHost);

  // float vals2[N];
  
  // for (int n=0; n<N; n++) {
  //   vals2[n] = 0.0;
  //   int index=0;
  //   for(int i=0; i<4; i++)
  //     for (int j=0; j<4; j++)
  // 	for (int k=0; k<4; k++)  {
  // 	  vals2[n] += abc[index] * coefs[(ix+i)*xs+(iy+j)*ys+(iz+k)*zs+n];
  // 	  index++;
  // 	}
  // }


  // for (int i=0; i<N/256; i++)	
  //   fprintf (stderr, "%1.9f %1.9f\n", vals[i], vals2[i]); 


  // cudaFree(abc_d);
  // cudaFree(coefs_d);
  // cudaFree(vals_d);
}




main()
{
  int deviceCount;
  cudaGetDeviceCount(&deviceCount);
  fprintf (stderr, "Detected %d CUDA devices.\n", deviceCount);

  // test_cuda();

  for (int device = 0; device < deviceCount; ++device) {
    cudaDeviceProp deviceProp;
    cudaGetDeviceProperties(&deviceProp, device);
    fprintf (stderr, "Device %d:\n", device);
    fprintf (stderr, "  Global memory:     %10d\n",
	     deviceProp.totalGlobalMem);
    fprintf (stderr, "  MultiProcessors:   %10d\n",
	     deviceProp.multiProcessorCount);
    fprintf (stderr, "  Registers:         %10d\n", 
	     deviceProp.regsPerBlock);
    fprintf (stderr, "  Constant memory:   %10d\n", 
	     deviceProp.totalConstMem);
    fprintf (stderr, "  Shared memory:     %10d\n", 
	     deviceProp.sharedMemPerBlock);
  }

  //  pthread_t threads[deviceCount];

  // for (int device = 0; device < deviceCount; device++) 
  //   pthread_create (&(threads[device]), NULL, test_multi_cuda, (void*)device);
  // cutStartThread((CUT_THREADROUTINE)test_multi_cuda,(void*)device);
  test_multi_cuda((void*)0);

  //  pthread_exit(NULL);
  //test_multi_cuda();
}