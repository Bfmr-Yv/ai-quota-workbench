# AI 额度开发工作台

把多个 AI 订阅与 API 渠道聚合成一个本地网关，供 Cursor Private Inference 使用；标清每个模型的来源与计价方式，并保证网关长期在线。

本机网关固定为 `http://127.0.0.1:3425/v1`，Cursor 用 `magpie-cursor-local` 作为 key 接入。真实账号凭据只存在 Magpie 里，不进本项目。

## 快速开始

> 换一台电脑从零部署，请看 **[新电脑部署.md](新电脑部署.md)**。

```powershell
# 1. 只读自检：确认依赖、网关、模型目录与各渠道额度
powershell -ExecutionPolicy Bypass -File 部署.ps1 -Check

# 2. 正式部署：编译守护程序 + 注册登录自启 + 桌面快捷方式
powershell -ExecutionPolicy Bypass -File 部署.ps1

# 3. 日常检查（只读，不改任何配置）
powershell -ExecutionPolicy Bypass -File 检查Magpie.ps1
```

Cursor 侧只需配置一次：**Settings → Models → Gateway → Configure gateway**，Base URL 填 `http://127.0.0.1:3425/v1`，API Key 填 `magpie-cursor-local`；再点 **Refresh model**，启用 **DeepSeek Flash Pool**。

## 目录结构

```
.
├── 部署.ps1                 一键部署 / -Check 只读自检 / -Uninstall 撤销
├── 检查Magpie.ps1           只读检查：目录、白名单、标签、9 个渠道额度
├── 启动Cursor多来源模型.ps1  修复工具：重设标签与白名单；-DryRun 只预览
├── Magpie网关守护.exe        托盘常驻，保证 3425 一直可用（编译产物）
├── lib/MagpieCommon.ps1     公共模块：路径探测、UTF-8 读取、key 解析
├── src/MagpieGatewayKeeper.cs  守护程序源码
├── 鲸鱼娘/                   额度桌宠（独立子项目，见 鲸鱼娘说明.md）
├── archive/                 历史文件与本机专属备份（不入版本库）
├── 接入状态.md              各渠道接入过程记录
└── README.md
```

## 可移植性设计

早期版本把本机路径和随机 key ID 写死在脚本里，换机器就会失败。现在全部改为运行时探测：

| 项目 | 解析方式 |
|---|---|
| Magpie 路径 | `MAGPIE_EXE` 环境变量 → `%LOCALAPPDATA%\Programs\magpie` → `Program Files` → `PATH` |
| Cursor 路径 | `CURSOR_EXE` → `%LOCALAPPDATA%\Programs\cursor` → `Program Files` |
| gateway key | 设置 `MAGPIE_GATEWAY_KEY_ID`，或从 `magpie gateway-key list` 按名称 `Cursor Private Inference` 动态匹配 |
| 网关地址 | 默认 `127.0.0.1:3425`，可用 `-BaseUrl` / `-Key` 覆盖 |
| 编译器 | 优先 `PATH` 里的 `csc.exe`，否则退到 .NET Framework 4.x 目录 |
| 桌面目录 | `[Environment]::GetFolderPath('Desktop')`，兼容重定向的桌面 |

脚本采用 UTF-8 **带 BOM** 保存。Windows PowerShell 5.1 会把无 BOM 的脚本按 ANSI 解析，中文标签会被破坏导致语法错误——这是本项目已经踩过两次的坑。

所有 `.ps1` 都应在仓库根目录或任意位置通过绝对路径调用；内部一律使用 `$PSScriptRoot` 定位资源，不依赖当前工作目录。

## 网关守护

`Magpie网关守护.exe` 只负责一件事：保证 `127.0.0.1:3425` 一直可用。它**不启动 Cursor，也不读写 Cursor 的配置**。

- 启动时探测网关（HTTP 200 才算通），不通则拉起 `magpie tray` 并等待就绪。
- 托盘常驻，每 30 秒探测；连续两次失败才重启 Magpie，避免网络抖动导致反复重启。
- 图标颜色即状态：绿=连通，黄=检查中/无响应，红=启动失败。
- 托盘右键：立即检查、打开 Magpie、复制 Cursor 网关地址、退出。
- 单实例，重复双击静默退出。

实测：强制结束 Magpie 后约 50 秒内自动恢复监听。

## 模型与计价

模型显示名直接标明来源和计价性质，不把付费渠道说成免费。

| 来源 | 计价性质 |
|---|---|
| WorkBuddy AI | Hy3 免费；其余模型消耗 WB Credits，单价未知 |
| Kimi Work | 月度会员共享额度，按功能共用，单价未知 |
| 小米 MiMo Token Plan | 按 Token Plan Credits/token 扣除；¥/M 只是普通 API 参考价 |
| DeepSeek 官方 API | 按账户余额计费，工作日晚高峰价格翻倍 |
| Trae CN / 小浣熊 / Loomy / ZCode / MiniMax | 积分制，单价未知 |

详细的模型清单与价格说明见 `部署.ps1 -Check` 或 `检查Magpie.ps1` 的实时输出——额度会变化，不在文档里写死数字。

### DeepSeek Flash 混池

`group/deepseek-flash-pool` 把 8 个来源聚成一个池，Cursor 里显示为 **DeepSeek Flash Pool**。顺序为：WorkBuddy → Loomy → Trae → 小浣熊的 DeepSeek V4.1 Flash，其次 Loomy MiMo V2.5、小米 MiMo V2.6 Flash/Pro，最后由 DeepSeek 官方 API 兜底。`routing=order`、`stays=turn`：每轮重新选源，单轮内保持同一来源。

8 个成员均已实测可用。官方 API 兜底会消耗余额，积分来源也不保证无限免费。

## 排除项

- **Codex / GPT**：本机有登录，但始终从 Cursor 白名单中排除。
- **Google Antigravity**：Magpie 提示在 Antigravity 外使用可能导致账号被暂停，按用户选择未接入。
- **`deepseek-2`**：指向 `api.deepseek.com` 但调用返回 401，无效，未接入。

## 注意事项

- 守护程序路径若被移动或删除，登录自启会失效，需重跑 `部署.ps1` 或改 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 中的 `MagpieGatewayKeeper`。
- Cursor 从桌面图标启动时继承 `explorer.exe` 的环境快照。若刚改过环境变量未生效，注销重登或用 `Configure gateway` 直接写入配置（优先级更高）。
- 小米 Token Plan 余额需在小米控制台查看，Magpie 没有对应接口。
- API key、Cookie、refresh token 和账号数据不得提交到项目。

## 参考

- [Magpie](https://github.com/yetone/magpie)
- [Magpie WorkBuddy 插件](https://github.com/magpie-community/plugins/blob/main/packages/workbuddy/README.md)
- [Magpie Kimi Work 插件](https://github.com/magpie-community/plugins/blob/main/packages/kimi-work/README.md)
- [Kimi 会员共享额度规则](https://www.kimi.com/help/membership/membership-update-rules)
- [小米 MiMo Token Plan](https://mimo.mi.com/docs/zh-CN/tokenplan)
- [小米 MiMo 价格](https://mimo.mi.com/docs/pricing)
- [DeepSeek API 价格](https://api-docs.deepseek.com/quick_start/pricing/)

## 变更记录

- **2026-11-04 工程化重构**：抽出 `lib/MagpieCommon.ps1` 公共模块，移除硬编码路径与 key ID；新增 `部署.ps1` 与 `-DryRun`；补 UTF-8 BOM；修复 `Invoke-RestMethod` 在 PS 5.1 下按 ANSI 解码导致的标签误判；修复额度读取被 stderr 警告与 `@()` 双层包裹干扰；修复 `visible` 中无效的 `group` 参数；文件归档到 `archive/`。
- **2026-11-04 网关守护**：新增 `Magpie网关守护.exe`，替代此前的启动脚本方案；撤销 3426 兼容适配层，恢复直连；清理幽灵模型 `workbuddy-ai/hy4-preview`。
- **2026-11-04 模型池扩充**：接入 Trae CN、小浣熊、ZCode、MiniMax、Loomy，白名单扩至 58 个单模型，建立 DeepSeek Flash 混池。

## 2026-11-04 池改由守护 EXE 实现（当前方案）

### 为什么改

Magpie 的 `group/*` 路由池在 Cursor 里**永远不可见**。查到的根因是：

Cursor 缓存目录时，用 `native_endpoints` 推导 `api_types`。实测 57 个可显示条目里，`api_types` 与 `native_endpoints` 严格一一对应（`/v1/chat/completions` → `chat_completions`，`/v1/messages` → `anthropic_messages`）。`group/deepseek-flash-pool` 缺少 `native_endpoints`（同时缺 `pricing` 和 `modalities.output`），推不出可用端点，被丢弃。网关返回 58 个，Cursor 只收 57 个，差的正是池。

给 group 补字段走不通（`magpie group set` 没有这类字段，`id=` 只能去掉 `auto-` 前缀），在 Cursor 里手动 `Add Custom Model` 也不显示。因此把池的实现移到本项目自己的守护程序里。

### 现在的架构

```
Cursor  →  127.0.0.1:3426（本程序）  →  127.0.0.1:3425（Magpie）
```

本程序对 Cursor 暴露结构完整的标准模型条目 `pool/deepseek-flash`（显示名 **DeepSeek Flash Pool**），池的路由在自己的代码里完成，天然满足 Cursor 的约定，不再受 Magpie 条目字段影响。

- `/v1/models`：转发 Magpie 目录，去掉无法显示的 `group/*`，把自建池插到首位；其余 57 个模型原样透传。
- `/v1/chat/completions`：请求的是池时，按优先级逐个尝试成员，首个成功即返回，并回写 `X-Pool-Member` 头标明实际来源；非池请求原样转发。
- 流式请求：连上就锁定该成员，同一轮不混用来源，SSE 逐块透传。

### 记忆共享

避免切换来源时"失忆"是本程序的核心设计：

- **会话指纹**：取 `messages` 里第一条 user 消息做 SHA-256 前缀。Cursor 每轮都带完整历史，首条消息在整个对话里稳定，因此同一对话的指纹不变。
- **来源记忆**：按指纹记住最近一次成功的成员（最多 200 个会话，LRU 淘汰）。下一轮把该成员提到队首，不再从第一个重新试起。
- **跨轮稳定**：同一对话持续使用同一来源，缓存和上下文不被打断；切换来源只发生在成员失败时。

### 池成员顺序

| # | 模型 | 消耗性质 |
|---|---|---|
| 1 | `workbuddy-ai/deepseek-v4.1-flash-sg` | WB 额度 |
| 2 | `loomy/DeepSeek-V4.1-Flash` | Loomy 积分 |
| 3 | `trae-cn/deepseek-v4.1-flash` | Trae 积分 |
| 4 | `raccoon/sn-deepseek-v4-1-flash-1017` | 小浣熊积分 |
| 5 | `loomy/mimo-v2.5` | Loomy MiMo |
| 6 | `xiaomi/mimo-v2.6-flash` | 小米 Token Plan |
| 7 | `xiaomi/mimo-v2.6-pro` | 小米 Token Plan Pro |
| 8 | `deepseek/deepseek-flash` | 官方 API 付费兜底 |

要改顺序或成员，编辑 `src/MagpieGatewayKeeper.cs` 里的 `PoolMembers` 数组，然后重跑 `部署.ps1`。

### Cursor 侧配置

Base URL 改为 `http://127.0.0.1:3426/v1`，API Key 仍是 `magpie-cursor-local`。托盘右键「复制 Cursor 网关地址」可一键复制。之后在 **Settings → Models** 点 Refresh model，选 **DeepSeek Flash Pool**。

注意：Cursor 有目录缓存（`cursor/localProviderModelCatalog`），改端口后需要它重新拉取才能看到池。

### 实测

- 目录：58 条，含 `pool/deepseek-flash` 且排在首位，`group/*` 已无残留，池条目五个关键字段齐全。
- 非流式：HTTP 200，走 WB 成员，响应头 `X-Pool-Member: workbuddy-ai/deepseek-v4.1-flash-sg`。
- 记忆共享：同一对话第二轮仍命中同一成员。
- 流式：HTTP 200，9 个 data 块，正常 `[DONE]` 结束。
- 故障回退：把首成员替换成不存在的模型后，自动跳到第二个 Loomy 并返回 200。
## 2026-11-04 池调度插件：额度感知、自动切换、记忆互通

池不再只是「按顺序试」，而是由一个调度器决定每次走哪个来源。源码见 `src/PoolScheduler.cs`。

### 三层决策

每次请求按以下顺序决定用哪个成员：

1. **记忆优先**：同一对话的上次成功来源排最前，保证多轮对话不换源、缓存和上下文不中断。
2. **额度排序**：按剩余额度比例排序。低于 10%（`LowWatermark`）的成员即使被记忆命中也会让位，避免死守一个快耗尽的渠道。
3. **冷却排除**：请求失败的成员进入冷却，分数降到最低，排到队尾。

### 额度归一化

各渠道的额度格式差异很大，这里统一成 0..1 的比例：

| 渠道 | 原始格式 | 处理方式 |
|---|---|---|
| WorkBuddy | Credits 0/100、Extra 0.02/350 | 数值窗口，按剩余比例 |
| Kimi / Trae / 小浣熊 | used/limit 数值 | 按剩余比例 |
| Loomy | 文本窗口 `4994 credits` | 解析首数字，有余额即视为可用 |
| 小米 | 无余额接口 | 标记未知，靠请求失败兜底 |
| DeepSeek | 金额 `¥27.23` | 记录金额，比例视为未知 |

额度每 120 秒刷新一次，读不到就保持「未知」，不阻断调度。

### 自动切换

- **失败即切**：成员返回非 2xx 时立刻换下一个，同一次请求内完成，调用方无感。
- **指数退避**：首次失败冷却 30 秒，连续失败翻倍，上限 10 分钟。到期自动回归调度。
- **流式保护**：流式请求一旦建连就锁定成员，不在同一轮里混用来源，避免上下文断裂。
- **稳定排序**：分数相同时按池内声明顺序决定先后。`.NET` 的 `List.Sort` 不稳定，只比分数会让同分成员顺序随机漂移，因此显式加了序号决胜。

### 托盘状态

托盘菜单实时显示池的健康摘要，例如：

```
最近 WB 额度｜Trae 积分(100%)  Loomy 积分(90%)  小米 TP  官方 API 付费  WB 额度(5%)
```

冷却中的成员标 `(冷却)`，额度未知的不显示百分比。

### 实测

- 额度排序：`Trae(100%) → Loomy(90%) → 未知 → WB(5%)`，低额度成员确实被压到末尾。
- 故障冷却：成员失败后立刻降到末位，其余前移。
- 记忆优先但额度不足：记住的成员只剩 5% 时自动让位，不会坚持使用。
- 端到端：同一对话连续三轮走同一来源；流式 27 个 data 块正常结束。

### 注意

池成员顺序在 `src/MagpieGatewayKeeper.cs` 的 `PoolMembers` 数组里，调整后重跑 `部署.ps1` 即可。近额度阈值和冷却参数在 `src/PoolScheduler.cs` 顶部的常量里。