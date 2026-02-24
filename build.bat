@echo off
setlocal


set ROOT=%~dp0
set SRC=%ROOT%src
set OUT=%ROOT%build
set SDK_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64
set UCRT_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\ucrt\x64

if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"

REM Etape 0 : helper.c (cl.exe) -> helper_c.obj
echo [0/12] helper.c  (bridge C : Perlin2D + smooth_log + plat_freq)...
cl.exe /c /O2 /nologo "%SRC%\helper.c" /Fo"%OUT%\helper_c.obj"
if errorlevel 1 goto :err

echo [1/12] audio.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\audio.asm" -o audio.obj
if errorlevel 1 goto :err

echo [2/12] main.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\main.asm" -o main.obj
if errorlevel 1 goto :err

echo [3/12] game.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\game.asm" -o game.obj
if errorlevel 1 goto :err

echo [4/12] physics.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\physics.asm" -o physics.obj
if errorlevel 1 goto :err

echo [5/12] input.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\input.asm" -o input.obj
if errorlevel 1 goto :err

echo [6/12] platforms.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\platforms.asm" -o platforms.obj
if errorlevel 1 goto :err

echo [6b/13] particles.asm (SIMD 4-wide update + 0-div render)...
nasm -f win64 -I"%SRC%\\" "%SRC%\particles.asm" -o particles.obj
if errorlevel 1 goto :err

echo [7/12] scroll.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\scroll.asm" -o scroll.obj
if errorlevel 1 goto :err

echo [8/12] score.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\score.asm" -o score.obj
if errorlevel 1 goto :err

echo [9/12] thread.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\thread.asm" -o thread.obj
if errorlevel 1 goto :err

echo [10/12] stars.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\stars.asm" -o stars.obj
if errorlevel 1 goto :err

REM Etape 11 : helper.asm (nasm) -> helper_wrap.obj
echo [11/12] helper.asm (bridge NASM wrappers -^> C)...
nasm -f win64 -I"%SRC%\\" "%SRC%\helper.asm" -o helper_wrap.obj
if errorlevel 1 goto :err

REM Linkage : helper_wrap.obj (NASM) + helper_c.obj (C) 
echo [12/12] Linkage...
link main.obj game.obj physics.obj input.obj platforms.obj particles.obj scroll.obj ^
     score.obj audio.obj thread.obj stars.obj ^
     helper_wrap.obj helper_c.obj ^
 /LIBPATH:"%SDK_LIB%" ^
 /LIBPATH:"%UCRT_LIB%" ^
 kernel32.lib user32.lib gdi32.lib winmm.lib ^
 ucrt.lib libvcruntime.lib ^
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