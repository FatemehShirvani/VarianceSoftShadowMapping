# Source Layout

The live demo is intentionally deployable as a single `index.html` file for static hosting, but the embedded source is mirrored here for review:

- `app.js`: WebGPU setup, scene construction, UI wiring, render loop, and compute/render pass orchestration.
- `shaders/vssm.wgsl`: WGSL shader code for rasterization, shadow passes, moment filtering, VSSM, debug views, SAT, and hierarchy construction.
- `styles.css`: UI styles extracted from the demo page.

Regenerate these files from the deployable HTML with:

```bash
node tools/extract-source.js
```
