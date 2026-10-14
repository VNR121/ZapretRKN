@echo off
chcp 65001 > nul
cd /d "%~dp0"

:: --- Самоэлевация через UAC ---
if /i not "%~1"=="elevated" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo Запрос прав администратора...
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
        exit /b
    )
)

echo ========================================
echo   Установка ZapretRKN
echo ========================================
echo.

:: --- Шаг 0: Проверка кириллицы в пути ---
echo %~dp0 | findstr /R /C:"[А-Яа-яЁё]" >nul
if not errorlevel 1 (
    echo [ОШИБКА] Путь содержит русские буквы: %~dp0
    echo Перенесите папку в C:\ZapretRKN и запустите снова.
    timeout /t 10 /nobreak >nul
    exit /b 1
)

:: --- Шаг 1: Автозагрузка ---
set "AUTOSTART=Y"
set /p "AUTOSTART=Добавить ZapretRKN в автозагрузку при включении ПК? [Y/n]: "
if "%AUTOSTART%"=="" set "AUTOSTART=Y"

if /i "%AUTOSTART%"=="n" (
    set "AUTOSTART_FLAG=0"
    echo Автозагрузка: отключена
) else (
    set "AUTOSTART_FLAG=1"
    echo Автозагрузка: включена
)
echo.

:: --- Шаг 2: Проверка файлов ---
set "SHORTCUT_NAME=ZapretRKN"
set "TARGET_BAT=%~dp0general.bat"
set "RUN_HIDDEN=%~dp0utils\scripts\run_hidden.vbs"

if not exist "%TARGET_BAT%" (
    echo [ОШИБКА] Не найден файл "general.bat"
    timeout /t 5 /nobreak >nul
    exit /b 1
)

:: run_hidden.vbs обязателен для скрытого запуска (ярлык + автозагрузка)
if not exist "%RUN_HIDDEN%" (
    echo [ОШИБКА] Не найден "%RUN_HIDDEN%"
    echo Без него обход будет запускаться в видимом окне.
    timeout /t 5 /nobreak >nul
    exit /b 1
)

:: --- Шаг 3: Иконка ---
set "ICON=%~dp0utils\scripts\icon.ico"
if not exist "%ICON%" (
    echo [ПРЕДУПРЕЖДЕНИЕ] Иконка не найдена: %ICON%
    echo Использую стандартную иконку Windows.
    set "ICON=shell32.dll,137"
)

:: --- Шаг 4: Создание ярлыка (идемпотентно: старый удаляется) ---
echo Создание ярлыка...

set "PS1=%TEMP%\zapret_make_shortcut.ps1"
> "%PS1%" echo $ErrorActionPreference = 'Stop'
>> "%PS1%" echo $desktop = [Environment]::GetFolderPath('Desktop')
>> "%PS1%" echo $lnkPath = Join-Path $desktop 'ZapretRKN.lnk'
>> "%PS1%" echo if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force }
>> "%PS1%" echo $ws = New-Object -ComObject WScript.Shell
>> "%PS1%" echo $sc = $ws.CreateShortcut($lnkPath)
>> "%PS1%" echo $sc.TargetPath = "$env:SystemRoot\System32\cmd.exe"
>> "%PS1%" echo $sc.Arguments = '/c ""%~dp0general.bat""'
>> "%PS1%" echo $sc.WorkingDirectory = '%~dp0'
>> "%PS1%" echo $sc.IconLocation = '%ICON%'
>> "%PS1%" echo $sc.Description = 'ZapretRKN DPI bypass'
>> "%PS1%" echo $sc.Save()
>> "%PS1%" echo $bytes = [System.IO.File]::ReadAllBytes($lnkPath)
>> "%PS1%" echo $bytes[0x15] = $bytes[0x15] -bor 0x20
>> "%PS1%" echo [System.IO.File]::WriteAllBytes($lnkPath, $bytes)
>> "%PS1%" echo Write-Host "OK: $lnkPath"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "PS_RESULT=%errorlevel%"
del /f /q "%PS1%" 2>nul

if not "%PS_RESULT%"=="0" (
    echo [ОШИБКА] Не удалось создать ярлык.
    timeout /t 5 /nobreak >nul
    exit /b 1
)

:: --- Шаг 5: Автозагрузка через Task Scheduler ---
set "PS2=%TEMP%\zapret_autostart.ps1"

if "%AUTOSTART_FLAG%"=="1" (
    echo Регистрация задачи автозагрузки...

    > "%PS2%" echo $ErrorActionPreference = 'Stop'
    >> "%PS2%" echo $batPath = '%~dp0general.bat'
    >> "%PS2%" echo $vbs = '%~dp0utils\scripts\run_hidden.vbs'
    >> "%PS2%" echo $q = [char]34
    >> "%PS2%" echo $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ^($q + $vbs + $q + ' ' + $q + $batPath + $q^)
    >> "%PS2%" echo $trigger = New-ScheduledTaskTrigger -AtLogOn
    >> "%PS2%" echo $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
    >> "%PS2%" echo $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    >> "%PS2%" echo Register-ScheduledTask -TaskName 'ZapretRKN' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force ^| Out-Null
    >> "%PS2%" echo Write-Host "Autostart task registered."

    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS2%"
    set "PS2_RESULT=%errorlevel%"
    del /f /q "%PS2%" 2>nul

    if not "%PS2_RESULT%"=="0" (
        echo [ПРЕДУПРЕЖДЕНИЕ] Ярлык создан, но задача автозагрузки не зарегистрирована.
    )
) else (
    echo Удаление задачи автозагрузки ^(если была^)...
    powershell -NoProfile -Command "Unregister-ScheduledTask -TaskName 'ZapretRKN' -Confirm:$false -ErrorAction SilentlyContinue" >nul 2>&1
)

:: --- Шаг 6: Проверка ярлыка ---
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP_REAL=%%D"

if not exist "%DESKTOP_REAL%\%SHORTCUT_NAME%.lnk" (
    echo [ОШИБКА] Ярлык не найден в: %DESKTOP_REAL%
    timeout /t 5 /nobreak >nul
    exit /b 1
)

echo.
echo ========================================
echo   ГОТОВО!
echo   Ярлык "%SHORTCUT_NAME%" создан.
echo   Автозагрузка: %AUTOSTART_FLAG%
echo ========================================
echo.

timeout /t 2 /nobreak >nul
exit /b 0
