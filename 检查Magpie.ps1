# 只读自检：模型目录、白名单、标签、各渠道额度。
# 用法：powershell -ExecutionPolicy Bypass -File 检查Magpie.ps1 [-BaseUrl ...] [-Key ...]
# 不修改任何 Magpie 配置，换机器可直接运行。
param(
    [string] $BaseUrl,
    [string] $Key
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\MagpieCommon.ps1')

$magpie = Find-MagpieExe
$cfg = Get-GatewayConfig -BaseUrl $BaseUrl -Key $Key
$keyId = Resolve-GatewayKeyId -Magpie $magpie

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
$expectedModelIds = @($modelLabels.Keys)

Write-Section 'Magpie 与网关'
Write-Host ('magpie.exe : ' + $magpie)
Write-Host ('gateway    : ' + $cfg.BaseUrl)
Write-Host ('gateway key: ' + $keyId)

Write-Section 'WorkBuddy AI 免费限制'
$options = (& $magpie plugin options workbuddy 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "无法读取 WorkBuddy 插件选项：$options" }
if ($options -match 'free_only\s+workbuddy(-ai)?\s+on') {
    Write-Host 'free_only 开启：仅免费模型可用。'
} else {
    Write-Host 'free_only 已关闭：WorkBuddy 模型可能消耗 Credits（当前采用的设置）。'
}

Write-Section 'Cursor gateway-key 白名单'
$policy = (& $magpie gateway-key models $keyId 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "无法读取 gateway-key 白名单：$policy" }
$missingInKey = @($expectedModelIds | Where-Object { $policy -notlike "*$_*" })
if ($missingInKey.Count -gt 0) {
    throw ('白名单缺少模型：' + ($missingInKey -join ', '))
}
if ($policy -match 'codex/|deepseek-2/') {
    throw 'Cursor 白名单里出现了应被排除的 Codex 或失效的 deepseek-2。'
}
Write-Host ("白名单已包含全部 {0} 个模型；Codex/GPT 与失效 key 均不在其中。" -f $expectedModelIds.Count)

Write-Section 'Cursor 模型目录与标签'
$probe = Test-Gateway -Config $cfg
if (-not $probe.Ok) {
    throw ('网关不可用：' + $probe.Reason)
}
$modelData = @($probe.Models)
$actualModelIds = @($modelData | ForEach-Object { $_.id })
$unexpected = @($actualModelIds | Where-Object { $_ -notin $expectedModelIds })
$missing = @($expectedModelIds | Where-Object { $_ -notin $actualModelIds })
$badLabels = @($modelData | Where-Object { $modelLabels.Contains($_.id) -and $modelLabels[$_.id] -ne $_.display_name })
if ($actualModelIds.Count -ne $expectedModelIds.Count -or $unexpected.Count -gt 0 -or $missing.Count -gt 0 -or $badLabels.Count -gt 0) {
    throw ("目录不一致。缺少：{0}；多余：{1}；标签需修正：{2}" -f
        ($missing -join ', '), ($unexpected -join ', '), (($badLabels | ForEach-Object { $_.id }) -join ', '))
}
$modelData | ForEach-Object { Write-Host ("{0} — {1}" -f $_.id, $_.display_name) }

# ---------- 额度 ----------
$quotaProviders = @('workbuddy-ai', 'kimi-work', 'xiaomi', 'deepseek', 'trae-cn', 'raccoon', 'zcode', 'minimax-code', 'loomy')
foreach ($provider in $quotaProviders) {
    Write-Section ('额度：' + $provider)
    try {
        # Magpie 会把 kimi-work 的登录警告写到 stderr。$ErrorActionPreference='Stop' 会把
        # 原生命令的 stderr 当成终止错误抛出，因此这里单独放宽，并且只取 stdout 的 JSON。
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $result = (& $magpie quota $provider --json 2>$null | Out-String)
        $exit = $LASTEXITCODE
        $ErrorActionPreference = $prev
        # 部分渠道即使成功返回 JSON 也会以非零码退出（同一次调用里其他渠道读取失败所致），
        # 因此以「有没有拿到 JSON」为准，退出码只作为提示。
        if (-not $result.Trim()) {
            $hint = if ($exit -ne 0) { '（magpie 退出码 ' + $exit + '）' } else { '' }
            Write-Host ('没有可读账号' + $hint + '。')
            continue
        }
        if ($exit -ne 0) { Write-Host ('注意：magpie 退出码 ' + $exit + '，但已取得数据。') }
        # JSON 顶层是数组；不要再用 @() 包裹，否则整个数组会被当成单个元素。
        $accounts = $result | ConvertFrom-Json
        if (@($accounts).Count -eq 0) { Write-Host '没有可读账号。'; continue }
        foreach ($a in $accounts) {
            # StrictMode 下不能直接访问不存在的属性，统一用 PSObject 判空。
            $err = $a.PSObject.Properties['error']
            if ($err -and $err.Value) { Write-Host ('无法读取：' + $err.Value); continue }
            $labelProp = $a.PSObject.Properties['plan']
            $label = if ($labelProp -and $labelProp.Value) { $labelProp.Value } else { $a.name }
            $bal = $a.PSObject.Properties['balance']
            if ($bal -and $bal.Value) { Write-Host ('{0}：余额 {1}' -f $label, $bal.Value) }
            $wins = $a.PSObject.Properties['windows']
            $windowList = @()
            if ($wins -and $wins.Value) { $windowList = @($wins.Value) }
            foreach ($w in $windowList) {
                if (-not $w) { continue }
                $d = $w.PSObject.Properties['display']
                $dText = if ($d) { $d.Value } else { $null }
                if ($dText) { Write-Host ('{0}：{1} = {2}' -f $label, $w.name, $dText); continue }
                $u = $w.PSObject.Properties['used']
                $r = $w.PSObject.Properties['remaining']
                if ($u -and $null -ne $u.Value) {
                    # 取整，避免出现 77.38000000000001 这种浮点往返噪声
                    $uText = [math]::Round([double]$u.Value, 2)
                    $rText = if ($r) { [math]::Round([double]$r.Value, 2) } else { '' }
                    Write-Host ('{0}：{1} 已用 {2}，剩余 {3}' -f $label, $w.name, $uText, $rText)
                }
            }
        }
    }
    catch {
        Write-Host ('读取异常：' + $_.Exception.Message)
    }
}

Write-Section '结果'
Write-Host '全部检查通过。'
exit 0
