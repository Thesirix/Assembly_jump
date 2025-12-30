@echo off
setlocal

set ROOT=%~dp0
set SRC=%ROOT%src
set OUT=%ROOT%build

if not exist "%OUT%" mkdir "%OUT%"

set SDK_LIB="C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64"

pushd "%OUT%"

nasm -f win64 "%SRC%\main.asm" -o main.obj
if errorlevel 1 goto :err

link main.obj ^
 /LIBPATH:%SDK_LIB% ^
 kernel32.lib user32.lib gdi32.lib ^
 /SUBSYSTEM:CONSOLE ^
 /ENTRY:_start ^
 /MACHINE:X64 ^
 /OUT:doodle.exe

if errorlevel 1 goto :err

echo OK: build\doodle.exe
popd
exit /b 0

:err
echo BUILD FAILED
popd
exit /b 1
