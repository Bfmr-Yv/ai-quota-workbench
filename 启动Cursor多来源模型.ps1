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

$modelLabels = [ordered]@{
    'group/deepseek-flash-pool' = 'DeepSeek Flash Pool'
    'loomy/DeepSeek-V4.1-Flash' = 'DeepSeek-V4.1-Flash · Loomy积分 · 单价未知'
    'loomy/deepseek-v4-flash-0731' = 'deepseek-v4-flash-0731 · Loomy积分 · 单价未知'
    'loomy/MiniMax-M3' = 'MiniMax-M3 · Loomy积分 · 单价未知'
    'loomy/Kimi-k2.6' = 'Kimi-k2.6 · Loomy积分 · 单价未知'
    'loomy/qwen-3.8-max' = 'qwen-3.8-max · Loomy积分 · 单价未知'
    'loomy/GLM-5.3-Flash' = 'GLM-5.3-Flash · Loomy积分 · 单价未知'
    'loomy/qwen3.8-flash' = 'qwen3.8-flash · Loomy积分 · 单价未知'
    'loomy/spark-x' = 'spark-x · Loomy积分 · 单价未知'
    'loomy/mimo-v2.5' = 'mimo-v2.5 · Loomy积分 · 单价未知'
    'loomy/spark-x2.6' = 'spark-x2.6 · Loomy积分 · 单价未知'
    'zcode/GLM-5.3-Flash' = 'GLM 5.3 Flash · ZCode Start Plan'
    'zcode/GLM-5.3' = 'GLM 5.3 · ZCode Start Plan'
    'zcode/GLM-5.3-Trial' = 'GLM 5.3 Trial · ZCode活动额度'
    'zcode/GLM-5.3-Flash-Trial' = 'GLM 5.3 Flash Trial · ZCode活动额度'
    'minimax-code/MiniMax-M3.1-Flash' = 'MiniMax M3.1 Flash · MiniMax积分'
    'minimax-code/MiniMax-M3' = 'MiniMax M3 · MiniMax积分'
    'raccoon/raccoon-090dd3' = 'Raccoon-Work · 小浣熊积分 · 单价未知'
    'raccoon/raccoon-19b265' = 'Raccoon-Work-260817-A · 小浣熊积分 · 单价未知'
    'raccoon/raccoon-405a1c' = 'Raccoon-Work-260817-B · 小浣熊积分 · 单价未知'
    'raccoon/sn-sensenova-6-8-flash' = 'SenseNova-6.8-Flash · 小浣熊积分 · 单价未知'
    'raccoon/sn-sensenova-6-8-flash-lite' = 'SenseNova-6.8-Flash-Lite · 小浣熊积分 · 单价未知'
    'raccoon/sn-glm-5-3' = 'GLM-5-3 · 小浣熊积分 · 单价未知'
    'raccoon/sn-kimi-k3' = 'Kimi-K3 · 小浣熊积分 · 单价未知'
    'raccoon/sn-glm-5-3-flash' = 'GLM-5-3-Flash · 小浣熊积分 · 单价未知'
    'raccoon/sn-deepseek-v4-1-flash-1017' = 'DeepSeek-V4.1-Flash-1017 · 小浣熊积分 · 单价未知'
    'raccoon/raccoon-chat-ml-5-5' = 'Raccoon Chat (默认) · 小浣熊积分 · 单价未知'
    'trae-cn/Doubao-Seed-2.1-Turbo' = 'Doubao-Seed-2.1-Turbo · Trae积分 · 单价未知'
    'trae-cn/Doubao-Seed-2.1-Pro' = 'Doubao-Seed-2.1-Pro · Trae积分 · 单价未知'
    'trae-cn/Doubao-Seed-Evolving' = 'Doubao-Seed-Evolving · Trae积分 · 单价未知'
    'trae-cn/Doubao-Seed-Code' = 'Doubao-Seed-Code · Trae积分 · 单价未知'
    'trae-cn/glm-5.3-flash' = 'glm-5.3-flash · Trae积分 · 单价未知'
    'trae-cn/glm-5.3-flashx' = 'glm-5.3-flashx · Trae积分 · 单价未知'
    'trae-cn/glm-5.3' = 'glm-5.3 · Trae积分 · 单价未知'
    'trae-cn/glm-5.2' = 'glm-5.2 · Trae积分 · 单价未知'
    'trae-cn/DeepSeek-V4-Flash' = 'DeepSeek-V4-Flash · Trae积分 · 单价未知'
    'trae-cn/deepseek-v4.1-flash' = 'deepseek-v4.1-flash · Trae积分 · 单价未知'
    'trae-cn/DeepSeek-V4-Pro' = 'DeepSeek-V4-Pro · Trae积分 · 单价未知'
    'trae-cn/kimi-k2.7-code' = 'kimi-k2.7-code · Trae积分 · 单价未知'
    'workbuddy-ai/hy3' = 'Hy3 · 免费（¥0）'
    'workbuddy-ai/deepseek-v4.1-flash-sg' = 'DeepSeek V4.1 Flash · WB额度 · 单价未知'
    'workbuddy-ai/grok-4.7' = 'Grok 4.7 · WB额度 · 单价未知'
    'workbuddy-ai/gemini-3.8-flash' = 'Gemini 3.8 Flash · WB额度 · 单价未知'
    'workbuddy-ai/glm-5.3' = 'GLM 5.3 · WB额度 · 单价未知'
    'workbuddy-ai/glm-5.3-flash' = 'GLM 5.3 Flash · WB额度 · 单价未知'
    'workbuddy-ai/kimi-k3.1-pro' = 'Kimi K3.1 Pro · WB额度 · 单价未知'
    'workbuddy-ai/kimi-k3.1-pro-highspeed' = 'Kimi K3.1 Pro Highspeed · WB额度 · 单价未知'
    'workbuddy-ai/kimi-k3' = 'Kimi K3 · WB额度 · 单价未知'
    'workbuddy-ai/minimax-m3.1-flash' = 'MiniMax M3.1 Flash · WB额度 · 单价未知'
    'kimi-work/k3d1-agent' = 'K3.1 Pro · 月度会员共享额度 · 价格未知'
    'kimi-work/k2d8-preview' = 'K2.8 Preview · 月度会员共享额度 · 价格未知'
    'kimi-work/k3-agent' = 'K3 · 月度会员共享额度 · 价格未知'
    'xiaomi/mimo-v2.6-pro' = 'MiMo V2.6 Pro · TP 2.5/300/600 cr/t · API ¥3/6/M'
    'xiaomi/mimo-v2.6-flash' = 'MiMo V2.6 Flash · TP 2/100/200 cr/t · API ¥1/2/M'
    'deepseek/deepseek-flash' = 'V4.1 Flash · 官方 API $0.15/$0.60/M off-peak'
    'deepseek/deepseek-v4-pro' = 'V4 Pro · 官方 API $0.66/$1.98/M off-peak'
    'trae-cn/glm-5.3-max' = 'GLM-5.3 Max · Trae积分 · 单价未知'
    'trae-cn/glm-5.3-flash-max' = 'GLM-5.3-Flash Max · Trae积分 · 单价未知'
    'trae-cn/glm-5.3-flashx-max' = 'GLM-5.3-FlashX Max · Trae积分 · 单价未知'
    'trae-cn/glm-5.2-max' = 'GLM-5.2 Max · Trae积分 · 单价未知'
    'trae-cn/glm-5.2_advisor_doubao' = 'GLM 5.2 · Trae积分 · 单价未知'
    'trae-cn/glm-5.1' = 'GLM 5.1 · Trae积分 · 单价未知'
    'trae-cn/glm-5' = 'GLM 5 · Trae积分 · 单价未知'
    'trae-cn/glm-4.7' = 'GLM 4.7 · Trae积分 · 单价未知'
    'trae-cn/glm-4.6' = 'GLM 4.6 · Trae积分 · 单价未知'
    'trae-cn/DeepSeek-V4-Flash-max' = 'DeepSeek-V4-Flash Max · Trae积分 · 单价未知'
    'trae-cn/DeepSeek-V4-Pro-max' = 'DeepSeek-V4-Pro Max · Trae积分 · 单价未知'
    'trae-cn/Doubao-Seed-2.1-Pro-max' = 'Seed 2.1 Pro Max · Trae积分 · 单价未知'
    'trae-cn/Doubao-Seed-Evolving-max' = 'Seed Evolving Max · Trae积分 · 单价未知'
    'workbuddy-ai/hy4free' = 'Hy4 · WB额度 · 单价未知'
    'workbuddy-ai/hy4std' = 'Hy4 Std · WB额度 · 单价未知'
    'kimi-work/k3d1-agent-fast' = 'K3.1 Pro Fast · 月度会员共享额度 · 价格未知'
    'loomy/auto' = 'Loomy Auto · 自动均衡 · 积分'
}
$allowedModelIds = @($modelLabels.Keys)
$visibleProviders = @('workbuddy-ai', 'kimi-work', 'xiaomi', 'deepseek', 'trae-cn', 'raccoon', 'zcode', 'minimax-code', 'loomy')

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

Invoke-MagpieWrite 'group add DeepSeek Flash Pool (8 models, order/turn)' { & $magpie group add 'DeepSeek Flash Pool' 'models=workbuddy-ai/deepseek-v4.1-flash-sg,loomy/DeepSeek-V4.1-Flash,trae-cn/deepseek-v4.1-flash,raccoon/sn-deepseek-v4-1-flash-1017,loomy/mimo-v2.5,xiaomi/mimo-v2.6-flash,xiaomi/mimo-v2.6-pro,deepseek/deepseek-flash' routing=order stays=turn }
if ($LASTEXITCODE -ne 0) { throw 'Could not configure DeepSeek Flash pool.' }

foreach ($modelId in $allowedModelIds | Where-Object { $_ -notlike 'group/*' }) {
    Invoke-MagpieWrite ('model name ' + $modelId) { & $magpie model name $modelId $modelLabels[$modelId] }
    if ($LASTEXITCODE -ne 0) { throw "Could not label model $modelId." }
}

# Keep Cursor limited to the four connected providers and this exact model allowlist.
Invoke-MagpieWrite 'visible cursor-local' { & $magpie visible cursor-local @visibleProviders }
if ($LASTEXITCODE -ne 0) { throw 'Could not set Cursor visible providers.' }
Invoke-MagpieWrite 'gateway-key models' { & $magpie gateway-key models $gatewayKeyId @allowedModelIds }
if ($LASTEXITCODE -ne 0) { throw 'Could not set the Cursor gateway-key model allowlist.' }

$env:CURSOR_LOCAL_AGENT_BASE_URL = $gatewayUrl
$env:CURSOR_LOCAL_AGENT_API_KEY = $cursorKey
try {
    $catalog = Get-Utf8Json -Uri "$gatewayUrl/models" -Token $cursorKey
} catch {
    throw 'Magpie gateway is unavailable or its Cursor key is missing. Start Magpie and retry.'
}

$modelData = @($catalog.data)
$actualModelIds = @($modelData | ForEach-Object { $_.id })
$unexpected = @($actualModelIds | Where-Object { $_ -notin $allowedModelIds })
$missing = @($allowedModelIds | Where-Object { $_ -notin $actualModelIds })
$badLabels = @($modelData | Where-Object { $_.display_name -ne $modelLabels[$_.id] })
if ($actualModelIds.Count -ne $allowedModelIds.Count -or $unexpected.Count -gt 0 -or $missing.Count -gt 0 -or $badLabels.Count -gt 0) {
    throw "Unexpected Cursor catalog. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', '); labels to fix: $(($badLabels | ForEach-Object { $_.id }) -join ', ')"
}

Write-Host 'Verified Cursor model choices:'
$modelData | ForEach-Object { Write-Host ("  {0} — {1}" -f $_.id, $_.display_name) }
Write-Host 'Codex/GPT models are absent from the Cursor gateway key.'

if ($DryRun) {
    Write-Host ''
    Write-Host '[DryRun] 校验通过；未修改 Magpie 配置，也未启动 Cursor。'
    exit 0
}

if (Get-Process -Name 'Cursor Private Inference' -ErrorAction SilentlyContinue) {
    throw 'Cursor Private Inference is already open. Quit it completely, then rerun this script so it refreshes the model catalog.'
}

Start-Process -FilePath $cursor -ArgumentList @('--new-window', ('"' + $PSScriptRoot + '"'))











