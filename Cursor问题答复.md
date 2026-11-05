# 回答：关于 Cursor Private Inference 的几个判断

这份说明基于**成功机器上的实测证据**，用来纠正原分析中几处与事实不符的推断。

---

## 核心结论先说

原分析里最关键的那条假设——「那台机器登录的是另一个（付费或团队）账号」——**不成立**。

成功机器上：

- 账号 `yvbfmr@gmail.com`
- `stripeMembershipType = free`
- 没有任何组织
- 构建确实是 `Cursor Private Inference` v3.28.7

也就是说：**免费账号 + Private Inference 构建可以正常连接本地网关**。这条路不需要团队或企业权限。

---

## 逐条回答 Q1–Q5

### Q1｜Cursor 是哪个构建？

**是 Private Inference 构建，但安装目录名不叫 `cursor-private-inference`。**

| 检查项 | 实际值 |
|---|---|
| 安装目录 | `%LOCALAPPDATA%\Programs\cursor`（**不是** `cursor-private-inference`）|
| `product.json` → `nameLong` | `Cursor Private Inference` |
| `nameShort` | `Cursor Private Inference` |
| `version` | `3.28.7` |
| `quality` | `stable` |
| 可执行文件名 | `Cursor Private Inference.exe` |

⚠️ 原问题里「看有没有 `cursor-private-inference` 目录」这个判断方式会误判。目录名依然是 `cursor`，**必须看 `product.json` 的 `nameLong` 或可执行文件名**。

数据目录则确实分开了：`%APPDATA%\Cursor` 和 `%APPDATA%\Cursor Private Inference` 并存。

### Q2｜登录的是哪个账号？

成功机器：`yvbfmr@gmail.com`，**free 套餐**。

这直接否定了「需要付费/团队账号」的假设。对方机器上的 `free` 不是障碍。

### Q3｜版本号？

`3.28.7`，`quality = stable`。

### Q4｜"Gateway" 在哪里？

`Settings → Models` 页面，**模型列表下方**有一个 `Gateway` 区块，里面有 `Base URL` 和 `API Key` 两行，点 **`Configure gateway`** 按钮打开对话框。

对话框里写得很清楚：

> Connect Cursor to a compatible LLM Gateway or API when in local mode.
> Can also set via `CURSOR_LOCAL_AGENT_BASE_URL`, `CURSOR_LOCAL_AGENT_API_KEY`, and `CURSOR_LOCAL_AGENT_HEADERS`.

### Q5｜那个按钮长什么样？

**不是设置页里的按钮**，是更新完成后弹出的对话框：

> **标题**：Cursor Private Inference is available
> **说明**：Download Cursor Private Inference to use your organization's private inference deployment.
> **按钮**：`Continue Update` / `Download Cursor Private Inference`

这里有个重要发现：它是**更新流程的一部分**——普通 Cursor 检查到新版本时弹出这个框，让你选「继续普通更新」还是「下载 Private Inference」。

---

## 原分析里需要修正的三处

### 1. 不是「公开下载 403」，而是通过更新通道下发

源码里触发条件是：

```js
if (!o.checkFeatureGate("cursor_private_inference_download_prompt")) return await f();
```

这是个 **feature gate（实验开关）**，由服务端按比例放量，**与账号套餐、组织身份无关**。所以：

- 不是「桶返回 403」那么简单
- 也不是「只给团队/企业」
- 而是**灰度放量**：部分账号会看到，部分不会

这解释了为什么两台机器表现不同——大概率不是账号差异，而是**是否被命中灰度**。

### 2. 不需要另装一个 exe，它是原地升级

安装目录创建于 3 月，Private Inference 构建文件写入于 11 月 3 日，同一个 `%LOCALAPPDATA%\Programs\cursor` 目录。数据目录 `Cursor Private Inference` 创建于 11 月 4 日。

**结论：普通 Cursor 原地升级成了 Private Inference，没有单独安装包。**

### 3. 「普通版无法连 127.0.0.1」这个结论需要限定

这个判断在**普通构建**上成立，但原因不是「订阅不足」。真正的区别在于构建本身：

- 普通构建：本地网关配置被 `Sl.localMode` 控制，且有订阅校验
- Private Inference 构建：`Sl.localMode = true`，本地网关是一等公民

所以问题不是「花钱就能解决」，而是**必须拿到这个构建**。

---

## 建议的处理顺序

按成本从低到高：

### 方案 A：等灰度命中（成本最低）

在另一台机器的普通 Cursor 里：

1. 保持登录 `free` 账号（**不用换账号**）
2. 让它完成一次版本更新（`Help → Check for Updates`）
3. 更新完成后如果弹出 **Cursor Private Inference is available**，点 **Download Cursor Private Inference**

如果没弹，说明该账号没被命中灰度。可以多试几次更新，或换个时间段。

### 方案 B：直接连 Magpie 补丁端口，绕开本地网关限制

如果最终拿不到 Private Inference 构建，**不要让 Cursor 连 `127.0.0.1`**。

关键点：原分析里「请求由 Cursor 服务器发出，会拒绝 127.0.0.1」——如果 FTT 监听在 `127.0.0.1:3427`，Cursor 的云端确实够不到。但可以让网关**监听在局域网地址**上，或用本项目的补丁代理暴露出去，再用 Cursor 的**自定义模型**接入。

不过这仍然受 `Cursor Subscription Required` 限制，**只解决「连不上」，解决不了「不能用」**。

### 方案 C：换客户端（今天就能用）

原分析里提到 Cline，这个方向是对的。既然目标是在编辑器里用上 112 个模型，而不是绑定 Cursor：

- VS Code + Cline / Continue 等扩展，配置 `http://127.0.0.1:3427/v1` + FTT 的 key
- 这些扩展直接用本地 HTTP 请求，**没有订阅校验**

如果 Q6 的答案是「只要能在编辑器里用上这 112 个模型就行」，这条路径最省事。

---

## 关于本项目的补丁代理

顺带说明：本项目的 `Magpie网关守护.exe` 在 `127.0.0.1:3426` 提供一个改造过的网关。它解决的是**另一个问题**——Magpie 自身的 `group/*` 路由池条目缺少 `native_endpoints` 字段，导致 Cursor 丢弃该条目。它**不能**绕过 Cursor 的订阅校验。

所以如果目标机器连的是 FTT 的 3427，这个补丁不适用；除非也要把 FTT 的模型池化。

---

## 最后

原分析的技术功底很好，尤其是「请求从 Cursor 服务器发出」这个观察是对的。真正需要修正的是**归因**：把「灰度未命中」误判成了「缺少团队权限」。

建议先回答一个问题来确定方向：**那台机器上有没有 `%APPDATA%\Cursor Private Inference` 这个数据目录？如果有，说明它确实跑过 Private Inference，那就照上面的方案 A 走。**
