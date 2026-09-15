# Variance Soft Shadow Mapping in WebGPU

A single-page WebGPU / WGSL demo comparing real-time shadow techniques in the same procedural scene.

The project implements and compares:

- No shadows baseline
- Hard shadow mapping
- PCF
- PCSS
- VSM
- SAVSM
- VSSM Hybrid
- VSSM Paper

The scene is procedural and does not require external meshes or textures.

## Run

Open the demo through a local HTTP server:

```bash
python -m http.server 8000
```

Then visit:

```text
http://127.0.0.1:8000/
```

On Windows, `run_demo.cmd` starts a local server and opens Chrome with WebGPU-friendly flags.

## Browser Notes

This project requires WebGPU. It is most reliable in Chrome or Edge on a machine with compatible GPU drivers.

The public `index.html` starts in a stable no-shadow baseline mode. Use the UI selectors to switch between the implemented shadow techniques.

## Report

See [report.pdf](report.pdf) for the implementation write-up and visual comparisons.
