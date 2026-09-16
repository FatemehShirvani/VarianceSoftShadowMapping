const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");

function extract(startRe, endRe, name) {
  const start = html.search(startRe);
  if (start < 0) {
    throw new Error(`Missing ${name} start marker`);
  }
  const startMatch = html.slice(start).match(startRe);
  const contentStart = start + startMatch[0].length;
  const end = html.slice(contentStart).search(endRe);
  if (end < 0) {
    throw new Error(`Missing ${name} end marker`);
  }
  return html
    .slice(contentStart, contentStart + end)
    .replace(/^\r?\n/, "")
    .replace(/\s*$/, "") + "\n";
}

const outputs = {
  "src/styles.css": extract(/<style>/, /<\/style>/, "style"),
  "src/shaders/vssm.wgsl": extract(
    /<script type="x-shader\/wgsl" id="shaders">/,
    /<\/script>/,
    "WGSL shader"
  ),
  "src/app.js": extract(/<script type="module">/, /<\/script>/, "JavaScript app"),
};

for (const [relativePath, content] of Object.entries(outputs)) {
  const outputPath = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, content, "utf8");
  console.log(`wrote ${relativePath}`);
}
