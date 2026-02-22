@echo off
setlocal
REM ============================================================
REM Doodle Jump — NASM x86-64 Assembly (Windows)
REM Features:
REM   - Multi-threading (3 workers: render, audio, platgen)
REM   - SIMD SSE2 (collision 4-wide) + AVX2 (clear 8-wide)
REM   - FPU x87 (fsin oscillation, float parabolic physics)
REM   - Fixed timestep QPC (Unity/Unreal method)
REM   - Double-buffering render thread
REM   - Perlin noise 1D (coherent level generator)
REM   - HSV->RGB integer conversion (platform colors)
REM   - Particle system (disintegration + gravity)
REM   - SIMD sky gradient (adaptive vertical gradient)
REM   - Parallax starfield 3 layers + twinkle
REM ============================================================

set ROOT=%~dp0
set SRC=%ROOT%src
set OUT=%ROOT%build
set SDK_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64

if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"

echo [1/10] audio.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\audio.asm" -o audio.obj
if errorlevel 1 goto :err

echo [2/10] main.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\main.asm" -o main.obj
if errorlevel 1 goto :err

echo [3/10] game.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\game.asm" -o game.obj
if errorlevel 1 goto :err

echo [4/10] physics.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\physics.asm" -o physics.obj
if errorlevel 1 goto :err

echo [5/10] input.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\input.asm" -o input.obj
if errorlevel 1 goto :err

echo [6/10] platforms.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\platforms.asm" -o platforms.obj
if errorlevel 1 goto :err

echo [7/10] scroll.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\scroll.asm" -o scroll.obj
if errorlevel 1 goto :err

echo [8/10] score.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\score.asm" -o score.obj
if errorlevel 1 goto :err

echo [9/10] thread.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\thread.asm" -o thread.obj
if errorlevel 1 goto :err

echo [10/10] stars.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\stars.asm" -o stars.obj
if errorlevel 1 goto :err

echo Linkage...
link main.obj game.obj physics.obj input.obj platforms.obj scroll.obj score.obj audio.obj thread.obj stars.obj ^
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
