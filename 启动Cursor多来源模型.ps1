# Configure the Cursor Private Inference catalog and start Cursor.
# WorkBuddy AI expanded models may consume credits; other enabled sources may consume subscription credits or API balance.
#
# -DryRun  只打印将要执行的改动并做校验，不写 Magpie 配置、不启动 Cursor。
param([switch] $DryRun)

$ErrorActionPreference = 'Stop'

# 统一出口：DryRun 时只打印，不执行写操作。
function Invoke-MagpieWrite {
    param([string] $Description, [scriptblock] $Action)
    if ($DryRun) {
        Write-Host ('[DryRun] 将执行：' + $Description)
        return
    }
    & $Action
}
. (Join-Path $PSScriptRoot 'lib\MagpieCommon.ps1')

# 路径与 gateway key 全部运行时探测，换机器无需改脚本。
$magpie = Find-MagpieExe
$cursor = Find-CursorExe
$gatewayKeyId = Resolve-GatewayKeyId -Magpie $magpie
$gatewayUrl = (Get-GatewayConfig).BaseUrl
$cursorKey = (Get-GatewayConfig).Key

. (Join-Path $PSScriptRoot 'lib\ModelLabels.ps1')
$modelLabels = Get-ModelLabels
$allowedModelIds = @($modelLabels.Keys)
$visibleProviders = Get-VisibleProviders

if (-not $magpie) { throw 'Magpie not found' }
if (-not $cursor) { throw 'Cursor Private Inference not found; set CURSOR_EXE.' }


# Expand WorkBuddy models, including DeepSeek; non-free models may consume credits.
# 先读当前状态：已是 off 就不动，避免 PowerShell 传 JSON 时的引号转义问题。
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$wbOptions = (& $magpie plugin options workbuddy 2>$null | Out-String)
$ErrorActionPreference = $prevEap
if ($wbOptions -match 'free_only\s+workbuddy\s+off') {
    Write-Host 'WorkBuddy free_only 已关闭。'
} else {
    Invoke-MagpieWrite 'plugin options workbuddy free_only=false' { & $magpie plugin options workbuddy '{\"free_only\":false}' }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning '无法自动关闭 WorkBuddy free_only，请在 Magpie 界面手动关闭。'
    }
}

Invoke-MagpieWrite 'group auto skip trae-cn raccoon zcode minimax-code loomy' { & $magpie group auto skip trae-cn raccoon zcode minimax-code loomy }
if ($LASTEXITCODE -ne 0) { throw 'Could not isolate Trae routing groups.' }

# DeepSeek's official API currently has two models; include the available V4 Pro model too.
Invoke-MagpieWrite 'provider models deepseek +deepseek-v4-pro' { & $magpie provider models deepseek +deepseek-v4-pro }
if ($LASTEXITCODE -ne 0) { throw 'Could not expose DeepSeek V4 Pro.' }

# 混池已改由 Magpie网关守护.exe 在 127.0.0.1:3426 上自建（pool/*），
# 不再需要在 Magpie 里建 group；旧的 group/deepseek-flash-pool 已废弃。

# pool/* 是本项目守护程序自建的，不是 Magpie 的上游模型：
# 它们不进 Magpie 的标签/白名单/visible，只在 3426 上服务 Cursor。
$upstreamIds = @($allowedModelIds | Where-Object { $_ -notlike 'pool/*' })

foreach ($modelId in $upstreamIds) {
    Invoke-MagpieWrite ('model name ' + $modelId) { & $magpie model name $modelId $modelLabels[$modelId] }
    if ($LASTEXITCODE -ne 0) { throw "Could not label model $modelId." }
}

# Keep Cursor limited to the connected providers and this exact upstream allowlist.
Invoke-MagpieWrite 'visible cursor-local' { & $magpie visible cursor-local @visibleProviders }
if ($LASTEXITCODE -ne 0) { throw 'Could not set Cursor visible providers.' }

# 注意：gateway-key models 是「整份替换」而不是追加。
# 这里传完整列表是安全的；要单独加几个模型时，必须先取出原列表再合并，否则会把白名单清空。
Invoke-MagpieWrite 'gateway-key models' { & $magpie gateway-key models $gatewayKeyId @upstreamIds }
if ($LASTEXITCODE -ne 0) { throw 'Could not set the Cursor gateway-key model allowlist.' }

# 校验打 Magpie 本体（3425）。pool/* 只在 3426 上，由 检查Magpie.ps1 单独验证。
$env:CURSOR_LOCAL_AGENT_BASE_URL = $gatewayUrl
$env:CURSOR_LOCAL_AGENT_API_KEY = $cursorKey
try {
    $catalog = Get-Utf8Json -Uri "$gatewayUrl/models" -Token $cursorKey
} catch {
    throw 'Magpie gateway is unavailable or its Cursor key is missing. Start Magpie and retry.'
}

$knownUnavailable = Get-KnownUnavailableModels
$modelData = @($catalog.data)
$actualModelIds = @($modelData | ForEach-Object { $_.id })
$unexpected = @($actualModelIds | Where-Object {
    $_ -notin $upstreamIds -and
    $_ -notlike 'group/*' -and
    $_ -notlike 'auto/*' -and
    -not $knownUnavailable.ContainsKey($_)
})
$missing = @($upstreamIds | Where-Object { $_ -notin $actualModelIds })
if ($unexpected.Count -gt 0) {
    throw "Unexpected Cursor catalog entries: $($unexpected -join ', ')"
}
if ($missing.Count -gt 0) {
    Write-Host ('提示：{0} 个上游模型当前不在网关目录里（额度用尽或上游下线）：{1}' -f $missing.Count, ($missing -join ', '))
}

Write-Host 'Verified Cursor model choices:'
$modelData | ForEach-Object { Write-Host ("  {0} — {1}" -f $_.id, $_.display_name) }
Write-Host ('自建池 {0} 个由 Magpie网关守护.exe 在 3426 上提供：{1}' -f
    (@($allowedModelIds | Where-Object { $_ -like 'pool/*' }).Count),
    (($allowedModelIds | Where-Object { $_ -like 'pool/*' }) -join ', '))

if ($DryRun) {
    Write-Host ''
    Write-Host '[DryRun] 校验通过；未修改 Magpie 配置，也未启动 Cursor。'
    exit 0
}

if (Get-Process -Name 'Cursor Private Inference' -ErrorAction SilentlyContinue) {
    throw 'Cursor Private Inference is already open. Quit it completely, then rerun this script so it refreshes the model catalog.'
}

Start-Process -FilePath $cursor -ArgumentList @('--new-window', ('"' + $PSScriptRoot + '"'))











