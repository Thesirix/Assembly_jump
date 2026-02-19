@echo off
setlocal

REM ===== Chemins =====
set ROOT=%~dp0
set SRC=%ROOT%src
set OUT=%ROOT%build

REM ===== Cree le dossier build si absent =====
if not exist "%OUT%" mkdir "%OUT%"

REM ===== Windows SDK x64 =====
set SDK_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64

pushd "%OUT%"

echo Compilation de audio.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\audio.asm" -o audio.obj
if errorlevel 1 goto :err

echo Compilation de audio_helpers.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\audio_helpers.asm" -o audio_helpers.obj
if errorlevel 1 goto :err

echo Compilation de main.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\main.asm" -o main.obj
if errorlevel 1 goto :err

echo Compilation de game.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\game.asm" -o game.obj
if errorlevel 1 goto :err

echo Compilation de physics.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\physics.asm" -o physics.obj
if errorlevel 1 goto :err

echo Compilation de input.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\input.asm" -o input.obj
if errorlevel 1 goto :err

echo Compilation de platforms.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\platforms.asm" -o platforms.obj
if errorlevel 1 goto :err

echo Compilation de scroll.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\scroll.asm" -o scroll.obj
if errorlevel 1 goto :err

echo Compilation de score.asm...
nasm -f win64 -I"%SRC%\\" "%SRC%\score.asm" -o score.obj
if errorlevel 1 goto :err

REM ===== Link =====
echo Linkage...
link main.obj game.obj physics.obj input.obj platforms.obj scroll.obj score.obj audio.obj audio_helpers.obj ^
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
echo.
popd
exit /b 0

:err
echo.
echo ============================================
echo BUILD FAILED - Verifiez les erreurs ci-dessus
echo ============================================
echo.
popd
pause
exit /b 1
