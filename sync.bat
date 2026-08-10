@echo off
cd /d "%~dp0"

git config user.name "lucky-cry" >nul 2>&1
git config user.email "739270050@qq.com" >nul 2>&1

for /f "tokens=2 delims==" %%a in ('findstr /b "version=" Source\module.prop') do set MODVER=%%a
for /f "tokens=2 delims==" %%b in ('findstr /b "versionCode=" Source\module.prop') do set MODCODE=%%b

echo module version: %MODVER% code: %MODCODE%

echo {> update.json
echo   "version": "%MODVER%",>> update.json
echo   "versionCode": %MODCODE%,>> update.json
echo   "zipUrl": "https://github.com/lucky-cry/magisk-modules/releases/download/v%MODVER%/freeze_logd_switch-%MODVER%.zip",>> update.json
echo   "changelog": "https://raw.githubusercontent.com/lucky-cry/magisk-modules/freeze_logd_switch/changelog">> update.json
echo }>> update.json

echo ##update info> version
echo name=v%MODVER%>> version
echo version=%MODCODE%>> version

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
