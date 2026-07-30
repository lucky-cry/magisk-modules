  @echo off
  cd /d "%~dp0"
  git config user.name "lucky-cry" >nul 2>&1
  git config user.email "739270050@qq.com" >nul 2>&1
  echo [1/3] git add...
  git add .
  echo [2/3] git commit...
  git commit -m "update %date%"
  echo [3/3] git push...
  git push origin freeze_logd_switch --force
  echo Done.
  pause
