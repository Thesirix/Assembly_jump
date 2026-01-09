@echo off
setlocal

REM ===== Chemins =====
set ROOT=%~dp0
set SRC=%ROOT%src
set OUT=%ROOT%build

REM ===== Crée le dossier build si absent =====
if not exist "%OUT%" mkdir "%OUT%"

REM ===== Windows SDK x64 =====
set SDK_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64

pushd "%OUT%"

REM ===== Assemblage =====
echo Compilation de main.asm...
nasm -f win64 "%SRC%\main.asm" -o main.obj
if errorlevel 1 goto :err

echo Compilation de game.asm...
nasm -f win64 "%SRC%\game.asm" -o game.obj
if errorlevel 1 goto :err

echo Compilation de physics.asm...
nasm -f win64 "%SRC%\physics.asm" -o physics.obj
if errorlevel 1 goto :err

echo Compilation de input.asm...
nasm -f win64 "%SRC%\input.asm" -o input.obj
if errorlevel 1 goto :err

echo Compilation de platforms.asm...
nasm -f win64 "%SRC%\platforms.asm" -o platforms.obj
if errorlevel 1 goto :err

echo Compilation de scroll.asm...
nasm -f win64 "%SRC%\scroll.asm" -o scroll.obj
if errorlevel 1 goto :err

echo Compilation de score.asm...
nasm -f win64 "%SRC%\score.asm" -o score.obj
if errorlevel 1 goto :err

REM ===== Link =====
echo Linkage...
link main.obj game.obj physics.obj input.obj platforms.obj scroll.obj score.obj^
 /LIBPATH:"%SDK_LIB%" ^
 kernel32.lib user32.lib gdi32.lib ^
 /SUBSYSTEM:WINDOWS ^
 /ENTRY:_start ^
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
============================================
echo.
popd
exit /b 1