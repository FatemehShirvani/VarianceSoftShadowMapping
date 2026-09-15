# Variance Soft Shadow Mapping in WebGPU

WebGPU/WGSL implementation of Variance Soft Shadow Mapping (VSSM), based on Yang et al.'s VSSM formulation [7]. The application compares classical shadow-map filtering methods and VSM-family soft-shadow methods in the same procedural scene.

Live demo:

```text
https://fatemehshirvani.github.io/assets/soft-shadows/demo.html
```

## Context

Course project for the Image Synthesis course taught by Tamy Boubekeur at École Polytechnique. Developed in March-April 2026.

## Implemented Methods

- Hard shadow mapping [1]
- Percentage-closer filtering (PCF) [2]
- Percentage-closer soft shadows (PCSS) [3]
- Variance shadow maps (VSM) [4]
- Summed-area variance shadow maps (SAVSM) [6]
- VSSM Paper mode [7]
- VSSM Hybrid mode
- Ray tracing mode retained as a debugging reference

## Pipeline

The VSSM implementation follows a four-stage WebGPU pipeline:

1. Shadow and moments pass  
   The scene is rendered from the light, following the depth-map shadowing idea introduced by Williams [1]. A depth texture and a moment texture are generated. The moment texture stores normalized linear depth moments `(z, z^2)`, following the VSM representation of Donnelly and Lauritzen [4].

2. Summed-area table pass  
   A summed-area table (SAT) [5] is built over the moment texture using horizontal and vertical compute-shader prefix scans. This makes rectangular moment queries effectively constant-time and is the basis of the SAVSM-style filtering path [6].

3. Min-max hierarchy pass  
   A hierarchical shadow map is built by iterative 2x2 reductions over linearized depth. The hierarchy is used for early lit/umbra tests over larger filter kernels.

4. VSSM shading pass  
   The shader estimates average blocker depth from VSM moments, derives a PCSS-style penumbra radius, and evaluates filtered visibility using moments, hierarchy tests, subdivision, and fallback sampling.

## VSSM Details

The blocker-search phase replaces PCSS brute-force sampling [3] with the moment-based estimate from VSSM [7]. Given average moments over the search kernel and receiver depth `t`, Chebyshev's inequality estimates the lit fraction. Under the two-plane assumption, the average blocker depth is reconstructed from the kernel mean and estimated occlusion probability.

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
- PCSS restores penumbra growth [3], but still pays a brute-force blocker-search cost.
- VSM and SAVSM are fast [4, 6], but leak light when a kernel spans multiple depth layers.
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

## References

[1] Lance Williams. 1978. [Casting curved shadows on curved surfaces](https://dl.acm.org/doi/10.1145/965139.807402). SIGGRAPH.

[2] William T. Reeves, David H. Salesin, and Robert L. Cook. 1987. [Rendering antialiased shadows with depth maps](https://dl.acm.org/doi/10.1145/37402.37435). SIGGRAPH.

[3] Randima Fernando. 2005. [Percentage-Closer Soft Shadows](https://developer.download.nvidia.com/shaderlibrary/docs/shadow_PCSS.pdf). ACM SIGGRAPH Sketch.

[4] William Donnelly and Andrew Lauritzen. 2006. [Variance Shadow Maps](https://doi.org/10.1145/1111411.1111440). I3D.

[5] Franklin C. Crow. 1984. [Summed-area tables for texture mapping](https://dl.acm.org/doi/10.1145/800031.808600). SIGGRAPH.

[6] Andrew Lauritzen. 2007. [Summed-Area Variance Shadow Maps](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-8-summed-area-variance-shadow-maps). GPU Gems 3, Chapter 8.

[7] Baoguang Yang, Zhao Dong, Jieqing Feng, Hans-Peter Seidel, and Jan Kautz. 2010. [Variance Soft Shadow Mapping](https://jankautz.com/publications/VSSM_PG2010.pdf). Pacific Graphics / Computer Graphics Forum.
