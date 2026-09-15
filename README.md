# Variance Soft Shadow Mapping in WebGPU

WebGPU/WGSL implementation of Variance Soft Shadow Mapping (VSSM), based on the paper by Yang et al. The application compares classical shadow-map filtering methods and VSM-family soft-shadow methods in the same procedural scene.

Live demo:

```text
https://fatemehshirvani.github.io/assets/soft-shadows/demo.html
```

## Implemented Methods

- Hard shadow mapping
- Percentage-closer filtering (PCF)
- Percentage-closer soft shadows (PCSS)
- Variance shadow maps (VSM)
- Summed-area variance shadow maps (SAVSM)
- VSSM Paper mode
- VSSM Hybrid mode
- Ray tracing mode retained as a debugging reference

## Pipeline

The VSSM implementation follows a four-stage WebGPU pipeline:

1. Shadow and moments pass  
   The scene is rendered from the light. A depth texture and a moment texture are generated. The moment texture stores normalized linear depth moments `(z, z^2)`.

2. Summed-area table pass  
   A SAT is built over the moment texture using horizontal and vertical compute-shader prefix scans. This makes rectangular moment queries effectively constant-time.

3. Min-max hierarchy pass  
   A hierarchical shadow map is built by iterative 2x2 reductions over linearized depth. The hierarchy is used for early lit/umbra tests over larger filter kernels.

4. VSSM shading pass  
   The shader estimates average blocker depth from VSM moments, derives a PCSS-style penumbra radius, and evaluates filtered visibility using moments, hierarchy tests, subdivision, and fallback sampling.

## VSSM Details

The blocker-search phase replaces PCSS brute-force sampling with a moment-based estimate. Given average moments over the search kernel and receiver depth `t`, Chebyshev's inequality estimates the lit fraction. Under the two-plane assumption, the average blocker depth is reconstructed from the kernel mean and estimated occlusion probability.

The implementation treats kernels as unstable when the VSM mean-depth prerequisite is violated. Those regions are subdivided instead of trusting a single variance reconstruction.

### VSSM Paper Mode

Mode 7 follows the paper-oriented path:

- SAT moment queries for blocker and filter kernels
- uniform `m x m` subdivision
- VSM fast path for stable sub-kernels
- exact 3x3 PCF fallback for unstable sub-kernels
- contact-shadow correction when blocker and receiver depths are nearly coplanar

### VSSM Hybrid Mode

Mode 6 adds a more practical adaptive filter:

- uniform subdivision for blocker-depth estimation
- stack-based quad-tree traversal for final visibility filtering
- VSM accept, PCF leaf, or subdivide decisions per node
- more sampling concentrated in high-variance penumbra regions

This mode was added to reduce light leaking, bright spots, and instability on thin foliage and near contact-shadow regions.

## Interface And Debugging

The demo uses a split-screen comparison interface. Both views share the same scene and camera, but each side has independent technique selection and shadow parameters.

Available debug modes:

- shadow factor
- VSSM branch classification
- moment / Chebyshev values
- SAT delta against brute-force moment estimates

These were used to separate variance-related leakage from SAT precision issues and subdivision artifacts.

## Observations

- Hard shadow maps show aliasing.
- PCF smooths aliasing but produces nearly uniform blur rather than contact hardening.
- PCSS restores penumbra growth, but still pays a brute-force blocker-search cost.
- VSM and SAVSM are fast but leak light when a kernel spans multiple depth layers.
- VSSM Paper reduces this leakage through subdivision and fallback.
- VSSM Hybrid is the most stable practical variant in this implementation, especially for thin foliage and contact regions.

## Limitations

- The implementation uses a single light-space depth map. Kernels with three or more distinct depth layers can still violate the two-plane assumption.
- SAT accumulation uses floating-point textures, so large-radius queries may lose precision through four-corner subtraction.
- Full end-to-end GPU timing was not recorded consistently enough for a final quantitative performance table.

## Run Locally

The demo requires a WebGPU-enabled browser.

On Windows:

```text
run_demo.cmd
```

Or serve the folder manually:

```bash
python -m http.server 8000
```

Then open:

```text
http://127.0.0.1:8000/
```

See [report.pdf](report.pdf) for the full write-up.
