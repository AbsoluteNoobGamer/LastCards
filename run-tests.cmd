@echo off
setlocal

if "%~1"=="" (
  flutter test
) else (
  flutter test %*
)
