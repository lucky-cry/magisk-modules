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
git commit -m "v%MODVER%"
git push origin freeze_logd_switch --force

echo Done. v%MODVER% pushed.
pause
