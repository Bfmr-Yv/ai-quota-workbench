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

. (Join-Path $PSScriptRoot 'lib\ModelLabels.ps1')
$modelLabels = Get-ModelLabels
$knownUnavailable = Get-KnownUnavailableModels
$expectedModelIds = @($modelLabels.Keys)

Write-Section 'Magpie 与网关'
Write-Host ('magpie.exe : ' + $magpie)
Write-Host ('gateway    : ' + $cfg.BaseUrl)
Write-Host ('gateway key: ' + $keyId)

Write-Section 'WorkBuddy AI 免费限制'
$options = Invoke-MagpieText -Magpie $magpie -Arguments @('plugin','options','workbuddy')
if (-not $options) { throw '无法读取 WorkBuddy 插件选项：magpie 没有返回任何内容' }
if ($options -match 'free_only\s+workbuddy(-ai)?\s+on') {
    Write-Host 'free_only 开启：仅免费模型可用。'
} else {
    Write-Host 'free_only 已关闭：WorkBuddy 模型可能消耗 Credits（当前采用的设置）。'
}

Write-Section 'Cursor gateway-key 白名单'
$policy = Invoke-MagpieText -Magpie $magpie -Arguments @('gateway-key','models',$keyId)
if (-not $policy) { throw '无法读取 gateway-key 白名单：magpie 没有返回任何内容' }
# pool/* 由本项目的守护程序在 3426 上自建，不是 Magpie 的上游模型，不该出现在 Magpie 白名单里。
$upstreamIds = @($expectedModelIds | Where-Object { $_ -notlike 'pool/*' })
$missingInKey = @($upstreamIds | Where-Object { $policy -notlike "*$_*" })
if ($missingInKey.Count -gt 0) {
    throw ('白名单缺少模型：' + ($missingInKey -join ', '))
}
if ($policy -match 'codex/|deepseek-2/') {
    throw 'Cursor 白名单里出现了应被排除的 Codex 或失效的 deepseek-2。'
}
Write-Host ("白名单已包含全部 {0} 个上游模型；Codex/GPT 与失效 key 均不在其中。" -f $upstreamIds.Count)

Write-Section 'Cursor 模型目录与标签'
$probe = Test-Gateway -Config $cfg
if (-not $probe.Ok) {
    throw ('网关不可用：' + $probe.Reason)
}
$modelData = @($probe.Models)
$actualModelIds = @($modelData | ForEach-Object { $_.id })
# 这里查的是 Magpie 本体目录（3425），pool/* 由守护程序在 3426 上另建，
# 因此比对时把 pool/* 排除；池的可用性由 3426 的独立探测覆盖。
$expectedUpstream = @($expectedModelIds | Where-Object { $_ -notlike 'pool/*' })
$actualUpstream = @($actualModelIds | Where-Object { $_ -notlike 'pool/*' })
$unexpected = @($actualUpstream | Where-Object { $_ -notin $expectedUpstream })
$missing = @($expectedUpstream | Where-Object { $_ -notin $actualUpstream })
# Magpie 的路由分组（group/*）、自动均衡（auto/*）不是具体模型，不参与比对。
$unexpected = @($unexpected | Where-Object { $_ -notlike 'group/*' -and $_ -notlike 'auto/*' -and -not $knownUnavailable.ContainsKey($_) })
# 上游目录会随时变动（模型下线、额度用尽被隐藏），缺失只提示不阻断。

# 标签只做提示，不当作硬失败：Magpie 会自行加后缀，这不影响可用性。
$labelDrift = @($modelData | Where-Object {
    $modelLabels.Contains($_.id) -and $modelLabels[$_.id] -ne $_.display_name -and $_.id -notlike 'pool/*'
})

if ($missing.Count -gt 0) {
    Write-Host ('提示：{0} 个上游模型当前不在网关目录里（可能额度用尽或上游已下线）：{1}' -f $missing.Count, ($missing -join ', '))
}
if ($unexpected.Count -gt 0) {
    throw ("目录里出现了标签表未登记的模型：{0}" -f ($unexpected -join ', '))
}
if ($labelDrift.Count -gt 0) {
    Write-Host ('注意：{0} 个模型的显示名由 Magpie 自动命名，与配置不同（非错误）。' -f $labelDrift.Count)
}
$modelData | ForEach-Object { Write-Host ("{0} — {1}" -f $_.id, $_.display_name) }

# ---------- 额度 ----------
$quotaProviders = @('workbuddy-ai', 'kimi-work', 'xiaomi', 'deepseek', 'trae-cn', 'raccoon', 'zcode', 'minimax-code', 'loomy', 'opencode-go')
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

