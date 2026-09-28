// Compiles settle.zig to WASM and inlines it (base64) into the app and bench pages.
// Usage: node solver/build.mjs   (set ZIG=/path/to/zig if zig is not on PATH)
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = dirname(fileURLToPath(import.meta.url));
const pages = [join(dir, "..", "index.html"), join(dir, "..", "bench", "index.html")];

execFileSync(process.env.ZIG || "zig", [
  "build-exe", "settle.zig",
  "-target", "wasm32-freestanding",
  "-mcpu=generic+simd128",
  "-fno-entry", "-rdynamic",
  "-O", "ReleaseSmall",
  "-femit-bin=settle.wasm",
], { cwd: dir, stdio: "inherit" });

const b64 = readFileSync(join(dir, "settle.wasm")).toString("base64");
const re = /const WASM_B64 = "[^"]*";/;
for (const page of pages) {
  const html = readFileSync(page, "utf8");
  if (!re.test(html)) throw new Error(`WASM_B64 placeholder not found in ${page}`);
  writeFileSync(page, html.replace(re, `const WASM_B64 = "${b64}";`));
}
console.log(`Inlined ${Buffer.from(b64, "base64").length} bytes of WASM into ${pages.length} pages`);
