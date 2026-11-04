# 一键部署：在当前机器上把项目跑起来。
# 用法：
#   powershell -ExecutionPolicy Bypass -File 部署.ps1
#   powershell -ExecutionPolicy Bypass -File 部署.ps1 -Check     # 只自检，不改任何设置
#   powershell -ExecutionPolicy Bypass -File 部署.ps1 -Uninstall # 撤销自启与快捷方式
#
# 做四件事：确认依赖 → 编译守护 → 校验网关 → 注册登录自启 + 桌面快捷方式。
# 不写死任何本机路径或账号，全部在运行时探测。
param(
    [switch] $Check,
    [switch] $Uninstall,
    [switch] $NoAutostart,
    [string] $CursorExe
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\MagpieCommon.ps1')

$root = $PSScriptRoot
$keeperSource = Join-Path $root 'src\MagpieGatewayKeeper.cs'
$keeperExe = Join-Path $root 'Magpie网关守护.exe'
$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'MagpieGatewayKeeper'

function Find-Csc {
    $found = Get-Command 'csc.exe' -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    $candidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return $null
}

function Get-DesktopPath {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) {
        $desktop = Join-Path $env:USERPROFILE 'Desktop'
    }
    return $desktop
}

# ---------- 卸载 ----------
if ($Uninstall) {
    Write-Section '撤销部署'
    if ((Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue)) {
        Remove-ItemProperty -Path $runKeyPath -Name $runValueName -Force
        Write-Host '已移除登录自启。'
    } else { Write-Host '没有登录自启项。' }

    $lnk = Join-Path (Get-DesktopPath) 'Magpie网关守护.lnk'
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host '已移除桌面快捷方式。' }

    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $keeperExe } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host ('已停止守护进程 ' + $_.ProcessId)
    }
    Write-Host '完成。Magpie 对应的自启项未修改。'
    exit 0
}

$problems = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

# ---------- 1. 依赖 ----------
Write-Section '1/4 检查依赖'

$magpie = $null
try { $magpie = Find-MagpieExe } catch { $problems.Add($_.Exception.Message) }
if ($magpie) {
    Write-Host ('Magpie      : ' + $magpie)
    try {
        $ver = (& $magpie --version 2>&1 | Out-String).Trim()
        if ($ver) { Write-Host ('版本        : ' + $ver) }
    } catch { }
} else {
    Write-Host 'Magpie      : 未找到'
}

$cursor = Find-CursorExe -Explicit $CursorExe
if ($cursor) { Write-Host ('Cursor      : ' + $cursor) }
else { Write-Host 'Cursor      : 未找到（不影响网关守护，仅提示）'; $notes.Add('未找到 Cursor Private Inference，需要时用 -CursorExe 指定。') }

$csc = Find-Csc
if ($csc) { Write-Host ('C# 编译器   : ' + $csc) } else { $problems.Add('找不到 csc.exe（.NET Framework 4.x），无法编译守护程序。') }

if (-not (Test-Path -LiteralPath $keeperSource)) { $problems.Add('缺少守护源码：' + $keeperSource) }

# ---------- 2. 网关 ----------
Write-Section '2/4 检查网关'

$cfg = Get-GatewayConfig
Write-Host ('地址        : ' + $cfg.BaseUrl)

$keyId = $null
if ($magpie) {
    try {
        $keyId = Resolve-GatewayKeyId -Magpie $magpie
        Write-Host ('gateway key : ' + $keyId)
    } catch {
        $problems.Add($_.Exception.Message)
    }
}

$gatewayOk = $false
if ($Check -or $magpie) {
    $probe = Test-Gateway -Config $cfg
    $gatewayOk = $probe.Ok
    if ($probe.Ok) {
        Write-Host ('目录        : ' + $probe.Count + ' 个模型，网关正常')
        $hasPool = @($probe.Models | Where-Object { $_.id -eq 'group/deepseek-flash-pool' }).Count -gt 0
        if ($hasPool) { Write-Host '混池        : DeepSeek Flash Pool 已提供' }
        else { $notes.Add('网关里没有 group/deepseek-flash-pool，混池需要先在 Magpie 中创建。') }
    } else {
        Write-Host ('目录        : 不可用 — ' + $probe.Reason)
        $notes.Add('网关当前不可用；守护程序启动后会尝试拉起 Magpie。')
    }
}

# ---------- 3. 编译守护 ----------
Write-Section '3/4 编译守护程序'

$compiled = $false
if (-not $Check -and $csc -and (Test-Path -LiteralPath $keeperSource)) {
    $running = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $keeperExe })
    foreach ($r in $running) { Stop-Process -Id $r.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($running.Count -gt 0) { Write-Host ('已停止旧的守护进程 ' + ($running.Count) + ' 个') }

    $iconArg = @()
    if ($magpie) {
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            $ico = Join-Path $env:TEMP ('magpie-' + [guid]::NewGuid().ToString('N') + '.ico')
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($magpie)
            if ($icon) {
                $stream = [IO.File]::Create($ico)
                $icon.Save($stream)
                $stream.Close()
                $iconArg = @("/win32icon:$ico")
            }
        } catch { }
    }

    if (Test-Path -LiteralPath $keeperExe) { Remove-Item -LiteralPath $keeperExe -Force }
    $compileArgs = @(
        '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
        "/out:$keeperExe"
    ) + $iconArg + @(
        '/reference:System.dll', '/reference:System.Core.dll',
        '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
        $keeperSource,
        (Join-Path $root 'src\PoolScheduler.cs')
    )
    $compileOut = (& $csc @compileArgs 2>&1 | Out-String)
    $compileArgs = $null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $keeperExe)) {
        Write-Host ('已生成      : ' + (Split-Path $keeperExe -Leaf) + ' (' + (Get-Item $keeperExe).Length + ' 字节)')
        $compiled = $true
    } else {
        $problems.Add('编译失败：' + (($compileOut -replace '\s+', ' ').Trim()))
    }
    if ($ico -and (Test-Path -LiteralPath $ico)) { Remove-Item $ico -Force -ErrorAction SilentlyContinue }
} elseif ($Check) {
    Write-Host '跳过（-Check 模式）。'
} else {
    if (Test-Path -LiteralPath $keeperExe) { Write-Host '沿用已有的可执行文件。'; $compiled = $true }
}

# ---------- 4. 自启与快捷方式 ----------
Write-Section '4/4 注册启动项'

if ($Check) {
    Write-Host '跳过（-Check 模式）。'
} elseif (-not $NoAutostart) {
    if ($compiled) {
        Set-ItemProperty -Path $runKeyPath -Name $runValueName -Value ('"' + $keeperExe + '"')
        Write-Host ('登录自启    : 已注册 ' + $keeperExe)

        $desktop = Get-DesktopPath
        $shell = New-Object -ComObject WScript.Shell
        $lnk = Join-Path $desktop 'Magpie网关守护.lnk'
        $shortcut = $shell.CreateShortcut($lnk)
        $shortcut.TargetPath = $keeperExe
        $shortcut.WorkingDirectory = $root
        $shortcut.IconLocation = "$keeperExe,0"
        $shortcut.Description = '常驻托盘，保证 Magpie 网关 127.0.0.1:3425 一直可用'
        $shortcut.Save()
        Write-Host ('桌面快捷    : ' + $lnk)

        Start-Process -FilePath $keeperExe
        Start-Sleep -Seconds 2
        $alive = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $keeperExe }).Count
        Write-Host ('守护已启动  : ' + $alive + ' 个进程')
    } else {
        $notes.Add('守护程序未就绪，跳过自启注册。')
    }
} else {
    Write-Host '跳过（-NoAutostart）。'
}

# ---------- 摘要 ----------
Write-Section '结果'
if ($notes.Count -gt 0) {
    Write-Host '提示：'
    foreach ($n in $notes) { Write-Host ('  - ' + $n) }
}
if ($problems.Count -gt 0) {
    Write-Host '存在问题：'
    foreach ($p in $problems) { Write-Host ('  - ' + $p) }
    exit 1
}

Write-Host '部署完成。'
Write-Host ''
Write-Host 'Cursor 侧只需配置一次：'
Write-Host '  Settings → Models → Gateway → Configure gateway'
Write-Host ('  Base URL : ' + $cfg.BaseUrl)
Write-Host ('  API Key  : ' + $cfg.Key)
Write-Host '  然后在 Settings → Models 点 Refresh model，启用 DeepSeek Flash Pool。'
exit 0
