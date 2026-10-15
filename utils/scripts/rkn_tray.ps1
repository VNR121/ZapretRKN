# rkn_tray.ps1 - ZapretRKN tray icon

$logPath = Join-Path $env:TEMP "zapret_tray.log"
"===== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Out-File -Append -Encoding UTF8 $logPath

try {

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, "Local\ZapretRKNTray_v1")
$acquired = $false
try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
if (-not $acquired) { exit }

$script:scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:utilsDir     = Split-Path -Parent $script:scriptDir
$script:projectRoot  = Split-Path -Parent $script:utilsDir
$script:iconPath     = Join-Path $script:scriptDir "icon.ico"
$script:iconGreyPath = Join-Path $script:scriptDir "icon_grey.ico"
$script:vbsPath      = Join-Path $script:scriptDir "run_hidden.vbs"
$script:checkerPath  = Join-Path $script:scriptDir "check_updates.ps1"
$script:connChecker  = Join-Path $script:scriptDir "check_connectivity.ps1"
$script:serviceBat   = Join-Path $script:projectRoot "service.bat"
$script:generalBat   = Join-Path $script:projectRoot "general.bat"
$script:stratDir     = Join-Path $script:projectRoot "strategies"
$script:listsDir     = Join-Path $script:projectRoot "lists"
$script:userListFile = Join-Path $script:listsDir "list-general-user.txt"
$script:updateFile   = Join-Path $env:TEMP "zapret_update.txt"
$script:connFile     = Join-Path $env:TEMP "zapret_connectivity.txt"
$script:regPath      = "HKLM:\System\CurrentControlSet\Services\zapret"
$script:regValue     = "zapret-discord-youtube"

$script:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not ("ZapretRKN_MenuRenderer" -as [type])) {
    $wfPath      = [System.Windows.Forms.Form].Assembly.Location
    $drawingPath = [System.Drawing.Bitmap].Assembly.Location
    Add-Type -ReferencedAssemblies $wfPath, $drawingPath -TypeDefinition @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class ZapretRKN_DarkColorTable : ProfessionalColorTable
{
    public override Color MenuItemSelected { get { return Color.FromArgb(50, 60, 60, 60); } }
    public override Color MenuItemSelectedGradientBegin { get { return Color.FromArgb(50, 60, 60, 60); } }
    public override Color MenuItemSelectedGradientEnd { get { return Color.FromArgb(50, 60, 60, 60); } }
    public override Color MenuItemBorder { get { return Color.FromArgb(0, 0, 0, 0); } }
    public override Color MenuBorder { get { return Color.FromArgb(60, 60, 60); } }
    public override Color ToolStripDropDownBackground { get { return Color.FromArgb(32, 32, 32); } }
    public override Color ImageMarginGradientBegin { get { return Color.FromArgb(32, 32, 32); } }
    public override Color ImageMarginGradientMiddle { get { return Color.FromArgb(32, 32, 32); } }
    public override Color ImageMarginGradientEnd { get { return Color.FromArgb(32, 32, 32); } }
    public override Color MenuItemPressedGradientBegin { get { return Color.FromArgb(45, 45, 45); } }
    public override Color MenuItemPressedGradientEnd { get { return Color.FromArgb(45, 45, 45); } }
    public override Color SeparatorDark { get { return Color.FromArgb(0, 0, 0, 0); } }
    public override Color SeparatorLight { get { return Color.FromArgb(0, 0, 0, 0); } }
}

public class ZapretRKN_MenuRenderer : ToolStripProfessionalRenderer
{
    public ZapretRKN_MenuRenderer() : base(new ZapretRKN_DarkColorTable()) { }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        if (e.Item.Selected && e.Item.Enabled)
        {
            Rectangle r = new Rectangle(0, 0, e.Item.Width, e.Item.Height);
            using (SolidBrush b = new SolidBrush(Color.FromArgb(50, 60, 60, 60)))
                e.Graphics.FillRectangle(b, r);
            using (SolidBrush accent = new SolidBrush(Color.FromArgb(80, 140, 210)))
                e.Graphics.FillRectangle(accent, 0, 0, 3, e.Item.Height);
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        if (e.Item.Enabled)
            e.TextColor = Color.FromArgb(235, 235, 235);
        else
            e.TextColor = Color.FromArgb(130, 130, 130);
        base.OnRenderItemText(e);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        using (Pen p = new Pen(Color.FromArgb(55, 55, 55)))
        {
            int y = e.Item.Height / 2;
            e.Graphics.DrawLine(p, 12, y, e.Item.Width - 12, y);
        }
    }
}
"@
}

if (-not ("ZapretRKN_WinApi" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ZapretRKN_WinApi {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}

function Load-Icon($path) {
    if (-not (Test-Path $path)) { return $null }
    try { return New-Object System.Drawing.Icon($path) } catch {
        try {
            $bmp = New-Object System.Drawing.Bitmap($path)
            $h = $bmp.GetHicon()
            return [System.Drawing.Icon]::FromHandle($h)
        } catch { return $null }
    }
}

$script:iconRed  = Load-Icon $script:iconPath
$script:iconGrey = Load-Icon $script:iconGreyPath
if ($null -eq $script:iconRed)  { $script:iconRed  = [System.Drawing.SystemIcons]::Application }
if ($null -eq $script:iconGrey) { $script:iconGrey = $script:iconRed }

$script:notifiedVersion       = $null
$script:engineVersion         = $null
$script:connectivityStatus    = "unknown"
$script:releaseUrl            = "https://github.com/VNR121/ZapretRKN/releases/latest"
$script:balloonOpensRelease   = $false
$script:autostartCached       = $false
$script:autostartLastCheck    = [DateTime]::MinValue

$script:engineVersionFile = Join-Path $script:projectRoot "bin\engine_version.txt"
if (Test-Path $script:engineVersionFile) {
    try { $script:engineVersion = (Get-Content $script:engineVersionFile -Raw).Trim() } catch { }
}

# --- Helpers ---
function Get-ZapretStatus {
    $p = Get-Process -Name winws -ErrorAction SilentlyContinue
    if ($p) { return "running" } else { return "stopped" }
}

function Get-CurrentStrategy {
    try {
        return (Get-ItemProperty -Path $script:regPath -Name $script:regValue -ErrorAction Stop).$script:regValue
    } catch { return $null }
}

function Get-AutostartCached {
    if (((Get-Date) - $script:autostartLastCheck).TotalSeconds -lt 30) {
        return $script:autostartCached
    }
    try {
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            $t = Get-ScheduledTask -TaskName "ZapretRKN" -ErrorAction SilentlyContinue
            $script:autostartCached = [bool]$t
        } else {
            # fallback для систем без модуля ScheduledTasks
            & schtasks.exe /Query /TN "ZapretRKN" 2>$null | Out-Null
            $script:autostartCached = ($LASTEXITCODE -eq 0)
        }
    } catch {
        $script:autostartCached = $false
    }
    $script:autostartLastCheck = Get-Date
    return $script:autostartCached
}

function Hide-WinwsWindow {
    for ($i = 0; $i -lt 5; $i++) {
        $found = $false
        Get-Process -Name winws -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.MainWindowHandle -ne [IntPtr]::Zero) {
                [ZapretRKN_WinApi]::ShowWindow($_.MainWindowHandle, 0) | Out-Null
                $found = $true
            }
        }
        if (-not $found) { break }
        Start-Sleep -Milliseconds 300
    }
}

function Stop-Zapret {
    Get-Process -Name winws -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

function Start-Zapret {
    if (-not $script:isAdmin) {
        $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
        $script:notifyIcon.BalloonTipText  = "Для запуска обхода нужны права администратора."
        $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
        $script:notifyIcon.ShowBalloonTip(4000)
        return
    }
    if (Test-Path $script:vbsPath) {
        Start-Process -FilePath "wscript.exe" -ArgumentList "`"$script:vbsPath`" `"$script:generalBat`"" -WindowStyle Hidden
    } else {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$script:generalBat`"" -WindowStyle Hidden
    }
    Start-Sleep -Milliseconds 1500
    Hide-WinwsWindow
}

function Start-UpdateCheck {
    if (-not (Test-Path $script:checkerPath)) { return }
    Remove-Item $script:updateFile -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$script:checkerPath`"" `
        -WindowStyle Hidden
}

function Start-ConnectivityCheck {
    if (-not (Test-Path $script:connChecker)) { return }
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$script:connChecker`"" `
        -WindowStyle Hidden
}

function Update-EngineVersion {
    if (Test-Path $script:engineVersionFile) {
        try {
            $v = (Get-Content $script:engineVersionFile -Raw).Trim()
            if ($v) { $script:engineVersion = $v }
        } catch { }
    }
}

function Switch-Strategy {
    param([string]$Name)
    if (-not $script:isAdmin) {
        $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
        $script:notifyIcon.BalloonTipText  = "Смена стратегии требует прав администратора."
        $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
        $script:notifyIcon.ShowBalloonTip(4000)
        return $false
    }
    try {
        $src = Join-Path $script:stratDir $Name
        if (-not (Test-Path $src)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Файл стратегии не найден: $src",
                "ZapretRKN", [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return $false
        }
        Copy-Item -Path $src -Destination $script:generalBat -Force
        try {
            Set-ItemProperty -Path $script:regPath -Name $script:regValue -Value $Name -ErrorAction Stop
        } catch { }
        Stop-Zapret
        Start-Sleep -Milliseconds 300
        Start-Zapret
        return $true
    } catch {
        $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
        $script:notifyIcon.BalloonTipText  = "Не удалось сменить стратегию: $($_.Exception.Message)"
        $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Error
        $script:notifyIcon.ShowBalloonTip(5000)
        return $false
    }
}

function Show-UserListsEditor {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "ZapretRKN - Свой список доменов"
    $form.Size = New-Object System.Drawing.Size(560, 460)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $form.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Каждая строка - один домен. После сохранения перезапустите обход."
    $label.Location = New-Object System.Drawing.Point(12, 10)
    $label.Size = New-Object System.Drawing.Size(520, 20)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Both"
    $textBox.Location = New-Object System.Drawing.Point(12, 35)
    $textBox.Size = New-Object System.Drawing.Size(520, 340)
    $textBox.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
    $textBox.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
    $textBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $textBox.AcceptsReturn = $true

    if (Test-Path $script:userListFile) {
        try { $textBox.Text = [System.IO.File]::ReadAllText($script:userListFile, [System.Text.Encoding]::UTF8) }
        catch { $textBox.Text = "" }
    } else {
        $textBox.Text = "# Список ваших доменов. По одному на строку.`r`n# Пример:`r`ndomain.example.abc"
    }
    $form.Controls.Add($textBox)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Сохранить"
    $btnSave.Location = New-Object System.Drawing.Point(347, 385)
    $btnSave.Size = New-Object System.Drawing.Size(90, 28)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(60, 100, 60)
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.FlatStyle = "Flat"
    $form.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Отмена"
    $btnCancel.Location = New-Object System.Drawing.Point(442, 385)
    $btnCancel.Size = New-Object System.Drawing.Size(90, 28)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = "Flat"
    $form.Controls.Add($btnCancel)

    $btnSave.add_Click({
        try {
            $content = $textBox.Text -replace "`r`n", "`n" -replace "`r", "`n"
            [System.IO.File]::WriteAllText($script:userListFile, $content, (New-Object System.Text.UTF8Encoding($false)))
            $form.DialogResult = "OK"
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Не удалось сохранить: $($_.Exception.Message)", "ZapretRKN",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })
    $btnCancel.add_Click({ $form.DialogResult = "Cancel"; $form.Close() })

    if ($form.ShowDialog() -eq "OK") {
        $restart = [System.Windows.Forms.MessageBox]::Show(
            "Список сохранён. Перезапустить обход сейчас?", "ZapretRKN",
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($restart -eq "Yes") {
            Stop-Zapret; Start-Sleep -Milliseconds 300; Start-Zapret
        }
    }
}

# --- NotifyIcon ---
# --- Дождаться загрузки Explorer (иначе трей не появится при автозапуске) ---
$wait = 0
while (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue) -and $wait -lt 90) {
    Start-Sleep -Seconds 2
    $wait += 2
}
Start-Sleep -Seconds 3

$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:notifyIcon.Icon    = $script:iconRed
$script:notifyIcon.Text    = "ZapretRKN"
$script:notifyIcon.Visible = $true

# --- Menu ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Renderer = New-Object ZapretRKN_MenuRenderer
$menu.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$menu.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$menu.ShowImageMargin = $false
$menu.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$menu.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)

$script:itemHeader    = New-Object System.Windows.Forms.ToolStripMenuItem("ZapretRKN")
$script:itemHeader.Enabled = $false
$script:itemToggle    = New-Object System.Windows.Forms.ToolStripMenuItem("Остановить")
$script:itemRestart   = New-Object System.Windows.Forms.ToolStripMenuItem("Перезапустить")
$script:itemStrategy  = New-Object System.Windows.Forms.ToolStripMenuItem("Стратегия")
$script:itemStrategy.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$script:itemUserList  = New-Object System.Windows.Forms.ToolStripMenuItem("Свой список доменов")
$script:itemAutostart = New-Object System.Windows.Forms.ToolStripMenuItem("Автозагрузка: выкл")

$itemMore = New-Object System.Windows.Forms.ToolStripMenuItem("Ещё")
$script:itemService  = New-Object System.Windows.Forms.ToolStripMenuItem("Менеджер службы")
$script:itemFolder   = New-Object System.Windows.Forms.ToolStripMenuItem("Папка ZapretRKN")
$itemCheckUpd        = New-Object System.Windows.Forms.ToolStripMenuItem("Проверить обновления")
$itemAbout           = New-Object System.Windows.Forms.ToolStripMenuItem("О программе")
[void]$itemMore.DropDownItems.Add($script:itemService)
[void]$itemMore.DropDownItems.Add($script:itemFolder)
[void]$itemMore.DropDownItems.Add($itemCheckUpd)
[void]$itemMore.DropDownItems.Add($itemAbout)

$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem("Закрыть трей")
$script:itemStrategy.DropDownDirection = [System.Windows.Forms.ToolStripDropDownDirection]::Right
$itemMore.DropDownDirection = [System.Windows.Forms.ToolStripDropDownDirection]::Right

$script:strategyItems = @{}
if (Test-Path $script:stratDir) {
    $strategies = @(Get-ChildItem -Path $script:stratDir -Filter "*.bat" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($strategies.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.ToolStripMenuItem("(нет стратегий)")
        $empty.Enabled = $false
        [void]$script:itemStrategy.DropDownItems.Add($empty)
    } else {
        foreach ($s in $strategies) {
            $sub = New-Object System.Windows.Forms.ToolStripMenuItem($s.Name)
            $sub.Tag = $s.Name
            $sub.add_Click({
                param($sender, $e)
                if (Switch-Strategy -Name $sender.Tag) { Update-TrayState }
            })
            [void]$script:itemStrategy.DropDownItems.Add($sub)
            $script:strategyItems[$s.Name] = $sub
        }
    }
} else {
    $empty = New-Object System.Windows.Forms.ToolStripMenuItem("(папка strategies не найдена)")
    $empty.Enabled = $false
    [void]$script:itemStrategy.DropDownItems.Add($empty)
}

$itemPadding = New-Object System.Windows.Forms.Padding(8, 2, 16, 2)
foreach ($it in @($script:itemToggle, $script:itemRestart, $script:itemStrategy, $script:itemUserList, $script:itemAutostart, $itemMore, $itemExit)) {
    $it.Padding = $itemPadding
}

[void]$menu.Items.Add($script:itemHeader)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($script:itemToggle)
[void]$menu.Items.Add($script:itemRestart)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($script:itemStrategy)
[void]$menu.Items.Add($script:itemUserList)
[void]$menu.Items.Add($script:itemAutostart)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemMore)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemExit)

$script:notifyIcon.ContextMenuStrip = $menu

# --- State updater ---
function Update-TrayState {
    try {
        $status = Get-ZapretStatus

        if (Test-Path $script:connFile) {
            $raw = ""
            try { $raw = (Get-Content $script:connFile -Raw -ErrorAction Stop).Trim() } catch { }
            if ($raw -match '^(\d+)\|(\d+)\|(\d+)$') {
                $ts = [int64]$matches[3]
                if (([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $ts) -lt 120) {
                    $got = [int]$matches[1]; $tot = [int]$matches[2]
                    if ($tot -gt 0 -and $got -ge 2) { $script:connectivityStatus = "ok" }
                    elseif ($got -ge 1) { $script:connectivityStatus = "weak" }
                    else { $script:connectivityStatus = "fail" }
                }
            }
        }

        $connSuffix = ""
        if ($status -eq "running") {
            if ($script:connectivityStatus -eq "weak") { $connSuffix = " (связь слабая)" }
            elseif ($script:connectivityStatus -eq "fail") { $connSuffix = " (нет связи)" }
        }

        if ($status -eq "running") {
            $script:notifyIcon.Icon = $script:iconRed
            $tip = "ZapretRKN - Работает$connSuffix"
            if ($script:engineVersion) { $tip += " | $($script:engineVersion)" }
            if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
            $script:notifyIcon.Text = $tip
            $script:itemToggle.Text = "Остановить"
            $script:itemHeader.Text = "ZapretRKN - Работает$connSuffix"
        } else {
            $script:notifyIcon.Icon = $script:iconGrey
            $script:notifyIcon.Text = "ZapretRKN - Остановлен"
            $script:itemToggle.Text = "Запустить"
            $script:itemHeader.Text = "ZapretRKN - Остановлен"
        }

        if (Get-AutostartCached) { $script:itemAutostart.Text = "Автозагрузка: ВКЛ" }
        else { $script:itemAutostart.Text = "Автозагрузка: выкл" }

        $cur = Get-CurrentStrategy
        if ($cur) { $script:itemStrategy.Text = "Стратегия: $cur" }
        else { $script:itemStrategy.Text = "Стратегия: (не определена)" }

        foreach ($name in $script:strategyItems.Keys) {
            $want = ($name -eq $cur)
            if ($script:strategyItems[$name].Checked -ne $want) {
                $script:strategyItems[$name].Checked = $want
            }
        }
    } catch {
        "TrayState error: $($_.Exception.Message)" | Out-File -Append -Encoding UTF8 $logPath
    }
}

# --- Events ---
$script:notifyIcon.add_BalloonTipClicked({
    if ($script:balloonOpensRelease) {
        $script:balloonOpensRelease = $false
        Start-Process $script:releaseUrl
    }
})

$script:notifyIcon.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $status = if ((Get-ZapretStatus) -eq "running") { "Работает" } else { "Остановлен" }
        $script:balloonOpensRelease = $false
        $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
        $script:notifyIcon.BalloonTipText  = "$status"
        $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
        $script:notifyIcon.ShowBalloonTip(3000)
    }
})

$script:notifyIcon.add_DoubleClick({
    Start-Process -FilePath $script:serviceBat -WorkingDirectory $script:projectRoot
})

$script:itemToggle.add_Click({
    if ((Get-ZapretStatus) -eq "running") { Stop-Zapret } else { Start-Zapret }
    Update-TrayState
})

$script:itemRestart.add_Click({
    Stop-Zapret; Start-Sleep -Milliseconds 200; Start-Zapret; Update-TrayState
})

$script:itemUserList.add_Click({ Show-UserListsEditor })

$script:itemAutostart.add_Click({
    if (Get-AutostartCached) {
        Unregister-ScheduledTask -TaskName "ZapretRKN" -Confirm:$false -ErrorAction SilentlyContinue
    } else {
        try {
            $action    = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ('"' + $script:vbsPath + '" "' + $script:generalBat + '"')
            $trigger   = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            Register-ScheduledTask -TaskName "ZapretRKN" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        } catch {
            $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
            $script:notifyIcon.BalloonTipText  = "Автозагрузка требует прав администратора."
            $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
            $script:notifyIcon.ShowBalloonTip(4000)
        }
    }
    $script:autostartLastCheck = [DateTime]::MinValue
    Update-TrayState
})

$script:itemService.add_Click({ Start-Process -FilePath $script:serviceBat -WorkingDirectory $script:projectRoot })
$script:itemFolder.add_Click({ Start-Process -FilePath "explorer.exe" -ArgumentList "`"$script:projectRoot`"" })

$itemCheckUpd.add_Click({
    $script:notifiedVersion = $null
    $script:balloonOpensRelease = $false
    Start-UpdateCheck
    $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
    $script:notifyIcon.BalloonTipText  = "Проверка обновлений запущена..."
    $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
    $script:notifyIcon.ShowBalloonTip(2000)
})

$itemAbout.add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "ZapretRKN v1.2.1`nОбход DPI-блокировок`n`nФорк Flowseal/zapret-discord-youtube`nhttps://github.com/VNR121/ZapretRKN",
        "О программе", [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

$itemExit.add_Click({
    $script:notifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

# --- Init ---
Start-Sleep -Milliseconds 100
Hide-WinwsWindow
Update-EngineVersion
Update-TrayState
Start-ConnectivityCheck

# --- Timers ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({ Update-TrayState })
$timer.Start()

$updTimer = New-Object System.Windows.Forms.Timer
$updTimer.Interval = 5000
$updTimer.add_Tick({
    if (Test-Path $script:updateFile) {
        $data = ""
        try { $data = (Get-Content $script:updateFile -Raw -ErrorAction Stop).Trim() } catch { }
        Remove-Item $script:updateFile -Force -ErrorAction SilentlyContinue
        if ($data -match '^(.+)\|(.+)$') {
            $remote = $matches[1]; $local = $matches[2]
            if ($remote -ne $script:notifiedVersion) {
                $script:notifiedVersion = $remote
                $script:balloonOpensRelease = $true
                $script:notifyIcon.BalloonTipTitle = "ZapretRKN - доступно обновление"
                $script:notifyIcon.BalloonTipText  = "Текущая: $local. Новая: $remote. Клик - открыть страницу."
                $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
                $script:notifyIcon.ShowBalloonTip(10000)
            }
        }
    }
})
$updTimer.Start()

$connTimer = New-Object System.Windows.Forms.Timer
$connTimer.Interval = 60000
$connTimer.add_Tick({
    if ((Get-ZapretStatus) -eq "running") { Start-ConnectivityCheck }
})
$connTimer.Start()

$engTimer = New-Object System.Windows.Forms.Timer
$engTimer.Interval = 600000
$engTimer.add_Tick({ Update-EngineVersion })
$engTimer.Start()

$initTimer = New-Object System.Windows.Forms.Timer
$initTimer.Interval = 30000
$initTimer.add_Tick({ $initTimer.Stop(); $initTimer.Dispose(); Start-UpdateCheck })
$initTimer.Start()

$verTimer = New-Object System.Windows.Forms.Timer
$verTimer.Interval = 43200000
$verTimer.add_Tick({ Start-UpdateCheck })
$verTimer.Start()

# --- Ротация лога ---
try {
    if ((Test-Path $logPath) -and ((Get-Item $logPath).Length -gt 1MB)) {
        Remove-Item $logPath -Force -ErrorAction SilentlyContinue
    }
} catch { }

[System.Windows.Forms.Application]::Run()

} catch {
    "FATAL: $($_.Exception.Message)" | Out-File -Append -Encoding UTF8 $logPath
    "Stack: $($_.ScriptStackTrace)" | Out-File -Append -Encoding UTF8 $logPath
    exit 1
} finally {
    try { if ($script:notifyIcon) { $script:notifyIcon.Visible = $false; $script:notifyIcon.Dispose() } } catch { }
    try { if ($mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() } } catch { }
}