@echo off
rem 三打哈联机服务器（M4）：无头 Godot 进程，端口默认 9080
rem 可传参覆盖端口：启动联机服务器.bat --port 9001
"%GODOT_PATH%" --headless --path "%~dp0" res://server/server_main.tscn %*
pause
