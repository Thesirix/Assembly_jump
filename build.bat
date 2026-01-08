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
nasm -f win64 "%SRC%\main.asm" -o main.obj
if errorlevel 1 goto :err

nasm -f win64 "%SRC%\game.asm" -o game.obj
if errorlevel 1 goto :err

nasm -f win64 "%SRC%\physics.asm" -o physics.obj
if errorlevel 1 goto :err

nasm -f win64 "%SRC%\input.asm" -o input.obj
if errorlevel 1 goto :err

REM ===== Link =====
link main.obj game.obj physics.obj input.obj^
 /LIBPATH:"%SDK_LIB%" ^
 kernel32.lib user32.lib gdi32.lib ^
 /SUBSYSTEM:WINDOWS ^
 /ENTRY:_start ^
 /MACHINE:X64 ^
 /OUT:doodle.exe

if errorlevel 1 goto :err

echo.
echo BUILD OK : build\doodle.exe
echo.
popd
exit /b 0

:err
echo.
echo BUILD FAILED
echo.
popd
exit /b 1
