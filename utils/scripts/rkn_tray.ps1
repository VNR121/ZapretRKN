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

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$utilsDir     = Split-Path -Parent $scriptDir
$projectRoot  = Split-Path -Parent $utilsDir
$iconPath     = Join-Path $scriptDir "icon.ico"
$iconGreyPath = Join-Path $scriptDir "icon_grey.ico"
$vbsPath      = Join-Path $scriptDir "run_hidden.vbs"
$checkerPath  = Join-Path $scriptDir "check_updates.ps1"
$serviceBat   = Join-Path $projectRoot "service.bat"
$generalBat   = Join-Path $projectRoot "general.bat"
$stratDir     = Join-Path $projectRoot "strategies"
$updateFile   = Join-Path $env:TEMP "zapret_update.txt"
$regPath      = "HKLM:\System\CurrentControlSet\Services\zapret"
$regValue     = "zapret-discord-youtube"

# --- Dark renderer ---
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

$iconRed  = Load-Icon $iconPath
$iconGrey = Load-Icon $iconGreyPath
if ($null -eq $iconRed)  { $iconRed  = [System.Drawing.SystemIcons]::Application }
if ($null -eq $iconGrey) { $iconGrey = $iconRed }

$script:localVersion    = $null
$script:notifiedVersion = $null
$script:releaseUrl      = "https://github.com/VNR121/ZapretRKN/releases/latest"

if (Test-Path $serviceBat) {
    $content = Get-Content $serviceBat -Raw
    if ($content -match 'LOCAL_VERSION=([\d\.]+)') { $script:localVersion = $matches[1] }
}

# --- Helpers ---
function Get-ZapretStatus {
    $p = Get-Process -Name winws -ErrorAction SilentlyContinue
    if ($p) { return "running" } else { return "stopped" }
}

function Get-CurrentStrategy {
    try {
        $v = (Get-ItemProperty -Path $regPath -Name $regValue -ErrorAction Stop).$regValue
        return $v
    } catch { return $null }
}

function Test-Autostart {
    $t = Get-ScheduledTask -TaskName "ZapretRKN" -ErrorAction SilentlyContinue
    return [bool]$t
}

function Hide-WinwsWindow {
    Get-Process -Name winws -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.MainWindowHandle -ne [IntPtr]::Zero) {
            [ZapretRKN_WinApi]::ShowWindow($_.MainWindowHandle, 0) | Out-Null
        }
    }
}

function Stop-Zapret {
    Get-Process -Name winws -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

function Start-Zapret {
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$($script:generalBat)`"" -WindowStyle Hidden
    Start-Sleep -Milliseconds 1500
    Hide-WinwsWindow
}

function Start-UpdateCheck {
    if (-not (Test-Path $checkerPath)) { return }
    Remove-Item $updateFile -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$checkerPath`"" `
        -WindowStyle Hidden
}

function Switch-Strategy {
    param([string]$Name)
    $src = Join-Path $stratDir $Name
    if (-not (Test-Path $src)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Файл стратегии не найден: $src",
            "ZapretRKN", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    Copy-Item -Path $src -Destination $generalBat -Force

    try {
        Set-ItemProperty -Path $regPath -Name $regValue -Value $Name -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Не удалось обновить реестр: нужны права администратора.`n`nФайл general.bat заменён, но название стратегии в меню не обновится.",
            "ZapretRKN", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }

    Stop-Zapret
    Start-Sleep -Milliseconds 300
    Start-Zapret
    return $true
}

# --- NotifyIcon ---
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon    = $iconRed
$notifyIcon.Text    = "ZapretRKN"
$notifyIcon.Visible = $true

# --- Menu ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Renderer = New-Object ZapretRKN_MenuRenderer
$menu.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$menu.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$menu.ShowImageMargin = $false
$menu.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$menu.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)

$itemHeader    = New-Object System.Windows.Forms.ToolStripMenuItem("ZapretRKN")
$itemHeader.Enabled = $false
$itemToggle    = New-Object System.Windows.Forms.ToolStripMenuItem("Остановить")
$itemRestart   = New-Object System.Windows.Forms.ToolStripMenuItem("Перезапустить")
$itemService   = New-Object System.Windows.Forms.ToolStripMenuItem("Менеджер службы")
$itemFolder    = New-Object System.Windows.Forms.ToolStripMenuItem("Папка ZapretRKN")
$itemAutostart = New-Object System.Windows.Forms.ToolStripMenuItem("Автозагрузка: выкл")

# Стратегия (родительский пункт с подменю)
$itemStrategy  = New-Object System.Windows.Forms.ToolStripMenuItem("Стратегия")
$itemStrategy.ForeColor = [System.Drawing.Color]::FromArgb(135, 135, 135)

# Заполняем подменю
$script:strategyItems = @{}
if (Test-Path $stratDir) {
    $strategies = @(Get-ChildItem -Path $stratDir -Filter "*.bat" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($strategies.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.ToolStripMenuItem("(нет стратегий)")
        $empty.Enabled = $false
        [void]$itemStrategy.DropDownItems.Add($empty)
    } else {
        foreach ($s in $strategies) {
            $sub = New-Object System.Windows.Forms.ToolStripMenuItem($s.Name)
            $sub.Tag = $s.Name
            $sub.add_Click({
                param($sender, $e)
                $name = $sender.Tag
                if (Switch-Strategy -Name $name) {
                    Update-TrayState
                }
            })
            [void]$itemStrategy.DropDownItems.Add($sub)
            $script:strategyItems[$s.Name] = $sub
        }
    }
} else {
    $empty = New-Object System.Windows.Forms.ToolStripMenuItem("(папка strategies не найдена)")
    $empty.Enabled = $false
    [void]$itemStrategy.DropDownItems.Add($empty)
}

$itemCheckUpd  = New-Object System.Windows.Forms.ToolStripMenuItem("Проверить обновления")
$itemAbout     = New-Object System.Windows.Forms.ToolStripMenuItem("О программе")
$itemExit      = New-Object System.Windows.Forms.ToolStripMenuItem("Выход")

$itemPadding = New-Object System.Windows.Forms.Padding(8, 2, 16, 2)
foreach ($it in @($itemToggle, $itemRestart, $itemService, $itemFolder, $itemAutostart, $itemStrategy, $itemCheckUpd, $itemAbout, $itemExit)) {
    $it.Padding = $itemPadding
}

[void]$menu.Items.Add($itemHeader)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemToggle)
[void]$menu.Items.Add($itemRestart)
[void]$menu.Items.Add($itemService)
[void]$menu.Items.Add($itemFolder)
[void]$menu.Items.Add($itemAutostart)
[void]$menu.Items.Add($itemStrategy)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemCheckUpd)
[void]$menu.Items.Add($itemAbout)
[void]$menu.Items.Add($itemExit)

$notifyIcon.ContextMenuStrip = $menu

# --- State updater ---
function Update-TrayState {
    $status = Get-ZapretStatus
    if ($status -eq "running") {
        $script:notifyIcon.Icon = $script:iconRed
        $script:notifyIcon.Text = "ZapretRKN - Работает"
        $script:itemToggle.Text = "Остановить"
        $script:itemHeader.Text = "ZapretRKN - Работает"
    } else {
        $script:notifyIcon.Icon = $script:iconGrey
        $script:notifyIcon.Text = "ZapretRKN - Остановлен"
        $script:itemToggle.Text = "Запустить"
        $script:itemHeader.Text = "ZapretRKN - Остановлен"
    }
    if (Test-Autostart) {
        $script:itemAutostart.Text = "Автозагрузка: ВКЛ"
    } else {
        $script:itemAutostart.Text = "Автозагрузка: выкл"
    }

    $cur = Get-CurrentStrategy
    if ($cur) {
        $script:itemStrategy.Text = "Стратегия: $cur"
    } else {
        $script:itemStrategy.Text = "Стратегия: (не определена)"
    }

    foreach ($name in $script:strategyItems.Keys) {
        if ($name -eq $cur) {
            $script:strategyItems[$name].Checked = $true
        } else {
            $script:strategyItems[$name].Checked = $false
        }
    }
}

# --- Events ---
$notifyIcon.add_BalloonTipClicked({
    Start-Process $script:releaseUrl
})

$notifyIcon.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $status = if ((Get-ZapretStatus) -eq "running") { "Работает" } else { "Остановлен" }
        $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
        $script:notifyIcon.BalloonTipText  = "$status"
        $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
        $script:notifyIcon.ShowBalloonTip(3000)
    }
})

$notifyIcon.add_DoubleClick({
    Start-Process -FilePath $script:serviceBat -WorkingDirectory $script:projectRoot
})

$itemToggle.add_Click({
    if ((Get-ZapretStatus) -eq "running") { Stop-Zapret } else { Start-Zapret }
    Update-TrayState
})

$itemRestart.add_Click({
    Stop-Zapret
    Start-Sleep -Milliseconds 200
    Start-Zapret
    Update-TrayState
})

$itemService.add_Click({
    Start-Process -FilePath $script:serviceBat -WorkingDirectory $script:projectRoot
})

$itemFolder.add_Click({
    Start-Process -FilePath "explorer.exe" -ArgumentList "`"$($script:projectRoot)`""
})

$itemAutostart.add_Click({
    if (Test-Autostart) {
        Unregister-ScheduledTask -TaskName "ZapretRKN" -Confirm:$false -ErrorAction SilentlyContinue
    } else {
        $action    = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ('"' + $script:vbsPath + '" "' + $script:generalBat + '"')
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName "ZapretRKN" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    }
    Update-TrayState
})

$itemCheckUpd.add_Click({
    $script:notifiedVersion = $null
    Start-UpdateCheck
    $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
    $script:notifyIcon.BalloonTipText  = "Проверка обновлений запущена..."
    $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
    $script:notifyIcon.ShowBalloonTip(2000)
})

$itemAbout.add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "ZapretRKN v1.2.0`nОбход DPI-блокировок`n`nФорк Flowseal/zapret-discord-youtube`nhttps://github.com/VNR121/ZapretRKN",
        "О программе",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
})

$itemExit.add_Click({
    Stop-Zapret
    $script:notifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

# --- Initial ---
Start-Sleep -Milliseconds 100
Hide-WinwsWindow
Start-Sleep -Milliseconds 400
Hide-WinwsWindow
Start-Sleep -Milliseconds 800
Hide-WinwsWindow
Update-TrayState

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
            $remote = $matches[1]
            $local  = $matches[2]
            if ($remote -ne $script:notifiedVersion) {
                $script:notifiedVersion = $remote
                $script:notifyIcon.BalloonTipTitle = "ZapretRKN - доступно обновление"
                $script:notifyIcon.BalloonTipText  = "Текущая: $local. Новая: $remote. Клик - открыть страницу."
                $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
                $script:notifyIcon.ShowBalloonTip(10000)
            }
        }
    }
})
$updTimer.Start()

$initTimer = New-Object System.Windows.Forms.Timer
$initTimer.Interval = 30000
$initTimer.add_Tick({
    $initTimer.Stop()
    $initTimer.Dispose()
    Start-UpdateCheck
})
$initTimer.Start()

$verTimer = New-Object System.Windows.Forms.Timer
$verTimer.Interval = 43200000
$verTimer.add_Tick({ Start-UpdateCheck })
$verTimer.Start()

[System.Windows.Forms.Application]::Run()

} catch {
    "FATAL: $($_.Exception.Message)" | Out-File -Append -Encoding UTF8 $logPath
    "Stack: $($_.ScriptStackTrace)" | Out-File -Append -Encoding UTF8 $logPath
    exit 1
}