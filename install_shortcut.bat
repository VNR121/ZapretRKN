@echo off
chcp 65001 > nul
cd /d "%~dp0"

echo ========================================
echo   Создание ярлыка Zapret на рабочем столе
echo ========================================
echo.

set "SHORTCUT_NAME=Zapret"
set "TARGET_BAT=%~dp0general (ALT11).bat"
set "DESKTOP=%USERPROFILE%\Desktop"

if not exist "%TARGET_BAT%" (
    echo [ОШИБКА] Не найден файл "general (ALT11).bat"
    echo Убедитесь, что он находится в одной папке с этим скриптом.
    pause
    exit /b 1
)

echo Создание ярлыка...
powershell -NoProfile -Command ^
    "$ws = New-Object -ComObject WScript.Shell;" ^
    "$sc = $ws.CreateShortcut('%DESKTOP%\%SHORTCUT_NAME%.lnk');" ^
    "$sc.TargetPath = 'cmd.exe';" ^
    "$sc.Arguments = '/c \"\"%TARGET_BAT%\"\"';" ^
    "$sc.WorkingDirectory = '%~dp0';" ^
    "$sc.IconLocation = 'shell32.dll,137';" ^
    "$sc.Description = 'Zapret DPI bypass - запуск от администратора';" ^
    "$sc.Save();"

if errorlevel 1 (
    echo [ОШИБКА] Не удалось создать ярлык.
    pause
    exit /b 1
)

echo Установка флага "Запуск от имени администратора"...
powershell -NoProfile -Command ^
    "$path = '%DESKTOP%\%SHORTCUT_NAME%.lnk';" ^
    "$bytes = [System.IO.File]::ReadAllBytes($path);" ^
    "$bytes[0x15] = $bytes[0x15] -bor 0x20;" ^
    "[System.IO.File]::WriteAllBytes($path, $bytes);"

echo.
echo ========================================
echo   ГОТОВО! Ярлык "Zapret" создан на рабочем столе.
echo   Двойной клик по нему автоматически
echo   запросит права администратора.
echo ========================================
echo.
pause