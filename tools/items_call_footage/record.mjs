#!/usr/bin/env node
// Records deck.html (a spreadsheet and a slide, rendered by a real browser, every frame a pure function of time) into an Ogg Theora video for the CALL window of the show.
//
//   node tools/items_call_footage/record.mjs stills 1,5,9,13,17,20 /tmp/stills   # PNGs of the page at those seconds (look at them first)
//   node tools/items_call_footage/record.mjs film out.ogv [width height quality]  # the clip: 30 fps, default 960x540, Theora quality 0-63 (default 40)
//
// Needs: puppeteer-core (~/node_modules) with the headless Chrome of ~/.cache/puppeteer, ffmpeg (scaling and pixel format) and the Theora encoder of theora_encode.c, which this script
// compiles against Homebrew's libtheora (`brew install theora`) the first time. The clip is silent; it loops (the last frames fade back onto the first).
import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(homedir(), "node_modules") + "/");
const puppeteer = require("puppeteer-core");

const shellRoot = join(homedir(), ".cache/puppeteer/chrome-headless-shell");
const version = readdirSync(shellRoot).sort().pop();
const executablePath = join(shellRoot, version, readdirSync(join(shellRoot, version))[0], "chrome-headless-shell");
const FPS = 30;

function encoder() {
  const binary = join(homedir(), ".cache/items-call-footage/theora_encode");
  if (!existsSync(binary)) {
    mkdirSync(dirname(binary), { recursive: true });
    execFileSync("clang", ["-O2", "-o", binary, join(here, "theora_encode.c"), "-I/opt/homebrew/include", "-L/opt/homebrew/lib", "-ltheoraenc", "-ltheoradec", "-logg"], { stdio: "inherit" });
  }
  return binary;
}

const [mode, ...args] = process.argv.slice(2);
const browser = await puppeteer.launch({ executablePath, headless: "shell", args: ["--no-sandbox", "--font-render-hinting=none", "--hide-scrollbars"] });
const page = await browser.newPage();
page.on("console", (message) => console.log("page:", message.text()));
await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(join(here, "deck.html")).href);
const length = await page.evaluate(() => window.CLIP_LENGTH);

if (mode === "stills") {
  const dir = resolve(args[1] ?? "/tmp/call_stills");
  mkdirSync(dir, { recursive: true });
  for (const t of args[0].split(",").map(Number)) {
    await page.evaluate((time) => window.seek(time), t);
    await page.screenshot({ path: join(dir, `t${String(t).padStart(5, "0")}.png`) });
  }
  console.log("stills in", dir);
} else if (mode === "film") {
  const out = resolve(args[0]);
  const width = Number(args[1] ?? 960), height = Number(args[2] ?? 540), quality = Number(args[3] ?? 40);
  const ffmpeg = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-i", "-", "-vf", `scale=${width}:${height}:flags=lanczos,format=yuv420p`, "-f", "rawvideo", "-"], { stdio: ["pipe", "pipe", "inherit"] });
  const theora = spawn(encoder(), [String(width), String(height), String(FPS), "1", String(quality), out], { stdio: ["pipe", "inherit", "inherit"] });
  ffmpeg.stdout.pipe(theora.stdin);
  const done = new Promise((ok, fail) => theora.on("close", (code) => (code === 0 ? ok() : fail(new Error("theora_encode exited " + code)))));
  const frames = Math.round(length * FPS);
  for (let i = 0; i < frames; i++) {
    await page.evaluate((time) => window.seek(time), i / FPS);
    const png = await page.screenshot({ type: "png" });
    if (!ffmpeg.stdin.write(png)) await new Promise((ok) => ffmpeg.stdin.once("drain", ok));
  }
  ffmpeg.stdin.end();
  await done;
  console.log(`${out}: ${frames} frames, ${length} s, ${width}x${height}`);
} else {
  console.error("usage: record.mjs stills <t,t,...> [dir] | film <out.ogv> [width height quality]");
  process.exitCode = 2;
}
await browser.close();
