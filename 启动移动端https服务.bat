@echo off
rem 移动端 HTTPS 服务：为手机/平板浏览器提供自签名 HTTPS（Godot Web 要求安全上下文，
rem 手机访问 http://<局域网IP> 会被 Godot 拒绝启动，报 Secure Context 错误）
rem 前置：先执行 Web 导出（build/web/index.html）；依赖 Python 与 openssl（Git for Windows 自带）
rem 用法：双击运行，手机浏览器打开窗口里打印的 https://<局域网IP>:8765
rem       首次访问会警告自签名证书——选「高级 → 继续访问」；Ctrl+C 停止
rem       端口可覆盖：启动移动端https服务.bat --port 9000
pushd "%~dp0"
where python >nul 2>nul && (python tool/serve_https.py %* & goto :done)
where py >nul 2>nul && (py tool/serve_https.py %* & goto :done)
echo 未找到 Python：请安装 Python 并加入 PATH（https://www.python.org/downloads/）
:done
popd
pause
