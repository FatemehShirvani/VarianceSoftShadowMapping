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

On Windows, the most reliable way to run the demo is:

```text
run_demo.cmd
```

That script starts a local server and opens Chrome with WebGPU-friendly flags:

```text
--enable-unsafe-webgpu --ignore-gpu-blocklist --force-high-performance-gpu
```

You can also run it manually through a local HTTP server:

```bash
python -m http.server 8000
```

Then visit:

```text
http://127.0.0.1:8000/
```

## Browser Notes

This project requires WebGPU. It is most reliable in Chrome or Edge on a machine with compatible GPU drivers.

If the page says `No appropriate GPUAdapter found`, the browser exposes `navigator.gpu` but refuses to provide an adapter. Use `run_demo.cmd`, update the browser/GPU driver, or check `chrome://gpu` for WebGPU status.

The public `index.html` starts in a stable no-shadow baseline mode. Use the UI selectors to switch between the implemented shadow techniques.

## Report

See [report.pdf](report.pdf) for the implementation write-up and visual comparisons.
