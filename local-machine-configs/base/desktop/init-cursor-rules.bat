@echo off
chcp 65001 >nul
title Cursor AI 规则初始化
echo.
echo ======================================
echo   Cursor AI 协作规则初始化
echo ======================================
echo.
echo 正在检查规则文件...

if not exist "%USERPROFILE%\.cursor-templates\.cursor\rules" (
    echo [错误] 找不到模板规则目录
    echo 请确认 E:\HJ\cursor 已正确设置
    pause
    exit /b 1
)

echo 规则目录存在
echo.
echo 将运行初始化脚本...
powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.cursor-templates\scripts\init-project.ps1"

if errorlevel 1 (
    echo.
    echo [错误] 初始化失败
    pause
    exit /b 1
)

echo.
echo ======================================
echo   初始化完成！
echo ======================================
echo.
echo 请重启 Cursor IDE 以加载新规则
echo.
pause
