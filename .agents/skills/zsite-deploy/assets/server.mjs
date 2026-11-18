// 三打哈部署服务器：单端口三服务（ZCode Sites 只对外暴露 3000 端口，全部在 3000 分流）。
//   /          → 游戏页面（Godot Web 导出静态文件，GAME_DIR 目录）
//   /files/    → 部署容器文件浏览/查看/下载（只读；根由 FILES_ROOTS 决定，默认 /app:/data）
//   WebSocket  → HTTP Upgrade 请求原样转发到 127.0.0.1:GODOT_PORT 的 Godot 无头联机服务器
//                （子进程由本进程拉起并守护重启；wss:// 在平台边缘终结 TLS 后落到这里）
// 零依赖（Node 内置模块）；index.wasm 预压缩为 .gz（满足单文件 ≤25MB 打包限制），
// 命中 Accept-Encoding: gzip 时以 Content-Encoding: gzip 透传，浏览器自动解压。
import { spawn } from "node:child_process";
import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { createServer } from "node:http";
import net from "node:net";
import { basename, dirname, extname, join, resolve, sep } from "node:path";

const GAME_DIR = resolve(process.env.GAME_DIR ?? "web");
// 允许浏览的根列表（Linux 用 : 分隔；本地 Windows 测试可用 ; 分隔避开盘符冒号）。
const FILES_ROOTS = (process.env.FILES_ROOTS ?? "/app:/data")
  .split(/[;:]/)
  .map((p) => p.trim())
  .filter(Boolean)
  .map((p) => resolve(p));
const PORT = Number(process.env.PORT ?? 3000);
const GODOT_PORT = Number(process.env.GODOT_PORT ?? 9080);

// 路径 p（绝对或相对根）落在任一根内 → 返回绝对路径；否则 undefined（越界拒绝）。
function safeResolve(rawPath) {
  let p;
  try {
    p = decodeURIComponent(String(rawPath ?? ""));
  } catch {
    return undefined;
  }
  if (!p) return FILES_ROOTS[0];
  for (const root of FILES_ROOTS) {
    const withSep = root.endsWith(sep) ? root : root + sep;
    const abs = resolve(p.startsWith("/") ? p : join(root, p));
    if (abs === root || abs.startsWith(withSep)) return abs;
  }
  return undefined;
}

function insideAnyRoot(abs) {
  return FILES_ROOTS.some((root) => {
    const withSep = root.endsWith(sep) ? root : root + sep;
    return abs === root || abs.startsWith(withSep);
  });
}

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".htm": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
  ".mp3": "audio/mpeg",
  ".wav": "audio/wav",
  ".pdf": "application/pdf",
};

function plain(res, status, msg) {
  res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8" }).end(msg);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function fmtSize(n) {
  if (n == null) return "—";
  if (n < 1024) return `${n} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = n;
  let i = -1;
  do {
    v /= 1024;
    i += 1;
  } while (v >= 1024 && i < units.length - 1);
  return `${v >= 100 ? v.toFixed(0) : v.toFixed(1)} ${units[i]}`;
}

function fmtTime(ms) {
  return ms == null ? "—" : new Date(ms).toISOString().replace("T", " ").slice(0, 19) + " UTC";
}

async function fileAt(path) {
  try {
    const info = await stat(path);
    return info.isFile() ? { path, size: info.size } : undefined;
  } catch {
    return undefined;
  }
}

function acceptsGzip(req) {
  return /gzip/i.test(req.headers["accept-encoding"] ?? "");
}

function sendFile(req, res, file, type, extraHeaders = {}) {
  res.writeHead(200, {
    "Content-Type": type,
    "Content-Length": file.size,
    "Cache-Control": "no-cache",
    ...extraHeaders,
  });
  if (req.method === "HEAD") return res.end();
  const stream = createReadStream(file.path);
  stream.on("error", () => res.destroy());
  stream.pipe(res);
}

// —— 游戏静态服务：/ → web/index.html；index.wasm 命中 gzip 时回退到预压缩的 .gz ——
async function handleGame(req, res, url) {
  let pathname;
  try {
    pathname = decodeURIComponent(url.pathname);
  } catch {
    return plain(res, 400, "Bad path");
  }
  const rel = pathname.replace(/^\/+/, "");
  const base = resolve(join(GAME_DIR, rel || "index.html"));
  if (base !== GAME_DIR && !base.startsWith(GAME_DIR + sep)) return plain(res, 403, "Forbidden");
  let file = (await fileAt(base)) ?? (await fileAt(join(base, "index.html")));
  let gz = false;
  if (!file && extname(base) === ".wasm" && acceptsGzip(req)) {
    file = await fileAt(`${base}.gz`);
    gz = Boolean(file);
  }
  if (!file) return plain(res, 404, "Not Found");
  const realExt = extname(gz ? base : file.path).toLowerCase();
  const type = MIME[realExt] ?? "application/octet-stream";
  const extra = gz ? { "Content-Encoding": "gzip", Vary: "Accept-Encoding" } : {};
  sendFile(req, res, file, type, extra);
}

// —— 文件查看/下载：/files/view 与 /files/download，?path= 绝对路径 ——
async function handleFileContent(req, res, url, disposition) {
  const abs = safeResolve(url.searchParams.get("path"));
  if (!abs) return plain(res, 403, "路径越界");
  const info = await stat(abs).catch(() => undefined);
  if (!info) return plain(res, 404, `不存在: ${abs}`);
  if (!info.isFile()) return plain(res, 400, "不是普通文件");
  const type = MIME[extname(abs).toLowerCase()] ?? "application/octet-stream";
  const encodedName = encodeURIComponent(basename(abs));
  sendFile(req, res, { path: abs, size: info.size }, type, {
    "Content-Disposition": `${disposition}; filename*=UTF-8''${encodedName}`,
  });
}

// —— 文件浏览：/files/（?path= 缺省为 FILES_ROOT）；path 指向文件时转为查看 ——
async function handleBrowse(req, res, url) {
  const abs = safeResolve(url.searchParams.get("path"));
  if (!abs) return plain(res, 403, "路径越界");
  const info = await stat(abs).catch(() => undefined);
  if (!info) return plain(res, 404, `不存在: ${abs}`);
  if (!info.isDirectory()) return handleFileContent(req, res, url, "inline");

  const dirents = await readdir(abs, { withFileTypes: true });
  const rows = await Promise.all(
    dirents.map(async (d) => {
      const full = join(abs, d.name);
      try {
        const s = await stat(full);
        return { name: d.name, dir: s.isDirectory(), size: s.size, mtime: s.mtimeMs };
      } catch {
        return { name: d.name, dir: d.isDirectory(), size: null, mtime: null };
      }
    }),
  );
  rows.sort((a, b) => Number(b.dir) - Number(a.dir) || a.name.localeCompare(b.name));

  const enc = encodeURIComponent;
  const q = (p) => `/files/?path=${enc(p)}`;
  const parent = dirname(abs);
  const parentLink =
    parent !== abs && insideAnyRoot(parent) ? ` <a href="${q(parent)}">⬆ 上一级</a>` : "";
  const quickLinks = FILES_ROOTS.map((p) => `<a href="${q(p)}">${escapeHtml(p)}</a>`).join(" · ");
  const items = rows
    .map((r) => {
      const nameCell = r.dir
        ? `<a class="d" href="${q(join(abs, r.name))}">📁 ${escapeHtml(r.name)}</a>`
        : `<a href="/files/view?path=${enc(join(abs, r.name))}">${escapeHtml(r.name)}</a>`;
      const ops = r.dir
        ? "—"
        : `<a href="/files/download?path=${enc(join(abs, r.name))}">下载</a>`;
      return `<tr><td>${nameCell}</td><td>${r.dir ? "目录" : "文件"}</td><td class="n">${fmtSize(r.size)}</td><td class="n">${fmtTime(r.mtime)}</td><td>${ops}</td></tr>`;
    })
    .join("\n");

  const html = `<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>文件浏览 · ${escapeHtml(abs)}</title>
<style>
body{font:14px/1.6 system-ui,"Segoe UI","Microsoft YaHei",sans-serif;margin:0;background:#1b2432;color:#e8e0c8;}
header{padding:14px 20px;border-bottom:1px solid #33415a;}
header .quick{margin-top:6px;color:#8fa0bd;}header .quick a{color:#7fb3ff;margin-right:4px;}
main{padding:12px 20px 40px;}
code{color:#9fd08f;word-break:break-all;}
table{border-collapse:collapse;width:100%;max-width:1100px;}
td,th{padding:6px 10px;border-bottom:1px solid #2c3850;text-align:left;vertical-align:top;}
th{color:#8fa0bd;font-weight:600;}td.n{white-space:nowrap;color:#a8b4c8;}
td a{color:#e8e0c8;text-decoration:none;word-break:break-all;}
td a.d{color:#ffd27f;font-weight:600;}
td a:hover{text-decoration:underline;}
footer{padding:10px 20px;color:#5c6b88;font-size:12px;}
</style></head><body>
<header><div>📁 <code>${escapeHtml(abs)}</code>${parentLink}</div>
<div class="quick">快速跳转：${quickLinks}</div></header>
<main><table><thead><tr><th>名称</th><th>类型</th><th>大小</th><th>修改时间</th><th>操作</th></tr></thead>
<tbody>${items || '<tr><td colspan="5">（空目录）</td></tr>'}</tbody></table></main>
<footer>只读浏览/下载 · 服务：/ 游戏页面 · /files/ 文件浏览</footer>
</body></html>`;
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" });
  if (req.method === "HEAD") return res.end();
  res.end(html);
}

// —— Godot 无头联机服务器子进程（GODOT_BIN 未设置则不拉起，仅静态/文件服务）——
// stdout/stderr 转发到控制台的同时落盘 $DATA_DIR/godot.log（可用 /files/view?path=/data/godot.log 查看启动错误）。
import { appendFileSync, readFileSync } from "node:fs";
const GODOT_LOG = process.env.GODOT_LOG ?? "/data/godot.log";
function godotLog(line) {
  console.log(line);
  try {
    appendFileSync(GODOT_LOG, line + "\n");
  } catch {}
}
let godotExit = null;
function spawnGodot() {
  const bin = process.env.GODOT_BIN;
  if (!bin) {
    godotLog("GODOT_BIN 未设置：跳过联机服务器，仅提供游戏页面与文件浏览");
    return;
  }
  const args = (process.env.GODOT_ARGS ?? `--headless -- --port ${GODOT_PORT}`)
    .split(" ")
    .filter(Boolean);
  godotExit = null;
  godotLog(`spawn godot-server: ${bin} ${args.join(" ")}`);
  const child = spawn(bin, args, { stdio: ["ignore", "pipe", "pipe"] });
  godotLog(`spawned pid=${child.pid}`);
  child.on("error", (e) => godotLog(`spawn error: ${e}`));
  child.stdout.on("data", (d) => d.toString().split("\n").filter(Boolean).forEach(godotLog));
  child.stderr.on("data", (d) => d.toString().split("\n").filter(Boolean).forEach((l) => godotLog("[stderr] " + l)));
  child.on("exit", (code, sig) => {
    godotExit = { code, sig, at: new Date().toISOString() };
    godotLog(`godot-server 退出（code=${code} sig=${sig}），3s 后重启`);
    setTimeout(spawnGodot, 3000);
  });
}
spawnGodot();

// —— /debug：联机子进程状态 + 多目标监听探测（部署诊断用） ——
function probePort(host, port, ms = 700) {
  return new Promise((resolve) => {
    const c = net.connect(port, host);
    const done = (v) => {
      c.destroy();
      resolve(v);
    };
    c.setTimeout(ms, () => done(false));
    c.on("connect", () => done(true));
    c.on("error", () => done(false));
  });
}
async function handleDebug(res) {
  const listening = {
    "127.0.0.1": await probePort("127.0.0.1", GODOT_PORT),
    "::1": await probePort("::1", GODOT_PORT),
  };
  let logTail = "";
  try {
    logTail = readFileSync(GODOT_LOG, "utf8").slice(-1500);
  } catch {}
  let engineLog = "";
  try {
    engineLog = readFileSync(process.env.GODOT_ENGINE_LOG ?? "/data/gd-engine.log", "utf8").slice(-1200);
  } catch {}
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-cache" });
  res.end(JSON.stringify({ godotExit, listening, logTail, engineLog }, null, 1));
}

const httpServer = createServer(async (req, res) => {
  try {
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.writeHead(405, { Allow: "GET, HEAD" }).end();
      return;
    }
    const url = new URL(req.url ?? "/", "http://localhost");
    if (url.pathname === "/debug") return handleDebug(res);
    if (url.pathname === "/files" || url.pathname === "/files/") return handleBrowse(req, res, url);
    if (url.pathname === "/files/view") return handleFileContent(req, res, url, "inline");
    if (url.pathname === "/files/download") return handleFileContent(req, res, url, "attachment");
    if (url.pathname.startsWith("/files/")) return plain(res, 404, "Not Found");
    return handleGame(req, res, url);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) plain(res, 500, "Internal error");
    else res.destroy();
  }
});

// —— WebSocket 升级代理：按原始头透传给 127.0.0.1:GODOT_PORT（Godot WebSocketMultiplayerPeer
//    不校验 Host/Origin，边缘终结 TLS 后此处是明文 ws，与平台「app 收到普通 HTTP」一致）——
httpServer.on("upgrade", (req, socket, head) => {
  let raw = `GET ${req.url} HTTP/1.1\r\n`;
  for (let i = 0; i < req.rawHeaders.length; i += 2) {
    raw += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
  }
  raw += "\r\n";
  const upstream = net.connect(GODOT_PORT, "127.0.0.1");
  upstream.setNoDelay(true);
  socket.setNoDelay(true);
  upstream.on("connect", () => {
    upstream.write(raw);
    if (head.length > 0) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  const fail = () => {
    socket.destroy();
    upstream.destroy();
  };
  upstream.on("error", fail);
  socket.on("error", fail);
  upstream.on("close", fail);
  socket.on("close", () => upstream.destroy());
});

httpServer.listen(PORT, "0.0.0.0", () => {
  console.log(
    `sanhax-server: game ${GAME_DIR} at /, file browser roots [${FILES_ROOTS.join(", ")}] at /files/,` +
      ` ws proxy -> 127.0.0.1:${GODOT_PORT}, on 0.0.0.0:${PORT}`,
  );
});
