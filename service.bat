@echo off
chcp 65001 > nul
set "LOCAL_VERSION=1.2.0"

:: External commands
if "%~1"=="status_zapret" (
    call :test_service zapret soft
    call :tcp_enable
    exit /b
)

if "%~1"=="check_updates" (
    if defined NO_UPDATE_CHECK exit /b

    if exist "%~dp0utils\check_updates.enabled" (
        if not "%~2"=="soft" (
            start /b service check_updates soft
        ) else (
            call :service_check_updates soft
        )
    )

    exit /b
)

if "%~1"=="load_game_filter" (
    call :game_switch_status
    exit /b
)

if "%~1"=="load_user_lists" (
    call :load_user_lists
    exit /b
)

if "%1"=="admin" (
    call :check_command chcp
    call :check_command find
    call :check_command findstr
    call :check_command netsh

    call :load_user_lists

    echo Запущено с правами администратора
) else (
    call :check_extracted
    call :check_command powershell

    echo Запрос прав администратора...
    powershell -NoProfile -Command "Start-Process 'cmd.exe' -ArgumentList '/c \"\"%~f0\" admin\"' -Verb RunAs"
    exit
)


:: MENU ================================
setlocal EnableDelayedExpansion
chcp 65001 > nul
title ZapretRKN Manager v!LOCAL_VERSION!
:menu

chcp 65001 > nul
cls

call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
call :get_strategy_name

chcp 65001 > nul

:: Перевод статусов для отображения
set "IPsetDisplay=!IPsetStatus!"
if /i "!IPsetStatus!"=="loaded" set "IPsetDisplay=загружен"
if /i "!IPsetStatus!"=="none"   set "IPsetDisplay=отключён"
if /i "!IPsetStatus!"=="any"    set "IPsetDisplay=любой"

set "CheckUpdatesDisplay=!CheckUpdatesStatus!"
if /i "!CheckUpdatesStatus!"=="enabled"  set "CheckUpdatesDisplay=включена"
if /i "!CheckUpdatesStatus!"=="disabled" set "CheckUpdatesDisplay=отключена"

set "GameFilterDisplay=!GameFilterStatus!"
if /i "!GameFilterStatus!"=="disabled"              set "GameFilterDisplay=отключён"
if /i "!GameFilterStatus!"=="enabled (TCP and UDP)" set "GameFilterDisplay=включён (TCP и UDP)"
if /i "!GameFilterStatus!"=="enabled (TCP)"         set "GameFilterDisplay=включён (TCP)"
if /i "!GameFilterStatus!"=="enabled (UDP)"         set "GameFilterDisplay=включён (UDP)"

set "menu_choice=null"

echo.
echo   ZapretRKN Manager v!LOCAL_VERSION!
echo.  !CurrentStrategy!
echo   ----------------------------------------
echo.
echo   :: СЛУЖБА
echo      1. Установить службу
echo      2. Удалить службы
echo      3. Проверить статус
echo.
echo   :: НАСТРОЙКИ
echo      4. Game Filter         [!GameFilterDisplay!]
echo      5. Фильтр IPSet        [!IPsetDisplay!]
echo      6. Авто-проверка       [!CheckUpdatesDisplay!]
echo      7. Замена активных фейков
echo.
echo   :: ОБНОВЛЕНИЯ
echo      8. Обновить IP-лист
echo      9. Обновить файл hosts
echo      10. Проверить обновления
echo.
echo   :: ИНСТРУМЕНТЫ
echo      11. Диагностика
echo      12. Тесты стратегий
echo      13. Сменить стратегию
echo      14. Обновить движок
echo      15. Автоподбор стратегии
echo.
echo   ----------------------------------------
echo      0. Выход
echo.

set /p menu_choice=   Выберите пункт (0-15): 

if "%menu_choice%"=="1" goto service_install
if "%menu_choice%"=="2" goto service_remove
if "%menu_choice%"=="3" goto service_status
if "%menu_choice%"=="4" goto game_switch
if "%menu_choice%"=="5" goto ipset_switch
if "%menu_choice%"=="6" goto check_updates_switch
if "%menu_choice%"=="7" goto replace_active_fakes
if "%menu_choice%"=="8" goto ipset_update
if "%menu_choice%"=="9" goto hosts_update
if "%menu_choice%"=="10" goto service_check_updates
if "%menu_choice%"=="11" goto service_diagnostics
if "%menu_choice%"=="12" goto run_tests
if "%menu_choice%"=="13" goto strategy_switch
if "%menu_choice%"=="14" goto engine_update
if "%menu_choice%"=="15" goto autotest_strategy
if "%menu_choice%"=="0" exit /b
goto menu


:: LOAD USER LISTS =====================
:load_user_lists
set "LISTS_PATH=%~dp0lists\"

if not exist "%LISTS_PATH%ipset-exclude-user.txt" (
    echo 203.0.113.113/32>"%LISTS_PATH%ipset-exclude-user.txt"
)
if not exist "%LISTS_PATH%list-general-user.txt" (
    echo # Never leave this file empty>"%LISTS_PATH%list-general-user.txt"
    echo domain.example.abc>>"%LISTS_PATH%list-general-user.txt"
)
if not exist "%LISTS_PATH%list-exclude-user.txt" (
    echo domain.example.abc>"%LISTS_PATH%list-exclude-user.txt"
)

exit /b


:: TCP ENABLE ==========================
:tcp_enable
chcp 437 > nul
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul || netsh interface tcp set global timestamps=enabled > nul 2>&1
exit /b


:: STATUS ==============================
:service_status
chcp 65001 > nul
cls

sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do echo Установленная стратегия: "%%B"
)

call :test_service zapret
call :test_service WinDivert

set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :PrintRed "Файл WinDivert64.sys НЕ найден."
)
echo:

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    call :PrintGreen "Обход (winws.exe) РАБОТАЕТ."
) else (
    call :PrintRed "Обход (winws.exe) НЕ работает."
)

pause
goto menu

:test_service
set "ServiceName=%~1"
set "ServiceStatus="

chcp 437 > nul
for /f "tokens=3 delims=: " %%A in ('sc query "%ServiceName%" ^| findstr /i "STATE"') do set "ServiceStatus=%%A"
set "ServiceStatus=%ServiceStatus: =%"
chcp 65001 > nul

if "%ServiceStatus%"=="RUNNING" (
    if "%~2"=="soft" (
        echo Служба "%ServiceName%" УЖЕ ЗАПУЩЕНА, используйте "service.bat" и выберите "Удалить службы", если хотите запустить standalone bat.
        pause
        exit /b
    ) else (
        echo Служба "%ServiceName%" работает.
    )
) else if "%ServiceStatus%"=="STOP_PENDING" (
    call :PrintYellow "!ServiceName! в состоянии STOP_PENDING. Возможен конфликт с другим обходом. Запустите Диагностику."
) else if not "%~2"=="soft" (
    echo Служба "%ServiceName%" НЕ работает.
)

exit /b


:: REMOVE ==============================
:service_remove
chcp 65001 > nul
cls

set SRVCNAME=zapret
sc query "!SRVCNAME!" >nul 2>&1
if !errorlevel!==0 (
    net stop %SRVCNAME%
    sc delete %SRVCNAME%
) else (
    echo Служба "%SRVCNAME%" не установлена.
)

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    taskkill /IM winws.exe /F > nul
)

sc query "WinDivert" >nul 2>&1
if !errorlevel!==0 (
    net stop "WinDivert"

    sc query "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        sc delete "WinDivert"
    )
)
net stop "WinDivert14" >nul 2>&1
sc delete "WinDivert14" >nul 2>&1

pause
goto menu


:: INSTALL =============================
:service_install
chcp 65001 > nul
cls

:: Main
cd /d "%~dp0"
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"

:: Поиск .bat, кроме service* и install*
set "count=0"
for /f "delims=" %%F in ('powershell -NoProfile -Command "Get-ChildItem -LiteralPath '.' -Filter '*.bat' | Where-Object { $_.Name -notlike 'service*' -and $_.Name -notlike 'install*' } | Sort-Object { [Regex]::Replace($_.Name, '(\d+)', { $args[0].Value.PadLeft(8, '0') }) } | ForEach-Object { $_.Name }"') do (
    set /a count+=1
    echo   !count!. %%F
    set "file!count!=%%F"
)

if !count!==0 (
    echo Не найдено ни одной стратегии .bat в корне проекта.
    pause
    goto menu
)

if !count!==1 (
    set "selectedFile=!file1!"
    echo Автовыбор стратегии: !selectedFile!
    echo.
) else (
    echo   0. Выход
    echo.
    set "choice="
    set /p "choice=Введите номер (0-!count!, по умолчанию: 0): "
    if "!choice!"=="" set "choice=0"
    if "!choice!"=="0" goto menu
    set "selectedFile=!file%choice%!"
)

if not defined selectedFile (
    echo Неверный выбор.
    pause
    goto menu
)

:: Args that should be followed by value
set "args_with_value=sni host altorder"

:: Parsing args (mergeargs: 2=start param|3=arg with value|1=params args|0=default)
set "args="
set "capture=0"
set "mergeargs=0"
set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
set QUOTE="

for /f "tokens=*" %%a in ('type "!selectedFile!"') do (
    set "line=%%a"
    call set "line=%%line:^!=EXCL_MARK%%"
    call set "line=!line!"

    echo !line! | findstr /i "winws.exe" >nul
    if not errorlevel 1 (
        set "capture=1"
    )

    if !capture!==1 (
        if not defined args (
            set "line=!line:*winws.exe"=!"
        )

        set "temp_args="
        for %%i in (!line!) do (
            set "arg=%%i"

            if not "!arg!"=="^" if not "!arg!"=="^^" (
                if "!arg:~0,2!" EQU "--" if not !mergeargs!==0 (
                    set "mergeargs=0"
                )

                if "!arg:~0,1!" EQU "!QUOTE!" (
                    set "arg=!arg:~1,-1!"

                    echo !arg! | findstr ":" >nul
                    if !errorlevel!==0 (
                        set "arg=\!QUOTE!!arg!\!QUOTE!"
                    ) else if "!arg:~0,1!"=="@" (
                        set "arg=\!QUOTE!@%~dp0!arg:~1!\!QUOTE!"
                    ) else (
                        set "arg=\!QUOTE!%~dp0!arg!\!QUOTE!"
                    )
                )

                if !mergeargs!==1 (
                    set "temp_args=!temp_args!,!arg!"
                ) else if !mergeargs!==3 (
                    set "temp_args=!temp_args!=!arg!"
                    set "mergeargs=1"
                ) else (
                    set "temp_args=!temp_args! !arg!"
                )

                if "!arg:~0,2!" EQU "--" (
                    set "mergeargs=2"
                ) else if !mergeargs! GEQ 1 (
                    if !mergeargs!==2 set "mergeargs=1"

                    for %%x in (!args_with_value!) do (
                        if /i "%%x"=="!arg!" (
                            set "mergeargs=3"
                        )
                    )
                )
            )
        )

        if not "!temp_args!"=="" (
            set "args=!args! !temp_args!"
        )
    )
)

:: Creating service with parsed args
call :tcp_enable

set ARGS=%args%
call set "ARGS=%%ARGS:EXCL_MARK=^!%%"
echo Итоговые аргументы: !ARGS!
set SRVCNAME=zapret

net stop %SRVCNAME% >nul 2>&1
sc delete %SRVCNAME% >nul 2>&1
sc create %SRVCNAME% binPath= "\"%BIN_PATH%winws.exe\" !ARGS!" DisplayName= "zapret" start= auto
sc description %SRVCNAME% "Zapret DPI bypass software"
sc start %SRVCNAME%
for %%F in ("!file%choice%!") do (
    set "filename=%%~nF"
)
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!filename!" /f

pause
goto menu


:: CHECK UPDATES =======================
:service_check_updates
chcp 65001 > nul
cls

:: Set current version and URLs
set "GITHUB_VERSION_URL=https://raw.githubusercontent.com/VNR121/ZapretRKN/main/.service/version.txt"
set "GITHUB_RELEASE_URL=https://github.com/VNR121/ZapretRKN/releases/tag/"
set "GITHUB_DOWNLOAD_URL=https://github.com/VNR121/ZapretRKN/releases/latest"

:: Get the latest version from GitHub
for /f "delims=" %%A in ('powershell -NoProfile -Command "(Invoke-WebRequest -Uri \"%GITHUB_VERSION_URL%\" -Headers @{\"Cache-Control\"=\"no-cache\"} -UseBasicParsing -TimeoutSec 5).Content.Trim()" 2^>nul') do set "GITHUB_VERSION=%%A"

:: Error handling
if not defined GITHUB_VERSION (
    echo Не удалось получить последнюю версию. Это не влияет на работу zapret.
    timeout /T 9
    if "%1"=="soft" exit
    goto menu
)

:: Version comparison
if "%LOCAL_VERSION%"=="%GITHUB_VERSION%" (
    echo Установлена последняя версия: %LOCAL_VERSION%

    if "%1"=="soft" exit
    pause
    goto menu
)

echo Доступна новая версия: %GITHUB_VERSION%
echo Страница релиза: %GITHUB_RELEASE_URL%%GITHUB_VERSION%

echo Открываю страницу загрузки...
start "" "%GITHUB_DOWNLOAD_URL%"

if "%1"=="soft" exit
pause
goto menu


:: DIAGNOSTICS =========================
:service_diagnostics
chcp 65001 > nul
cls

call :PrintGreen "Zapret установлен в: '%~dp0'"
echo:

:: Base Filtering Engine
chcp 437 > nul
sc query BFE | findstr /I "RUNNING" > nul
chcp 65001 > nul
if !errorlevel!==0 (
    call :PrintGreen "Base Filtering Engine: OK"
) else (
    call :PrintRed "[X] Base Filtering Engine не запущен. Эта служба нужна для работы zapret."
)
echo:

:: Proxy check
set "proxyEnabled=0"
set "proxyServer="
for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i "ProxyEnable"') do (
    if "%%B"=="0x1" set "proxyEnabled=1"
)
if !proxyEnabled!==1 (
    for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i "ProxyServer"') do set "proxyServer=%%B"
    call :PrintYellow "[?] Системный прокси включён: !proxyServer!"
    call :PrintYellow "Убедитесь, что он рабочий, или отключите его."
) else (
    call :PrintGreen "Прокси: OK"
)
echo:

:: TCP timestamps
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul
if !errorlevel!==0 (
    call :PrintGreen "TCP timestamps: OK"
) else (
    call :PrintYellow "[?] TCP timestamps выключены. Включаю..."
    netsh interface tcp set global timestamps=enabled > nul 2>&1
    if !errorlevel!==0 ( call :PrintGreen "TCP timestamps успешно включены" ) else ( call :PrintRed "[X] Не удалось включить TCP timestamps" )
)
echo:

:: AdguardSvc.exe
tasklist /FI "IMAGENAME eq AdguardSvc.exe" | find /I "AdguardSvc.exe" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружен Adguard. Он может мешать работе Discord."
    set /p "FIXAD=Закрыть процесс Adguard? (Y/N): "
    if /i "!FIXAD!"=="Y" (
        taskkill /IM AdguardSvc.exe /F >nul 2>&1
        if !errorlevel!==0 ( call :PrintGreen "Adguard закрыт" ) else ( call :PrintRed "Не удалось закрыть Adguard" )
    )
) else (
    call :PrintGreen "Adguard: OK"
)
echo:

:: Killer
sc query | findstr /I "Killer" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружены службы Killer. Они конфликтуют с zapret."
    call :PrintYellow "Отключите их через services.msc вручную."
) else (
    call :PrintGreen "Killer: OK"
)
echo:

:: Intel Connectivity
sc query | findstr /I "Intel" | findstr /I "Connectivity" | findstr /I "Network" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружена служба Intel Connectivity Network. Она конфликтует с zapret."
    call :PrintYellow "Отключите её через services.msc вручную."
) else (
    call :PrintGreen "Intel Connectivity: OK"
)
echo:

:: Check Point
set "checkpointFound=0"
sc query | findstr /I "TracSrvWrapper" > nul && set "checkpointFound=1"
sc query | findstr /I "EPWD" > nul && set "checkpointFound=1"
if !checkpointFound!==1 (
    call :PrintRed "[X] Обнаружены службы Check Point. Они конфликтуют с zapret."
    call :PrintYellow "Попробуйте удалить Check Point через Панель управления."
) else (
    call :PrintGreen "Check Point: OK"
)
echo:

:: SmartByte
sc query | findstr /I "SmartByte" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружены службы SmartByte. Они конфликтуют с zapret."
    call :PrintYellow "Удалите или отключите SmartByte через services.msc"
) else (
    call :PrintGreen "SmartByte: OK"
)
echo:

:: Cyrillic path
powershell -NoProfile -Command "if ('%~dp0' -match '[\u0430-\u044F\u0410-\u042F\u0451\u0401]') { exit 0 } else { exit 1 }"
if !errorlevel!==0 (
    call :PrintRed "[X] Путь содержит кириллицу: %~dp0"
    call :PrintYellow "Перенесите папку в C:\ZapretRKN и запустите install.bat заново."
    set /p "FIXPATH=Открыть инструкцию? (Y/N): "
    if /i "!FIXPATH!"=="Y" (
        start notepad "%~dp0README.md"
    )
) else (
    call :PrintGreen "Путь без кириллицы: OK"
)
echo:

:: OneDrive
if defined OneDrive (
    echo %~dp0\ | findstr /I /C:"%OneDrive%\\" > nul
    if !errorlevel!==0 (
        call :PrintRed "[X] Zapret установлен в папке OneDrive."
        call :PrintYellow "Перенесите папку в C:\ZapretRKN"
    ) else (
        call :PrintGreen "OneDrive: OK"
    )
) else (
    call :PrintGreen "OneDrive: OK"
)
echo:

:: WinDivert64.sys
set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :PrintRed "Файл WinDivert64.sys НЕ найден."
    echo:
)

:: VPN
set "VPN_SERVICES="
sc query | findstr /I "VPN" > nul
if !errorlevel!==0 (
    for /f "tokens=2 delims=:" %%A in ('sc query ^| findstr /I "VPN"') do (
        if not defined VPN_SERVICES ( set "VPN_SERVICES=!VPN_SERVICES!%%A" ) else ( set "VPN_SERVICES=!VPN_SERVICES!,%%A" )
    )
    call :PrintYellow "[?] Обнаружены VPN-службы:!VPN_SERVICES!."
    call :PrintYellow "Убедитесь, что все VPN выключены."
) else (
    call :PrintGreen "VPN: OK"
)
echo:

:: DNS
set "dohfound=0"
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-ChildItem -Recurse -Path 'HKLM:System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\' | Get-ItemProperty | Where-Object { $_.DohFlags -gt 0 } | Measure-Object | Select-Object -ExpandProperty Count"') do (
    if %%a gtr 0 ( set "dohfound=1" )
)
if !dohfound!==0 (
    call :PrintYellow "[?] Настройте защищённый DNS в браузере (нестандартный провайдер),"
    call :PrintYellow "или в Windows 11 настройте шифрованный DNS в Параметрах."
) else (
    call :PrintGreen "Защищённый DNS: OK"
)
echo:

:: Hosts file
set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
if exist "%hostsFile%" (
    set "yt_found=0"
    >nul 2>&1 findstr /I "youtube.com" "%hostsFile%" && set "yt_found=1"
    >nul 2>&1 findstr /I "youtu.be" "%hostsFile%" && set "yt_found=1"
    if !yt_found!==1 (
        call :PrintYellow "[?] В файле hosts есть записи youtube.com или youtu.be."
        set /p "FIXHOSTS=Открыть hosts? (Y/N): "
        if /i "!FIXHOSTS!"=="Y" (
            start notepad "%hostsFile%"
        )
    )
)

:: WinDivert conflict
tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
set "winws_running=!errorlevel!"
chcp 437 > nul
sc query "WinDivert" | findstr /I "RUNNING STOP_PENDING" > nul
chcp 65001 > nul
set "windivert_running=!errorlevel!"
if !winws_running! neq 0 if !windivert_running!==0 (
    call :PrintYellow "[?] winws.exe не работает, но служба WinDivert активна."
    set /p "FIXWD=Удалить WinDivert? (Y/N): "
    if /i "!FIXWD!"=="Y" (
        net stop "WinDivert" >nul 2>&1
        sc delete "WinDivert" >nul 2>&1
        net stop "WinDivert14" >nul 2>&1
        sc delete "WinDivert14" >nul 2>&1
        call :PrintGreen "WinDivert удалён."
    )
    echo:
)

:: Conflicting bypasses
set "conflicting_services=GoodbyeDPI discordfix_zapret winws1 winws2"
set "found_any_conflict=0"
set "found_conflicts="
for %%s in (!conflicting_services!) do (
    sc query "%%s" >nul 2>&1
    if !errorlevel!==0 (
        if "!found_conflicts!"=="" ( set "found_conflicts=%%s" ) else ( set "found_conflicts=!found_conflicts! %%s" )
        set "found_any_conflict=1"
    )
)
if !found_any_conflict!==1 (
    call :PrintRed "[X] Найдены конфликтующие службы: !found_conflicts!"
    set /p "FIXCONF=Удалить эти службы? (Y/N): "
    if /i "!FIXCONF!"=="Y" (
        for %%s in (!found_conflicts!) do (
            net stop "%%s" >nul 2>&1
            sc delete "%%s" >nul 2>&1
        )
        net stop "WinDivert" >nul 2>&1
        sc delete "WinDivert" >nul 2>&1
        net stop "WinDivert14" >nul 2>&1
        sc delete "WinDivert14" >nul 2>&1
        call :PrintGreen "Конфликтующие службы удалены."
    )
    echo:
)

:: Discord cache
set "CHOICE="
set /p "CHOICE=Очистить кэш Discord? (Y/N, по умолчанию Y): "
if "!CHOICE!"=="" set "CHOICE=Y"
if /i "!CHOICE!"=="Y" (
    set "discordFound=0"
    if exist "%APPDATA%\discord\" ( set "discordFound=1" & call :clear_discord_cache "Discord.exe" "Discord" "%APPDATA%\discord" )
    if exist "%APPDATA%\discordptb\" ( set "discordFound=1" & call :clear_discord_cache "DiscordPTB.exe" "Discord PTB" "%APPDATA%\discordptb" )
    if exist "%APPDATA%\discordcanary\" ( set "discordFound=1" & call :clear_discord_cache "DiscordCanary.exe" "Discord Canary" "%APPDATA%\discordcanary" )
    if exist "%APPDATA%\discorddevelopment\" ( set "discordFound=1" & call :clear_discord_cache "DiscordDevelopment.exe" "Discord Development" "%APPDATA%\discorddevelopment" )
    if !discordFound! equ 0 call :PrintRed "Установки Discord не найдены"
    set "discordFound="
)
echo:

pause
goto menu


:: STRATEGY SWITCH ====================
:strategy_switch
chcp 65001 > nul
cls

set "STRAT_DIR=%~dp0strategies"
if not exist "%STRAT_DIR%\" (
    echo Папка strategies не найдена.
    echo Проверьте, что она есть рядом с service.bat.
    pause
    goto menu
)

:: Текущая стратегия из реестра
set "currentFile="
for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do set "currentFile=%%B"

echo   Смена стратегии
echo   ----------------------------------------
echo.
echo Текущая: !currentFile!
echo.
echo Доступные:
echo.

set "count=0"
for /f "delims=" %%F in ('dir /b /o:n "%STRAT_DIR%\*.bat" 2^>nul') do (
    set /a count+=1
    echo   !count!. %%F
    set "strat!count!=%%F"
)

if !count!==0 (
    echo В папке strategies нет .bat файлов.
    pause
    goto menu
)

echo.
echo   0. Отмена
echo.
set "strat_choice="
set /p "strat_choice=Выберите номер (0-!count!, по умолчанию: 0): "
if "!strat_choice!"=="" set "strat_choice=0"
if "!strat_choice!"=="0" goto menu

set "selected="
for /l %%N in (1,1,!count!) do (
    if "!strat_choice!"=="%%N" set "selected=!strat%%N!"
)
if not defined selected (
    echo Неверный номер.
    pause
    goto strategy_switch
)

echo.
echo Выбрана: !selected!
echo Копирую поверх general.bat...

copy /y "%STRAT_DIR%\!selected!" "%~dp0general.bat" >nul
if errorlevel 1 (
    call :PrintRed "Не удалось скопировать. Проверьте права."
    pause
    goto menu
)

:: Обновляем запись в реестре, чтобы отображалось в меню
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!selected!" /f >nul 2>&1

call :PrintGreen "Стратегия успешно сменена: !selected!"

:: Предложить перезапуск
echo.
set /p "restart=Перезапустить обход сейчас? (Y/N, по умолчанию Y): "
if "!restart!"=="" set "restart=Y"
if /i "!restart!"=="Y" (
    call :PrintYellow "Перезапускаю..."

    :: Останавливаем службу, если она есть
    sc query "zapret" >nul 2>&1
    if !errorlevel!==0 (
        net stop zapret >nul 2>&1
        sc start zapret >nul 2>&1
    )

    :: Убиваем winws.exe, если запущен вручную
    taskkill /IM winws.exe /F >nul 2>&1

    :: Запускаем general.bat скрыто
    start /b "" "%~dp0general.bat"
    call :PrintGreen "Обход перезапущен."
)

pause
goto menu


:: ENGINE UPDATE =======================
:engine_update
chcp 65001 > nul
cls

echo   Обновление движка (winws.exe + .bin)
echo   ----------------------------------------
echo.
echo Что произойдёт:
echo   - Скачаю последний релиз Flowseal с GitHub.
echo   - Сделаю бэкап старого bin\ в utils\backup\.
echo   - Заменю winws.exe, WinDivert64.sys и .bin-файлы.
echo.
echo Обход будет остановлен на время обновления.
echo.

set /p "eng_confirm=Продолжить? (Y/N): "
if /i not "!eng_confirm!"=="Y" goto menu

echo.
echo Останавливаю обход...

taskkill /IM winws.exe /F >nul 2>&1

sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    net stop zapret >nul 2>&1
)

:: Останавливаем драйвер WinDivert, чтобы освободить .sys-файлы
sc query "WinDivert" >nul 2>&1
if !errorlevel!==0 (
    net stop "WinDivert" >nul 2>&1
)
sc query "WinDivert14" >nul 2>&1
if !errorlevel!==0 (
    net stop "WinDivert14" >nul 2>&1
)

echo Ожидание освобождения файлов...
timeout /t 3 /nobreak >nul
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\scripts\update_engine.ps1"
if !errorlevel! neq 0 (
    call :PrintRed "Обновление завершилось с ошибкой."
    echo Бэкап старого bin лежит в utils\backup\.
    pause
    goto menu
)

echo.
call :PrintGreen "Движок обновлён."
echo.

:: Перезапуск
sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    set /p "eng_restart=Запустить службу обратно? (Y/N, по умолчанию Y): "
    if "!eng_restart!"=="" set "eng_restart=Y"
    if /i "!eng_restart!"=="Y" (
        sc start zapret >nul 2>&1
        call :PrintGreen "Служба запущена."
    )
) else (
    set /p "eng_restart=Запустить обход вручную? (Y/N, по умолчанию Y): "
    if "!eng_restart!"=="" set "eng_restart=Y"
    if /i "!eng_restart!"=="Y" (
        start /b "" "%~dp0general.bat"
        call :PrintGreen "Обход запущен."
    )
)

pause
goto menu

:: AUTOTEST STRATEGY ===================
:autotest_strategy
chcp 65001 > nul
cls

echo   Автоподбор стратегии
echo   ----------------------------------------
echo.
echo Что произойдёт:
echo   - Скрипт по очереди запустит каждую стратегию из strategies\.
echo   - Проверит доступность YouTube, Discord, Google.
echo   - Выберет лучшую и переключит на неё.
echo.
echo Обход будет остановлен на время теста (~1-2 минуты).
echo.

set /p "at_confirm=Продолжить? (Y/N): "
if /i not "!at_confirm!"=="Y" goto menu

echo.
echo Останавливаю обход...
taskkill /IM winws.exe /F >nul 2>&1
sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    net stop zapret >nul 2>&1
)

del /f /q "%TEMP%\zapret_best_strategy.txt" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\scripts\test_strategies.ps1"
set "AT_RESULT=!errorlevel!"

echo.
if "!AT_RESULT!"=="2" (
    call :PrintRed "Ни одна стратегия не сработала."
    pause
    goto menu
)
if "!AT_RESULT!" neq "0" (
    call :PrintRed "Тест завершился с ошибкой."
    pause
    goto menu
)

set "BEST="
for /f "usebackq delims=" %%B in ("%TEMP%\zapret_best_strategy.txt") do set "BEST=%%B"
if not defined BEST (
    call :PrintRed "Не удалось определить победителя."
    pause
    goto menu
)

echo Лучшая стратегия: !BEST!
set /p "at_apply=Применить её? (Y/N, по умолчанию Y): "
if "!at_apply!"=="" set "at_apply=Y"
if /i not "!at_apply!"=="Y" goto menu

copy /y "%~dp0strategies\!BEST!" "%~dp0general.bat" >nul
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!BEST!" /f >nul 2>&1

call :PrintGreen "Стратегия применена: !BEST!"

:: Перезапуск
sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    sc start zapret >nul 2>&1
    call :PrintGreen "Служба запущена."
) else (
    start /b "" "%~dp0general.bat"
    call :PrintGreen "Обход запущен."
)

pause
goto menu

:: GAME SWITCH ========================
:game_switch_status
chcp 437 > nul

set "gameFlagFile=%~dp0utils\game_filter.enabled"
set "GameFilterMode=disabled"
set "GameFilterTCPRange=1024-65535"
set "GameFilterUDPRange=1024-65535"
set "GameFilterStatus=disabled"
set "GameFilter=12"
set "GameFilterTCP=12"
set "GameFilterUDP=12"

if not exist "%gameFlagFile%" exit /b

set "GameFilterTCPCandidate="
set "GameFilterUDPCandidate="
for /f "usebackq tokens=1,* delims==" %%A in ("%gameFlagFile%") do (
    if /i "%%A"=="mode" set "GameFilterMode=%%B"
    if /i "%%A"=="all" set "GameFilterMode=all"
    if /i "%%A"=="udp" (
        if "%%B"=="" (set "GameFilterMode=udp") else set "GameFilterUDPCandidate=%%B"
    )
    if /i "%%A"=="tcp" (
        if "%%B"=="" (set "GameFilterMode=tcp") else set "GameFilterTCPCandidate=%%B"
    )
)

call :validate_game_filter_range "%GameFilterTCPCandidate%"
if defined ValidatedGameFilterRange set "GameFilterTCPRange=%ValidatedGameFilterRange%"
call :validate_game_filter_range "%GameFilterUDPCandidate%"
if defined ValidatedGameFilterRange set "GameFilterUDPRange=%ValidatedGameFilterRange%"

if /i "%GameFilterMode%"=="all" (
    set "GameFilterStatus=enabled (TCP and UDP)"
    set "GameFilter=%GameFilterTCPRange%"
    set "GameFilterTCP=%GameFilterTCPRange%"
    set "GameFilterUDP=%GameFilterUDPRange%"
) else if /i "%GameFilterMode%"=="tcp" (
    set "GameFilterStatus=enabled (TCP)"
    set "GameFilter=%GameFilterTCPRange%"
    set "GameFilterTCP=%GameFilterTCPRange%"
    set "GameFilterUDP=12"
) else if /i "%GameFilterMode%"=="udp" (
    set "GameFilterStatus=enabled (UDP)"
    set "GameFilter=%GameFilterUDPRange%"
    set "GameFilterTCP=12"
    set "GameFilterUDP=%GameFilterUDPRange%"
) else (
    set "GameFilterMode=disabled"
)
exit /b


:game_switch
chcp 65001 > nul
cls
call :game_switch_status

echo Настройка Game Filter:
if "%GameFilterMode%"=="disabled"   (echo   1. * Отключить) else        echo   1.   Отключить
if "%GameFilterMode%"=="all"        (echo   2. * TCP и UDP) else        echo   2.   TCP и UDP
if "%GameFilterMode%"=="tcp"        (echo   3. * TCP) else              echo   3.   TCP
if "%GameFilterMode%"=="udp"        (echo   4. * UDP) else              echo   4.   UDP
echo.
echo   5. Изменить диапазон TCP-портов (текущий: %GameFilterTCPRange%)
echo   6. Изменить диапазон UDP-портов (текущий: %GameFilterUDPRange%)
echo   7. Изменить диапазоны TCP и UDP
echo.
echo.  0. Выход
echo.
set "GameFilterChoice=0"
set /p "GameFilterChoice=Выберите пункт (0-7, по умолчанию: 0): "
if "%GameFilterChoice%"=="" set "GameFilterChoice=0"

if "%GameFilterChoice%"=="1" (
    set "GameFilterMode=disabled"
) else if "%GameFilterChoice%"=="2" (
    set "GameFilterMode=all"
) else if "%GameFilterChoice%"=="3" (
    set "GameFilterMode=tcp"
) else if "%GameFilterChoice%"=="4" (
    set "GameFilterMode=udp"
) else if "%GameFilterChoice%"=="5" (
    call :change_game_filter_range tcp
) else if "%GameFilterChoice%"=="6" (
    call :change_game_filter_range udp
) else if "%GameFilterChoice%"=="7" (
    call :change_game_filter_range all
) else (
    goto menu
)

echo.
call :save_game_filter_settings
call :PrintYellow "Перезапустите zapret, чтобы применить изменения."
pause
goto game_switch


:change_game_filter_range
set "GameFilterRangeInput="

echo.
echo Изменение портов для %~1 (пример: 1024-1934,1936-65535, по умолчанию: 1024-65535)
set /p "GameFilterRangeInput=Введите порты/диапазоны: "
call :validate_game_filter_range "%GameFilterRangeInput%"
if not defined ValidatedGameFilterRange (
    call :PrintRed "Неверный ввод. Введите корректные порты/диапазоны."
    pause
    goto game_switch
)

if /i "%~1"=="tcp" set "GameFilterTCPRange=%ValidatedGameFilterRange%"
if /i "%~1"=="udp" set "GameFilterUDPRange=%ValidatedGameFilterRange%"
if /i "%~1"=="all" (
    set "GameFilterTCPRange=%ValidatedGameFilterRange%"
    set "GameFilterUDPRange=%ValidatedGameFilterRange%"
)
exit /b


:validate_game_filter_range
set "ValidatedGameFilterRange="
setlocal EnableDelayedExpansion
set "GameFilterRangeToValidate=%~1"
set "GameFilterRangeToValidate=!GameFilterRangeToValidate: =!"
if not defined GameFilterRangeToValidate exit /b
for %%A in ("!GameFilterRangeToValidate:,=" "!") do (
    call :gf_validate_item "%%~A"
    if not defined GameFilterRangeItemValid exit /b
)
endlocal & set "ValidatedGameFilterRange=%GameFilterRangeToValidate%"
exit /b


:gf_validate_item
set "GameFilterRangeItemValid="
setlocal EnableDelayedExpansion
set "GameFilterRangeItem=%~1"

echo(!GameFilterRangeItem!| findstr /r /x /c:"[1-9][0-9]*" /c:"[1-9][0-9]*-[1-9][0-9]*" > nul || exit /b
for /f "tokens=1,2 delims=-" %%A in ("!GameFilterRangeItem!") do (
    set "GameFilterRangeStart=%%A"
    set "GameFilterRangeEnd=%%B"
)
if not defined GameFilterRangeEnd set "GameFilterRangeEnd=!GameFilterRangeStart!"

if not "!GameFilterRangeStart:~5,1!"=="" exit /b
if not "!GameFilterRangeEnd:~5,1!"=="" exit /b
set /a GameFilterRangeStartNumber=GameFilterRangeStart, GameFilterRangeEndNumber=GameFilterRangeEnd
if !GameFilterRangeStartNumber! gtr 65535 exit /b
if !GameFilterRangeEndNumber! gtr 65535 exit /b
if !GameFilterRangeStartNumber! gtr !GameFilterRangeEndNumber! exit /b

endlocal & set "GameFilterRangeItemValid=1"
exit /b


:save_game_filter_settings
>"%gameFlagFile%" (
    echo mode=%GameFilterMode%
    echo tcp=%GameFilterTCPRange%
    echo udp=%GameFilterUDPRange%
)
exit /b


:: CHECK UPDATES SWITCH =================
:check_updates_switch_status
chcp 437 > nul

set "checkUpdatesFlag=%~dp0utils\check_updates.enabled"

if exist "%checkUpdatesFlag%" (
    set "CheckUpdatesStatus=enabled"
) else (
    set "CheckUpdatesStatus=disabled"
)
exit /b


:check_updates_switch
chcp 65001 > nul
cls

if not exist "%checkUpdatesFlag%" (
    echo Включаю автопроверку обновлений...
    echo ENABLED > "%checkUpdatesFlag%"
) else (
    echo Отключаю автопроверку обновлений...
    del /f /q "%checkUpdatesFlag%"
)

pause
goto menu


:: REPLACE ACTIVE FAKES =================
:replace_active_fakes
chcp 65001 > nul
cls

set "BIN_PATH=%~dp0bin\"
set "fake_count=0"
set "fake_type="
set "fake_number="
set "discord_hash="
set "game_hash="
set "current_discord_fake=(не найден)"
set "current_game_fake=(не найден)"

if not exist "%BIN_PATH%" (
    echo Ошибка: папка bin не найдена.
    pause
    goto menu
)

pushd "%BIN_PATH%"
for /f "tokens=1,2,3 delims=|" %%A in ('powershell -NoProfile -Command "foreach ($item in @(@{Name='ACTIVE_DISCORD_UDP.bin'; Label='ACTIVE_DISCORD'},@{Name='ACTIVE_GAME_UDP.bin'; Label='ACTIVE_GAME'})) { if (Test-Path -LiteralPath $item.Name) { Write-Output ($item.Label + [char]124 + $item.Label + [char]124 + (Get-FileHash -LiteralPath $item.Name -Algorithm SHA256).Hash) } }; $files = @(Get-ChildItem -LiteralPath . -File -Filter '*.bin'); foreach ($file in $files) { if ($file.BaseName -notlike 'ACTIVE_*') { Write-Output ('FAKE' + [char]124 + $file.BaseName + [char]124 + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) } }"') do (
    if "%%A"=="ACTIVE_DISCORD" (
        set "discord_hash=%%C"
    ) else if "%%A"=="ACTIVE_GAME" (
        set "game_hash=%%C"
    ) else if "%%A"=="FAKE" (
        set /a fake_count+=1
        set "fake_file!fake_count!=%BIN_PATH%%%B.bin"
        set "fake_name!fake_count!=%%B"
        set "fake_hash!fake_count!=%%C"
    )
)
popd

if !fake_count! EQU 0 (
    echo В папке bin не найдено .bin-файлов.
    pause
    goto menu
)

for /l %%N in (1,1,!fake_count!) do (
    if defined discord_hash if /i "!fake_hash%%N!"=="!discord_hash!" set "current_discord_fake=!fake_name%%N!"
    if defined game_hash if /i "!fake_hash%%N!"=="!game_hash!" set "current_game_fake=!fake_name%%N!"
)

:replace_active_fakes_prompt
echo.
echo Введите номер типа фейка и номер файла-фейка, которым заменить.
echo Пример: 1 4 (заменяет Discord UDP на файл под номером 4)
echo         2 1 (заменяет GameFilter UDP на файл под номером 1)
echo.
echo Нажмите ENTER или 0 для возврата.
echo.
echo   ----------------------------------------
echo.
echo Типы фейков:
echo   1. Discord UDP     (текущий: !current_discord_fake!)
echo   2. GameFilter UDP  (текущий: !current_game_fake!)
echo.
echo Файлы-фейки:
for /l %%N in (1,1,!fake_count!) do echo   %%N. !fake_name%%N!
echo.

set "replace_choice="
set /p "replace_choice=Введите выбор: "
if not defined replace_choice goto menu
if "!replace_choice!"=="0" goto menu

set "active_file="
set "fake_type="
set "fake_number="
for /f "tokens=1,2" %%A in ("!replace_choice!") do (
    set "fake_type=%%A"
    set "fake_number=%%B"
)

if "!fake_type!"=="1" (
    set "active_file=%BIN_PATH%ACTIVE_DISCORD_UDP.bin"
) else if "!fake_type!"=="2" (
    set "active_file=%BIN_PATH%ACTIVE_GAME_UDP.bin"
) else (
    echo Неверный тип фейка.
    pause
    cls
    goto replace_active_fakes_prompt
)

set "source_file="
for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" set "source_file=!fake_file%%N!"
if not defined source_file (
    echo Неверный номер файла-фейка.
    pause
    cls
    goto replace_active_fakes_prompt
)

del /f /q "!active_file!" >nul 2>&1
copy /y "!source_file!" "!active_file!" >nul
if errorlevel 1 (
    echo Не удалось заменить активный файл-фейк.
) else (
    echo Активный файл-фейк успешно заменён.
    for /l %%N in (1,1,!fake_count!) do if "%%N"=="!fake_number!" (
        if "!fake_type!"=="1" set "current_discord_fake=!fake_name%%N!"
        if "!fake_type!"=="2" set "current_game_fake=!fake_name%%N!"
    )
)
pause
cls
goto replace_active_fakes_prompt


:: IPSET SWITCH =======================
:ipset_switch_status
chcp 437 > nul

set "listFile=%~dp0lists\ipset-all.txt"
for /f %%i in ('type "%listFile%" 2^>nul ^| find /c /v ""') do set "lineCount=%%i"

if !lineCount!==0 (
    set "IPsetStatus=any"
) else (
    findstr /C:"203.0.113.113/32" "%listFile%" >nul
    if !errorlevel!==0 (
        set "IPsetStatus=none"
    ) else (
        set "IPsetStatus=loaded"
    )
)
exit /b


:ipset_switch
chcp 65001 > nul
cls

set "listFile=%~dp0lists\ipset-all.txt"
set "backupFile=%listFile%.backup"

if "%IPsetStatus%"=="loaded" (
    echo Переключение в режим "отключён"...

    if not exist "%backupFile%" (
        ren "%listFile%" "ipset-all.txt.backup"
    ) else (
        del /f /q "%backupFile%"
        ren "%listFile%" "ipset-all.txt.backup"
    )

    >"%listFile%" (
        echo 203.0.113.113/32
    )

) else if "%IPsetStatus%"=="none" (
    echo Переключение в режим "любой"...

    >"%listFile%" (
        rem Creating empty file
    )

) else if "%IPsetStatus%"=="any" (
    echo Переключение в режим "загружен"...

    if exist "%backupFile%" (
        del /f /q "%listFile%"
        ren "%backupFile%" "ipset-all.txt"
    ) else (
        echo Ошибка: нет бэкапа для восстановления. Сначала обновите список из меню.
        pause
        goto menu
    )

)

pause
goto menu


:: IPSET UPDATE =======================
:ipset_update
chcp 65001 > nul
cls

set "listFile=%~dp0lists\ipset-all.txt"
set "url=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt"

echo Обновление ipset-all...

if exist "%SystemRoot%\System32\curl.exe" (
    curl --version | find "libcurl/7"
    if !errorlevel!==0 (
        curl --ssl-no-revoke -L -f -o "%listFile%" "%url%"
    ) else (
        curl --ssl-revoke-best-effort -L -f -o "%listFile%" "%url%"
    )
) else (
    powershell -NoProfile -Command ^
        "$url = '%url%';" ^
        "$out = '%listFile%';" ^
        "$dir = Split-Path -Parent $out;" ^
        "if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null };" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8 } else { exit 1 }"
)

echo Готово

pause
goto menu


:: HOSTS UPDATE =======================
:hosts_update
chcp 65001 > nul
cls

set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
set "hostsUrl=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts"
set "tempFile=%TEMP%\zapret_hosts.txt"
set "needsUpdate=0"

:: === БЭКАП HOSTS ПЕРЕД ОБНОВЛЕНИЕМ ===
if not exist "%~dp0utils\backup\" mkdir "%~dp0utils\backup\"
copy "%SystemRoot%\System32\drivers\etc\hosts" "%~dp0utils\backup\hosts_backup_%date:~-4%%date:~3,2%%date:~0,2%.txt" >nul
:: =====================================

set "cacheBuster=%RANDOM%%RANDOM%%RANDOM%"
set "requestUrl=%hostsUrl%?t=%cacheBuster%"

echo Проверка файла hosts...

if exist "%SystemRoot%\System32\curl.exe" (
    curl -L -s -f -o "%tempFile%" "%requestUrl%"
) else (
    powershell -NoProfile -Command ^
        "$url = '%requestUrl%';" ^
        "$out = '%tempFile%';" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8 } else { exit 1 }"
)
if not exist "%tempFile%" (
    call :PrintRed "Не удалось скачать файл hosts из репозитория"
    call :PrintYellow "Скопируйте hosts вручную из %hostsUrl%"
    pause
    goto menu
)

set "firstLine="
set "lastLine="
for /f "usebackq delims=" %%a in ("%tempFile%") do (
    if not defined firstLine (
        set "firstLine=%%a"
    )
    set "lastLine=%%a"
)

findstr /C:"!firstLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    echo Первая строка из репозитория не найдена в hosts
    set "needsUpdate=1"
)

findstr /C:"!lastLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    echo Последняя строка из репозитория не найдена в hosts
    set "needsUpdate=1"
)

if "%needsUpdate%"=="1" (
    echo:
    call :PrintYellow "Файл hosts требует обновления"
    call :PrintYellow "Скопируйте содержимое из открытого файла в hosts вручную"

    start notepad "%tempFile%"
    explorer /select,"%hostsFile%"
) else (
    call :PrintGreen "Файл hosts актуален"
    if exist "%tempFile%" del /f /q "%tempFile%"
)

echo:
pause
goto menu


:: RUN TESTS =============================
:run_tests
chcp 65001 >nul
cls

:: Require PowerShell 3.0+
powershell -NoProfile -Command "if ($PSVersionTable -and $PSVersionTable.PSVersion -and $PSVersionTable.PSVersion.Major -ge 3) { exit 0 } else { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo Требуется PowerShell 3.0 или новее.
    echo Обновите PowerShell и запустите снова.
    echo.
    pause
    goto menu
)

echo Запуск тестов конфигурации в окне PowerShell...
echo.
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\test zapret.ps1"
pause
goto menu


:: Get strategy name
:get_strategy_name
set "CurrentStrategy="
for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do set "CurrentStrategy=Стратегия: %%B"
exit /b


:: Utility functions

:clear_discord_cache
setlocal EnableDelayedExpansion
set "discordProcess=%~1"
set "discordName=%~2"
set "discordCacheDir=%~3"

tasklist /FI "IMAGENAME eq !discordProcess!" 2>nul | findstr /I /C:"!discordProcess!" >nul
if !errorlevel! equ 0 (
    echo !discordName! запущен, закрываю...
    taskkill /IM "!discordProcess!" /F >nul 2>&1
    if !errorlevel! equ 0 (
        call :PrintGreen "!discordName! успешно закрыт"
    ) else (
        call :PrintRed "Не удалось закрыть !discordName!"
    )
)

if exist "!discordCacheDir!\" (
    for %%d in ("Cache" "Code Cache" "GPUCache") do (
        set "dirPath=!discordCacheDir!\%%~d"
        if exist "!dirPath!\" (
            rd /s /q "!dirPath!" >nul 2>&1
            if exist "!dirPath!\" (
                call :PrintRed "Не удалось удалить !dirPath!"
            ) else (
                call :PrintGreen "Успешно удалено: !dirPath!"
            )
        ) else (
            call :PrintRed "!dirPath! не существует"
        )
    )
)

endlocal
exit /b

:PrintGreen
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Green"
exit /b

:PrintRed
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Red"
exit /b

:PrintYellow
powershell -NoProfile -Command "Write-Host \"%~1\" -ForegroundColor Yellow"
exit /b

:check_command
where %1 >nul 2>&1
if %errorLevel% neq 0 (
    echo [ОШИБКА] %1 не найден в PATH
    echo Исправьте переменную PATH по инструкции: https://github.com/Flowseal/zapret-discord-youtube/issues/7490
    pause
    exit /b 1
)
exit /b 0

:check_extracted
set "extracted=1"

if not exist "%~dp0bin\" set "extracted=0"

if "%extracted%"=="0" (
    echo Zapret нужно распаковать из архива, либо папка bin не найдена.
    pause
    exit
)
exit /b 0