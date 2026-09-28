// Compiles settle.zig to WASM and inlines it (base64) into index.html.
// Usage: node build.mjs   (set ZIG=/path/to/zig if zig is not on PATH)
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = dirname(fileURLToPath(import.meta.url));
const wasmPath = join(dir, "settle.wasm");
const htmlPath = join(dir, "index.html");

execFileSync(process.env.ZIG || "zig", [
  "build-exe", "settle.zig",
  "-target", "wasm32-freestanding",
  "-mcpu=generic+simd128",
  "-fno-entry", "-rdynamic",
  "-O", "ReleaseSmall",
  "-femit-bin=settle.wasm",
], { cwd: dir, stdio: "inherit" });

const wasm = readFileSync(wasmPath);
const html = readFileSync(htmlPath, "utf8");
const re = /const WASM_B64 = "[^"]*";/;
if (!re.test(html)) throw new Error("WASM_B64 placeholder not found in index.html");
writeFileSync(htmlPath, html.replace(re, `const WASM_B64 = "${wasm.toString("base64")}";`));
console.log(`Inlined ${wasm.length} bytes of WASM into index.html`);
