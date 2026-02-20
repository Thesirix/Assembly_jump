@echo off
setlocal

set ROOT=%~dp0
set SRC=%ROOT%src
set OUT=%ROOT%build
set SDK_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64

if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"

echo [1/9] audio.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\audio.asm" -o audio.obj
if errorlevel 1 goto :err

echo [2/9] main.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\main.asm" -o main.obj
if errorlevel 1 goto :err

echo [3/9] game.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\game.asm" -o game.obj
if errorlevel 1 goto :err

echo [4/9] physics.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\physics.asm" -o physics.obj
if errorlevel 1 goto :err

echo [5/9] input.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\input.asm" -o input.obj
if errorlevel 1 goto :err

echo [6/9] platforms.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\platforms.asm" -o platforms.obj
if errorlevel 1 goto :err

echo [7/9] scroll.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\scroll.asm" -o scroll.obj
if errorlevel 1 goto :err

echo [8/9] score.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\score.asm" -o score.obj
if errorlevel 1 goto :err

echo [9/9] thread.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\thread.asm" -o thread.obj
if errorlevel 1 goto :err

echo Linkage...
link main.obj game.obj physics.obj input.obj platforms.obj scroll.obj score.obj audio.obj thread.obj ^
 /LIBPATH:"%SDK_LIB%" ^
 kernel32.lib user32.lib gdi32.lib winmm.lib ^
 /SUBSYSTEM:WINDOWS ^
 /ENTRY:Start ^
 /MACHINE:X64 ^
 /OUT:doodle.exe
if errorlevel 1 goto :err

echo.
echo ============================================
echo BUILD OK : build\doodle.exe
echo ============================================
popd
exit /b 0

:err
echo.
echo ============================================
echo BUILD FAILED
echo ============================================
popd
pause
exit /b 1
