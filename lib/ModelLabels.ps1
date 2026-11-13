# 模型标签表：唯一来源。
# 启动Cursor多来源模型.ps1 与 检查Magpie.ps1 都从这里取，避免两份表不同步。
# 键 = Magpie/自建池的模型 id；值 = 在 Cursor 里显示的名字。
#
# 改动规则：
#   1. 新增来源模型 → 这里加一行，同时把 id 加进 Gateway key 白名单。
#   2. 新增/删除自建池 → 改 src\MagpieGatewayKeeper.cs 的 Pools 数组，再同步这里的 pool/* 行。
#   3. 任何这里列出的 model 都必须能被网关解析，否则 Cursor 里会出现选不动的死项。

function Get-ModelLabels {
    [ordered]@{
        # ---- 自建池（由 Magpie网关守护.exe 在 127.0.0.1:3426 上提供）----
        'pool/deepseek-flash' = 'DeepSeek Flash Pool'
        'pool/glm' = 'GLM Pool'
        'pool/glm-flash' = 'GLM Flash Pool'
        'pool/kimi-k3.1' = 'Kimi K3.1 Pool'
        'pool/kimi-k3' = 'Kimi K3 Pool'
        'pool/kimi-k2' = 'Kimi K2 Pool'
        'pool/doubao' = 'Doubao Pool'
        'pool/gpt6-luna' = 'GPT-6 Luna Pool'
        'pool/gpt56-luna' = 'GPT-5.6 Luna Pool'
        'pool/grok-4.7' = 'Grok 4.7 Pool'
        'pool/hy' = 'Hy Pool'
        'pool/minimax-m3.1-flash' = 'MiniMax M3.1 Flash Pool'
        'pool/minimax-m3' = 'MiniMax M3 Pool'
        'pool/qwen' = 'Qwen Pool'

        # ---- 原始来源模型（池成员即由这些组成）----
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
        'workbuddy-ai/glm-5.3' = 'GLM 5.3 · WB额度 · 单价未知'
        'workbuddy-ai/glm-5.3-flash' = 'GLM 5.3 Flash · WB额度 · 单价未知'
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

        # ---- OpenCode Go（订阅制：5 小时 / 7 天 / 月 三个窗口）----
        'opencode-go/deepseek-v4.1-flash' = 'DeepSeek V4.1 Flash · OpenCode Go'
        'opencode-go/deepseek-v4-pro' = 'DeepSeek V4 Pro · OpenCode Go'
        'opencode-go/glm-5.2' = 'GLM-5.2 · OpenCode Go'
        'opencode-go/glm-5.3' = 'GLM-5.3 · OpenCode Go'
        'opencode-go/glm-5.3-flash' = 'GLM-5.3-Flash · OpenCode Go'
        'opencode-go/grok-4.7' = 'Grok 4.7 · OpenCode Go'
        'opencode-go/gpt-5.6-luna' = 'GPT-5.6 Luna · OpenCode Go'
        'opencode-go/gpt-6-luna' = 'GPT-6 Luna · OpenCode Go'
        'opencode-go/claude-haiku-5-5' = 'Claude Haiku 5.5 · OpenCode Go'
        'opencode-go/hy3' = 'Hy3 · OpenCode Go'
        'opencode-go/hy4' = 'Hy4 · OpenCode Go'
        'opencode-go/hy4-preview' = 'Hy4 Preview · OpenCode Go'
        'opencode-go/kimi-k2.7-code' = 'Kimi K2.7 Code · OpenCode Go'
        'opencode-go/kimi-k3' = 'Kimi K3 · OpenCode Go'
        'opencode-go/kimi-k3.1-pro' = 'Kimi K3.1 Pro · OpenCode Go'
        'opencode-go/mimo-v2.6-flash' = 'MiMo-V2.6-Flash · OpenCode Go'
        'opencode-go/mimo-v2.6-pro' = 'MiMo-V2.6-Pro · OpenCode Go'
        'opencode-go/minimax-m3' = 'MiniMax-M3 · OpenCode Go'
        'opencode-go/minimax-m3.1-flash' = 'MiniMax M3.1 Flash · OpenCode Go'
        'opencode-go/longcat-2.0' = 'LongCat-2.0 · OpenCode Go'
        'opencode-go/step-5-preview' = 'Step 5 Preview · OpenCode Go'
        'opencode-go/beam-free' = 'Beam Free · OpenCode Go'
        'opencode-go/qwen3.8-max' = 'Qwen3.8 Max · OpenCode Go'
        'opencode-go/qwen3.8-flash' = 'Qwen3.8 Flash · OpenCode Go'
        'opencode-go/qwen3.7-plus' = 'Qwen3.7 Plus · OpenCode Go'
        'opencode-go/gemini-4-argon' = 'Gemini 4 Argon · OpenCode Go'
    }
}

# 在 Magpie 里显式 visible 的来源。
function Get-VisibleProviders {
    @('workbuddy-ai', 'kimi-work', 'xiaomi', 'deepseek', 'trae-cn', 'raccoon', 'zcode', 'minimax-code', 'loomy', 'opencode-go')
}

# 故意不暴露给 Cursor 的模型：目录里有，但调用会被上游隐私策略拒绝。
# 不放进 Get-ModelLabels（否则 Cursor 里会出现点了就报错的死项），
# 但在这里登记，好让自检脚本把它和「漏登记」区分开。
# 要启用某个：先去 OpenCode 控制台改 Privacy 设置，再把它移进 Get-ModelLabels。
function Get-KnownUnavailableModels {
    @{
        'opencode-go/deepseek-v4.1-flash'        = '托管在欧洲/美国之外，需控制台 Privacy → Regions 选 Global'
        'opencode-go/deepseek-v4-pro'            = '同上'
        'opencode-go/longcat-2.5-free'           = '同上'
        'opencode-go/muse-spark-1.2-contributor' = '会用请求数据训练，需控制台 Privacy → Training 打开付费端点'
        'opencode-go/muse-spark-1.3-contributor' = '同上'
        'opencode-go/iceman-contributor-free'    = '同上'
    }
}
