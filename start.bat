@echo off
chcp 65001 >nul
echo ====================================
echo    申论行测学习系统 - 本地启动
echo ====================================
echo.

:: 检查Node.js是否安装
node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [错误] 未检测到Node.js，请先安装Node.js
    echo 下载地址: https://nodejs.org/
    pause
    exit /b 1
)

echo [信息] Node.js版本: 
node --version
echo.

:: 检查是否已安装依赖
if not exist "node_modules" (
    echo [信息] 首次运行，正在安装依赖...
    npm install
    if %errorlevel% neq 0 (
        echo [错误] 依赖安装失败
        pause
        exit /b 1
    )
    echo [成功] 依赖安装完成
    echo.
)

:: 启动服务器
echo [信息] 正在启动申论行测学习系统...
echo [信息] 本地访问地址: http://localhost:3000
echo [信息] 按 Ctrl+C 停止服务器
echo.

node server.js

echo.
echo [信息] 服务器已停止
pause