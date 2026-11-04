# Magpie 配置公共模块
# 被 检查Magpie.ps1、启动Cursor多来源模型.ps1、部署.ps1 共同调用（dot-source）。
# 目标：不写死本机路径、用户名、随机 key ID，换一台机器也能直接用。
#
# 读取方式：. (Join-Path $PSScriptRoot 'lib\MagpieCommon.ps1')

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# ---------- 路径与可执行文件 ----------

function Find-MagpieExe {
    # 依次尝试：显式指定 > 环境变量 > 常见安装位置 > PATH
    param([string] $Explicit)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Explicit) { $candidates.Add($Explicit) }
    if ($env:MAGPIE_EXE) { $candidates.Add($env:MAGPIE_EXE) }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\magpie\magpie.exe'))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Magpie\magpie.exe'))
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Magpie\magpie.exe'))
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            # 指定了路径却没命中，说明覆盖没生效，明确提示而不是静默回退
            $given = if ($Explicit) { $Explicit } else { $env:MAGPIE_EXE }
            if ($given -and $c -ne $given) {
                Write-Warning ("指定的 magpie 路径不存在（$given），已回退到 $c")
            }
            return (Resolve-Path -LiteralPath $c).Path
        }
    }

    $onPath = Get-Command 'magpie.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $onPath = Get-Command 'magpie' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    throw ("找不到 magpie.exe。已尝试：`n  " + ($candidates -join "`n  ") +
           "`n请安装 Magpie，或设置环境变量 MAGPIE_EXE 指向它。")
}

function Find-CursorExe {
    param([string] $Explicit)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Explicit) { $candidates.Add($Explicit) }
    if ($env:CURSOR_EXE) { $candidates.Add($env:CURSOR_EXE) }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor Private Inference.exe'))
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Cursor\Cursor.exe'))
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

# ---------- 网关 ----------

function Get-GatewayConfig {
    param(
        [string] $BaseUrl,
        [string] $Key
    )
    if (-not $BaseUrl) { $BaseUrl = 'http://127.0.0.1:3425/v1' }
    if (-not $Key) { $Key = 'magpie-cursor-local' }
    return [pscustomobject]@{ BaseUrl = $BaseUrl.TrimEnd('/'); Key = $Key }
}

function Get-Utf8Json {
    # Windows PowerShell 5.1 的 Invoke-RestMethod 会把 UTF-8 JSON 当 ANSI 解码，
    # 中文 display_name 会变成乱码导致比对失败。这里显式按 UTF-8 读取。
    param([string] $Uri, [string] $Token)

    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $client = New-Object System.Net.Http.HttpClient
    try {
        $client.Timeout = [TimeSpan]::FromSeconds(20)
        if ($Token) {
            $client.DefaultRequestHeaders.Authorization =
                (New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token))
        }
        $body = $client.GetStringAsync($Uri).Result
        return ($body | ConvertFrom-Json)
    }
    finally { $client.Dispose() }
}

function Test-Gateway {
    # 返回 $true/$false 与原因，供守护、部署、检查共用
    param([object] $Config)

    try {
        $models = Get-Utf8Json -Uri ($Config.BaseUrl + '/models') -Token $Config.Key
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Reason = $_.Exception.GetBaseException().Message; Count = 0; Models = @() }
    }

    $data = @($models.data)
    if ($data.Count -eq 0) {
        return [pscustomobject]@{ Ok = $false; Reason = '网关返回了空的模型目录'; Count = 0; Models = @() }
    }
    return [pscustomobject]@{ Ok = $true; Reason = $null; Count = $data.Count; Models = $data }
}

# ---------- gateway key ----------

function Resolve-GatewayKeyId {
    # `magpie gateway-key list` 只接受 ID，不支持按名字，且没有 --json。
    # 从纯文本列表里按名称匹配，避免把本机的随机 ID 写死进脚本。
    param(
        [string] $Magpie,
        [string] $Name = 'Cursor Private Inference'
    )

    if ($env:MAGPIE_GATEWAY_KEY_ID) { return $env:MAGPIE_GATEWAY_KEY_ID }

    $listing = (& $Magpie gateway-key list 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "无法读取 gateway-key 列表：$listing"
    }

    # 每行形如：<id>  <name>  <state>  <key>  <limit>  <models>
    $pattern = '(?m)^\s*([0-9a-f]{16,})\s+' + [regex]::Escape($Name) + '\b'
    $m = [regex]::Match($listing, $pattern, 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }

    # 退而求其次：任意条目的 ID
    $any = [regex]::Match($listing, '(?m)^\s*([0-9a-f]{16,})\s+\S')
    if ($any.Success) { return $any.Groups[1].Value }

    throw "Magpie 里没有名为 '$Name' 的 gateway key。请在 Magpie 中创建它，或设置环境变量 MAGPIE_GATEWAY_KEY_ID。"
}

# ---------- 输出 ----------

function Write-Section {
    param([string] $Title)
    Write-Host ''
    Write-Host ('== ' + $Title + ' ==')
}
