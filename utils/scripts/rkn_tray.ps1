# rkn_tray.ps1 - ZapretRKN tray icon

$logPath = Join-Path $env:TEMP "zapret_tray.log"
"===== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Out-File -Append -Encoding UTF8 $logPath

try {

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
"Assemblies loaded" | Out-File -Append -Encoding UTF8 $logPath

# --- Single instance (Local, без Global\) ---
$mutex = New-Object System.Threading.Mutex($false, "Local\ZapretRKNTray_v1")
$acquired = $false
try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
if (-not $acquired) {
    "Mutex already held, exiting" | Out-File -Append -Encoding UTF8 $logPath
    exit
}
"Mutex acquired" | Out-File -Append -Encoding UTF8 $logPath

# --- Paths ---
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$utilsDir    = Split-Path -Parent $scriptDir
$projectRoot = Split-Path -Parent $utilsDir
$iconPath    = Join-Path $scriptDir "icon.ico"
$vbsPath     = Join-Path $scriptDir "run_hidden.vbs"
$serviceBat  = Join-Path $projectRoot "service.bat"
$generalBat  = Join-Path $projectRoot "general.bat"
"ProjectRoot: $projectRoot" | Out-File -Append -Encoding UTF8 $logPath

# --- Dark renderer + custom menu renderer ---
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
            {
                e.Graphics.FillRectangle(b, r);
            }
            using (SolidBrush accent = new SolidBrush(Color.FromArgb(80, 140, 210)))
            {
                e.Graphics.FillRectangle(accent, 0, 0, 3, e.Item.Height);
            }
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        if (e.Item.Enabled)
        {
            e.TextColor = Color.FromArgb(235, 235, 235);
        }
        else
        {
            e.TextColor = Color.FromArgb(130, 130, 130);
        }
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
    "Renderer compiled" | Out-File -Append -Encoding UTF8 $logPath
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

# --- Icon loading with PNG-framed fallback ---
$icon = $null
if (Test-Path $iconPath) {
    try {
        $icon = New-Object System.Drawing.Icon($iconPath)
        "Icon loaded directly" | Out-File -Append -Encoding UTF8 $logPath
    } catch {
        "Direct icon load failed: $($_.Exception.Message)" | Out-File -Append -Encoding UTF8 $logPath
        try {
            $bmp   = New-Object System.Drawing.Bitmap($iconPath)
            $hicon = $bmp.GetHicon()
            $icon  = [System.Drawing.Icon]::FromHandle($hicon)
            "Icon loaded via Bitmap->Hicon fallback" | Out-File -Append -Encoding UTF8 $logPath
        } catch {
            "Bitmap fallback failed: $($_.Exception.Message)" | Out-File -Append -Encoding UTF8 $logPath
            $icon = $null
        }
    }
}
if ($null -eq $icon) {
    $icon = [System.Drawing.SystemIcons]::Application
    "Using system fallback icon" | Out-File -Append -Encoding UTF8 $logPath
}

# --- Helpers ---
function Get-ZapretStatus {
    $p = Get-Process -Name winws -ErrorAction SilentlyContinue
    if ($p) { return "running" } else { return "stopped" }
}

function Test-Autostart {
    $t = Get-ScheduledTask -TaskName "ZapretRKN" -ErrorAction SilentlyContinue
    return [bool]$t
}

function Hide-WinwsWindow {
    $procs = Get-Process -Name winws -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $hwnd = $p.MainWindowHandle
        if ($hwnd -ne [IntPtr]::Zero) {
            [ZapretRKN_WinApi]::ShowWindow($hwnd, 0) | Out-Null
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

# --- NotifyIcon ---
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon    = $icon
$notifyIcon.Text    = "ZapretRKN"
$notifyIcon.Visible = $true
"NotifyIcon visible" | Out-File -Append -Encoding UTF8 $logPath

# --- Menu ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Renderer = New-Object ZapretRKN_MenuRenderer
$menu.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$menu.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$menu.ShowImageMargin = $false
$menu.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$menu.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)

$itemHeader    = New-Object System.Windows.Forms.ToolStripMenuItem("ZapretRKN")
$itemHeader.Enabled = $false

$itemToggle    = New-Object System.Windows.Forms.ToolStripMenuItem("Остановить")
$itemRestart   = New-Object System.Windows.Forms.ToolStripMenuItem("Перезапустить")
$itemService   = New-Object System.Windows.Forms.ToolStripMenuItem("Менеджер службы")
$itemFolder    = New-Object System.Windows.Forms.ToolStripMenuItem("Открыть папку ZapretRKN")
$itemAutostart = New-Object System.Windows.Forms.ToolStripMenuItem("Автозагрузка: выкл")
$itemAbout     = New-Object System.Windows.Forms.ToolStripMenuItem("О программе")
$itemExit      = New-Object System.Windows.Forms.ToolStripMenuItem("Выход")

$itemPadding = New-Object System.Windows.Forms.Padding(10, 3, 20, 3)
foreach ($it in @($itemToggle, $itemRestart, $itemService, $itemFolder, $itemAutostart, $itemAbout, $itemExit)) {
    $it.Padding = $itemPadding
}

[void]$menu.Items.Add($itemHeader)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemToggle)
[void]$menu.Items.Add($itemRestart)
[void]$menu.Items.Add($itemService)
[void]$menu.Items.Add($itemFolder)
[void]$menu.Items.Add($itemAutostart)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemAbout)
[void]$menu.Items.Add($itemExit)

$notifyIcon.ContextMenuStrip = $menu

# --- State updater ---
function Update-TrayState {
    $status = Get-ZapretStatus
    if ($status -eq "running") {
        $script:notifyIcon.Text = "ZapretRKN - работает"
        $script:itemToggle.Text = "Остановить"
        $script:itemHeader.Text = "ZapretRKN - работает"
    } else {
        $script:notifyIcon.Text = "ZapretRKN - остановлен"
        $script:itemToggle.Text = "Запустить"
        $script:itemHeader.Text = "ZapretRKN - остановлен"
    }
    if (Test-Autostart) {
        $script:itemAutostart.Text = "Автозагрузка: ВКЛ"
    } else {
        $script:itemAutostart.Text = "Автозагрузка: выкл"
    }
}

# --- Events ---
$notifyIcon.add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $status = if ((Get-ZapretStatus) -eq "running") { "работает" } else { "остановлен" }
        $script:notifyIcon.BalloonTipTitle = "ZapretRKN"
        $script:notifyIcon.BalloonTipText  = "Статус: $status"
        $script:notifyIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
        $script:notifyIcon.ShowBalloonTip(3000)
    }
})

$notifyIcon.add_DoubleClick({
    Start-Process -FilePath $script:serviceBat -WorkingDirectory $script:projectRoot
})

$itemToggle.add_Click({
    if ((Get-ZapretStatus) -eq "running") {
        Stop-Zapret
    } else {
        Start-Zapret
    }
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

$itemAbout.add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "ZapretRKN v1.1.1`nОбход DPI-блокировок`n`nФорк Flowseal/zapret-discord-youtube`nhttps://github.com/VNR121/ZapretRKN",
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

# --- Initial hide + state ---
Start-Sleep -Milliseconds 100
Hide-WinwsWindow
Start-Sleep -Milliseconds 400
Hide-WinwsWindow
Start-Sleep -Milliseconds 800
Hide-WinwsWindow
Update-TrayState

# --- Timer ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({ Update-TrayState })
$timer.Start()

"Entering message loop" | Out-File -Append -Encoding UTF8 $logPath
[System.Windows.Forms.Application]::Run()

} catch {
    "FATAL: $($_.Exception.Message)" | Out-File -Append -Encoding UTF8 $logPath
    "Stack: $($_.ScriptStackTrace)" | Out-File -Append -Encoding UTF8 $logPath
    exit 1
}