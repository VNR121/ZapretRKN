@echo off
chcp 65001 > nul
cd /d "%~dp0"

set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo [ОШИБКА] csc.exe не найден. Требуется .NET Framework 4.x
    pause
    exit /b 1
)

set "ROOT=%~dp0..\..\"
set "OUT=%ROOT%ZapretRKN.exe"
set "ICON=%~dp0icon.ico"
set "SRC=%~dp0launcher.cs"

if not exist "%SRC%" (
    echo [ОШИБКА] Не найден исходник: %SRC%
    pause
    exit /b 1
)

echo Компиляция ZapretRKN.exe...

if exist "%OUT%" del /f /q "%OUT%"

if exist "%ICON%" (
    "%CSC%" /nologo /optimize+ /target:winexe /out:"%OUT%" /win32icon:"%ICON%" /r:System.Windows.Forms.dll "%SRC%"
) else (
    "%CSC%" /nologo /optimize+ /target:winexe /out:"%OUT%" /r:System.Windows.Forms.dll "%SRC%"
)

if errorlevel 1 (
    echo [ОШИБКА] Компиляция провалилась.
    pause
    exit /b 1
)

if not exist "%OUT%" (
    echo [ОШИБКА] Файл не создан.
    pause
    exit /b 1
)

for %%A in ("%OUT%") do echo Готово: %%A (%%~zA байт)
pause