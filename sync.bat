@echo off
setlocal
cd /d "%~dp0"

git config user.name "lucky-cry" >nul 2>&1
git config user.email "739270050@qq.com" >nul 2>&1

for /f "tokens=2 delims==" %%a in ('findstr /b "version=" Source\module.prop') do set MODVER=%%a
for /f "tokens=2 delims==" %%b in ('findstr /b "versionCode=" Source\module.prop') do set MODCODE=%%b

echo module version: %MODVER% code: %MODCODE%

REM 定位 Git for Windows 自带的 bash, 运行统一元数据生成脚本 (update_meta.sh)
set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "BASH=%ProgramFiles%\Git\usr\bin\bash.exe"
if not defined BASH if exist "%LocalAppData%\Programs\Git\bin\bash.exe" set "BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if defined BASH goto :havebash
for /f "delims=" %%i in ('where bash 2^>nul') do if not defined BASH set "BASH=%%i"
if defined BASH goto :havebash
echo [错误] 未找到 Git for Windows 的 bash, 无法生成 update.json/version
pause
exit /b 1

:havebash
"%BASH%" update_meta.sh github || goto :error

git add .
git commit -m "v%MODVER%" >nul 2>&1 || echo (无新增提交, 继续)

REM 推送前先同步远程最新状态: 取回 + 变基, 避免覆盖 CI 提交, 也避免 stale info 拒绝
git fetch origin freeze_logd_switch || goto :error
git pull --rebase origin freeze_logd_switch || goto :error
git push origin freeze_logd_switch || goto :error

echo Done. v%MODVER% pushed.
pause
exit /b 0

:error
echo.
echo [错误] 同步失败, 请检查上方输出后重试.
pause
exit /b 1
