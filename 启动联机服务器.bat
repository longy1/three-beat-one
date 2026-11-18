@echo off
rem 三打哈联机服务器（M4）：无头 Godot 进程，端口默认 9080
rem 可传参覆盖端口：启动联机服务器.bat --port 9001
rem 注意：--path 不能直接用 %~dp0（尾部反斜杠会转义闭合引号，吞掉后一个参数）
if "%GODOT_PATH%"=="" set "GODOT_PATH=S:\Program\Godot\Godot_v4.7.2-stable_win64.exe"
pushd "%~dp0"
"%GODOT_PATH%" --headless --path . res://server/server_main.tscn %*
popd
pause
