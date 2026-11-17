"""局域网 HTTPS 静态服务器：手机/其它设备访问 Godot Web 导出用。

背景：Godot Web 版要求页面处于「安全上下文」（Secure Context）。
桌面访问 http://127.0.0.1 可行（localhost 是可信任来源），但手机访问
http://<局域网IP>:端口 不是安全上下文，Godot 启动即报
「Secure Context - Check web server configuration (use HTTPS)」。
本脚本用自签名证书以 HTTPS 提供服务：手机首次访问时浏览器会警告证书无效，
选择「继续访问/信任」即可正常进入游戏。

用法（仓库根目录）：
    python tool/serve_https.py            # 默认服务 build/web，端口 8765
    python tool/serve_https.py --port 9000
证书自动生成于 build/web/.cert/（self-signed，仅本地测试用）。
依赖 openssl 命令（Git for Windows 自带）。

附带 /touchtest.html 触控事件探针页：iPhone 点按无效时打开它连点几下，
页面直接显示收到的事件序列（touchstart/pointerdown/mousedown…），
用于判断事件断在哪一层（页面收不到事件 = 浏览器层；收到了 = Godot 层）。
服务器带 no-cache 头——Safari 缓存很激进，防止手机拿到旧版导出产物。
"""

import argparse
import functools
import ssl
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = REPO_ROOT / "build" / "web"
CERT_DIR = DEFAULT_DIR / ".cert"
CERT_FILE = CERT_DIR / "cert.pem"
KEY_FILE = CERT_DIR / "key.pem"

TOUCHTEST_HTML = """<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<title>触控事件探针</title>
<style>
body{margin:0;font-family:-apple-system,sans-serif;background:#12291d;color:#d8e5dd;}
#count{font-size:64px;font-weight:bold;color:#ffd140;text-align:center;}
#sec{font-size:15px;line-height:1.8;text-align:center;}
#last{font-size:13px;color:#7fdc9a;text-align:center;min-height:2em;word-break:break-all;padding:0 10px;}
#log{position:fixed;left:0;right:0;bottom:0;height:34%;overflow-y:auto;background:rgba(0,0,0,.55);
font:12px/1.5 monospace;padding:8px;box-sizing:border-box;}
.ev{color:#ffd140}
</style></head><body>
<div style="padding:14px 10px;">
<div id="count">0</div>
<div id="sec">次有效点按事件</div>
<div id="last">（在页面任意位置点按，此处显示最近事件；下方滚动区为完整序列）</div>
<div style="text-align:center;opacity:.7;font-size:12px;margin-top:10px;">
isSecureContext: <b id="sc">?</b><br>UA: <span id="ua"></span><br>innerW/H: <span id="wh"></span></div>
</div>
<div id="log"></div>
<script>
var n = 0;
document.getElementById('sc').textContent = window.isSecureContext;
document.getElementById('ua').textContent = navigator.userAgent.slice(0, 90);
document.getElementById('wh').textContent = innerWidth + 'x' + innerHeight + ' dpr:' + devicePixelRatio;
var log = document.getElementById('log');
function add(msg){
  n++;
  document.getElementById('count').textContent = n;
  document.getElementById('last').textContent = msg;
  var d = document.createElement('div');
  d.className = 'ev';
  d.textContent = n + '. ' + (performance.now() | 0) + 'ms ' + msg;
  log.insertBefore(d, log.firstChild);
}
['touchstart', 'touchend', 'touchcancel', 'pointerdown', 'pointerup',
 'mousedown', 'mouseup', 'click'].forEach(function(type){
  window.addEventListener(type, function(evt){
    var x = (evt.clientX !== undefined) ? Math.round(evt.clientX) : '-';
    var y = (evt.clientY !== undefined) ? Math.round(evt.clientY) : '-';
    var pt = evt.pointerType || '';
    add(type + ' x=' + x + ' y=' + y + (pt ? ' type=' + pt : '') +
        (evt.touches ? ' touches=' + evt.touches.length : ''), 'ev');
  }, true);
});
</script></body></html>
"""

class NoCacheHandler(SimpleHTTPRequestHandler):
    """Safari 缓存很激进——禁缓存保证手机拿到最新导出产物。"""

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()


def lan_ip() -> str:
    """取局域网 IP（UDP connect 不实际发包，仅选路由源地址）。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def ensure_cert() -> None:
    if CERT_FILE.exists() and KEY_FILE.exists():
        return
    CERT_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-days", "3650", "-subj", "/CN=three-beat-one-local",
        "-keyout", str(KEY_FILE), "-out", str(CERT_FILE),
    ]
    print("生成自签名证书……")
    subprocess.run(cmd, check=True, capture_output=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Godot Web 导出局域网 HTTPS 服务器")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR, help="静态目录（默认 build/web）")
    args = parser.parse_args()

    if not (args.dir / "index.html").exists():
        print(f"错误：{args.dir} 下没有 index.html——请先执行 Web 导出", file=sys.stderr)
        return 1
    try:
        ensure_cert()
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        print(f"错误：生成证书失败（需要 openssl 命令）：{e}", file=sys.stderr)
        return 1

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(CERT_FILE, KEY_FILE)
    (args.dir / "touchtest.html").write_text(TOUCHTEST_HTML, encoding="utf-8")
    handler = functools.partial(NoCacheHandler, directory=str(args.dir))
    server = ThreadingHTTPServer(("0.0.0.0", args.port), handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)

    ip = lan_ip()
    print(f"HTTPS 服务已启动（目录 {args.dir}）")
    print(f"  本机访问：  https://localhost:{args.port}")
    print(f"  手机访问：  https://{ip}:{args.port}")
    print(f"  触控探针：  https://{ip}:{args.port}/touchtest.html")
    print("  首次访问浏览器会警告自签名证书——选择「高级 → 继续访问」即可。")
    print("  Ctrl+C 停止。")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
