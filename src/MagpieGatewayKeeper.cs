// Magpie 网关守护 + 自建路由池（托盘常驻）
//
// 下游：Cursor。上游：Magpie (127.0.0.1:3425)。
//
// 为什么由本程序实现池，而不是用 Magpie 的 group/：
//   Cursor 用 native_endpoints 推导 api_types，缺这个字段的条目会被直接丢弃，
//   Magpie 的 group/* 条目恰好缺这些字段，所以永远不出现在选择器里。
//   本程序对外暴露结构完整的标准模型条目，池在内部按规则路由，天然满足 Cursor 的约定。
//
// 能力：
//   1. 对 Cursor 暴露 127.0.0.1:3426，把请求转发给 Magpie
//   2. 自建池：按「记忆 > 额度 > 顺序」调度，失败自动切换到下一个，无感
//   3. 额度感知：定时读取各渠道额度，接近耗尽的成员自动降权
//   4. 故障冷却：失败的成员进入指数退避冷却，到期自动回归
//   5. 记忆共享：同一对话优先复用上次成功的来源
//   6. 守护 Magpie：不可用则拉起，连续失败则重启
//   7. 托盘：状态、池健康摘要、手动检查、打开 Magpie、复制地址、退出
//
// 不启动 Cursor，也不读写 Cursor 的配置。
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace MagpieGatewayKeeper
{
    internal static class Program
    {
        internal const string UpstreamOrigin = "http://127.0.0.1:3425";
        internal const string UpstreamBase = "http://127.0.0.1:3425/v1";
        internal const string GatewayKey = "magpie-cursor-local";

        internal const int ProxyPort = 3426;
        internal const string ProxyBase = "http://127.0.0.1:3426/v1";

        // 自建池对外暴露的模型 id
        internal const string PoolId = "pool/deepseek-flash";
        internal const string PoolName = "DeepSeek Flash Pool";

        private const string MutexName = @"Local\MagpieGatewayKeeper.SingleInstance";

        internal const int PollSeconds = 30;
        internal const int QuotaRefreshSeconds = 120;
        internal const int FailuresBeforeRestart = 2;
        internal const int BootWaitSeconds = 20;

        // 池成员，按顺序尝试。标签体现消耗性质，便于在托盘和日志里辨认。
        internal static readonly PoolMember[] PoolMembers =
        {
            new PoolMember("workbuddy-ai/deepseek-v4.1-flash-sg", "WB 额度"),
            new PoolMember("loomy/DeepSeek-V4.1-Flash", "Loomy 积分"),
            new PoolMember("trae-cn/deepseek-v4.1-flash", "Trae 积分"),
            new PoolMember("raccoon/sn-deepseek-v4-1-flash-1017", "小浣熊积分"),
            new PoolMember("loomy/mimo-v2.5", "Loomy MiMo"),
            new PoolMember("xiaomi/mimo-v2.6-flash", "小米 TP"),
            new PoolMember("xiaomi/mimo-v2.6-pro", "小米 TP Pro"),
            new PoolMember("deepseek/deepseek-flash", "官方 API 付费")
        };

        [STAThread]
        private static void Main()
        {
            bool createdNew;
            using (Mutex mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    // 已有实例在守护；静默退出，不弹窗打断重复双击
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                using (TrayApp app = new TrayApp())
                {
                    app.Start();
                    Application.Run();
                }
            }
        }

        internal static string MagpiePath
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    @"Programs\magpie\magpie.exe");
            }
        }

        internal static bool ProbeGateway(out string detail)
        {
            detail = string.Empty;
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(UpstreamBase + "/models");
                req.Method = "GET";
                req.Timeout = 2500;
                req.ReadWriteTimeout = 2500;
                req.Proxy = null;
                req.Headers["Authorization"] = "Bearer " + GatewayKey;

                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                {
                    if ((int)resp.StatusCode == 200)
                    {
                        return true;
                    }
                    detail = "HTTP " + (int)resp.StatusCode;
                    return false;
                }
            }
            catch (WebException wex)
            {
                HttpWebResponse er = wex.Response as HttpWebResponse;
                if (er != null)
                {
                    detail = "HTTP " + (int)er.StatusCode;
                    er.Close();
                }
                else
                {
                    detail = wex.Message;
                }
                return false;
            }
            catch (Exception ex)
            {
                detail = ex.Message;
                return false;
            }
        }

        internal static bool StartMagpie()
        {
            string exe = MagpiePath;
            if (!File.Exists(exe))
            {
                return false;
            }
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                psi.Arguments = "tray";
                Process.Start(psi);
                return true;
            }
            catch
            {
                return false;
            }
        }

        internal static bool MagpieRunning()
        {
            try
            {
                return Process.GetProcessesByName("magpie").Length > 0;
            }
            catch
            {
                return false;
            }
        }

        internal static bool WaitForGateway(int seconds, out string detail)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(seconds);
            detail = string.Empty;
            while (DateTime.UtcNow < deadline)
            {
                if (ProbeGateway(out detail))
                {
                    return true;
                }
                Thread.Sleep(500);
            }
            return false;
        }
    }

    internal sealed class PoolMember
    {
        public readonly string ModelId;
        public readonly string Label;

        public PoolMember(string modelId, string label)
        {
            ModelId = modelId;
            Label = label;
        }
    }

    /// <summary>
    /// 池的记忆：每个对话上次成功的来源，切换后不会每轮从头试。
    /// </summary>
    internal sealed class PoolState
    {
        private const int MaxSessions = 200;

        private readonly Dictionary<string, string> _bySession =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly LinkedList<string> _order = new LinkedList<string>();
        private readonly object _lock = new object();

        public string LastLabel;

        // 是否在来源切换时往回复里附加额度说明
        public bool NotifyOnChange = true;

        public string Get(string session)
        {
            if (string.IsNullOrEmpty(session))
            {
                return null;
            }
            lock (_lock)
            {
                string v;
                return _bySession.TryGetValue(session, out v) ? v : null;
            }
        }

        public void Set(string session, string modelId, string label)
        {
            LastLabel = label;
            if (string.IsNullOrEmpty(session))
            {
                return;
            }
            lock (_lock)
            {
                if (!_bySession.ContainsKey(session))
                {
                    _order.AddLast(session);
                }
                _bySession[session] = modelId;
                while (_order.Count > MaxSessions)
                {
                    string old = _order.First.Value;
                    _order.RemoveFirst();
                    _bySession.Remove(old);
                }
            }
        }
    }

    internal sealed class GatewayProxy : IDisposable
    {
        private readonly HttpListener _listener;
        private readonly JavaScriptSerializer _json = new JavaScriptSerializer();
        private Thread _thread;
        private volatile bool _stopping;

        public readonly PoolState State = new PoolState();
        public readonly PoolScheduler Scheduler = new PoolScheduler(Program.PoolMembers);

        public GatewayProxy()
        {
            _listener = new HttpListener();
            _listener.Prefixes.Add("http://127.0.0.1:" + Program.ProxyPort + "/");
        }

        public bool Start(out string error)
        {
            error = null;
            try
            {
                _listener.Start();
            }
            catch (Exception ex)
            {
                error = ex.Message;
                return false;
            }

            _thread = new Thread(Loop);
            _thread.IsBackground = true;
            _thread.Name = "gateway";
            _thread.Start();
            return true;
        }

        private void Loop()
        {
            while (!_stopping)
            {
                HttpListenerContext ctx;
                try
                {
                    ctx = _listener.GetContext();
                }
                catch (Exception)
                {
                    if (_stopping)
                    {
                        return;
                    }
                    Thread.Sleep(200);
                    continue;
                }

                ThreadPool.QueueUserWorkItem(delegate { Handle(ctx); });
            }
        }

        private void Handle(HttpListenerContext ctx)
        {
            try
            {
                string path = ctx.Request.Url.AbsolutePath.TrimEnd('/');

                if (ctx.Request.HttpMethod == "GET" && path.Equals("/v1/models", StringComparison.OrdinalIgnoreCase))
                {
                    HandleModels(ctx);
                    return;
                }

                byte[] body;
                using (MemoryStream ms = new MemoryStream())
                {
                    if (ctx.Request.HasEntityBody)
                    {
                        ctx.Request.InputStream.CopyTo(ms);
                    }
                    body = ms.ToArray();
                }

                if (ctx.Request.HttpMethod == "POST" && path.Equals("/v1/chat/completions", StringComparison.OrdinalIgnoreCase))
                {
                    HandleChat(ctx, body);
                    return;
                }

                ProxyStream(ctx, body);
            }
            catch (Exception)
            {
                TryClose(ctx);
            }
        }

        // ---------- /v1/models：转发 Magpie，去掉 group/，加上自建池 ----------

        private void HandleModels(HttpListenerContext ctx)
        {
            int status;
            List<KeyValuePair<string, string>> headers;
            byte[] body = ReadUpstream(ctx, null, out status, out headers);

            if (status == 200 && body != null && body.Length > 0)
            {
                try
                {
                    object parsed = _json.DeserializeObject(Encoding.UTF8.GetString(body));
                    Dictionary<string, object> root = parsed as Dictionary<string, object>;
                    object dataObj;
                    if (root != null && root.TryGetValue("data", out dataObj))
                    {
                        object[] arr = dataObj as object[];
                        if (arr != null)
                        {
                            List<object> list = new List<object>();
                            // 池条目放最前，便于在选择器顶部找到
                            list.Add(BuildPoolEntry());

                            foreach (object o in arr)
                            {
                                Dictionary<string, object> d = o as Dictionary<string, object>;
                                if (d == null)
                                {
                                    continue;
                                }
                                object idv;
                                string id = (d.TryGetValue("id", out idv) ? idv : null) as string;
                                // Magpie 的 group/* 在 Cursor 里不可见，交给本程序的池
                                if (id != null && id.StartsWith("group/", StringComparison.OrdinalIgnoreCase))
                                {
                                    continue;
                                }
                                list.Add(o);
                            }

                            root["data"] = list.ToArray();
                            body = Encoding.UTF8.GetBytes(_json.Serialize(root));
                        }
                    }
                }
                catch
                {
                    // 解析失败就原样返回
                }
            }

            Write(ctx, status, headers, body);
        }

        /// <summary>
        /// 结构完整的池条目，字段对齐 Magpie 的普通模型，确保 Cursor 不会丢弃。
        /// </summary>
        private static Dictionary<string, object> BuildPoolEntry()
        {
            Dictionary<string, object> caps = new Dictionary<string, object>();
            caps["supports_tool_use"] = true;
            caps["supports_streaming"] = true;
            caps["supports_reasoning"] = true;
            caps["supports_vision"] = false;
            caps["output_modalities"] = new object[] { "text" };
            caps["input_modalities"] = new object[] { "text" };
            caps["context_length"] = 1048576;
            caps["max_output_tokens"] = 65536;
            caps["reasoning_effort"] = new object[] { "low", "high" };

            Dictionary<string, object> mod = new Dictionary<string, object>();
            mod["input"] = new object[] { "text" };
            mod["output"] = new object[] { "text" };

            Dictionary<string, object> pricing = new Dictionary<string, object>();
            pricing["prompt"] = "0";
            pricing["completion"] = "0";
            pricing["input_cache_read"] = "0";

            Dictionary<string, object> e = new Dictionary<string, object>();
            e["id"] = Program.PoolId;
            e["object"] = "model";
            e["type"] = "model";
            e["created"] = 0;
            e["created_at"] = "2025-01-01T00:00:00Z";
            e["owned_by"] = "magpie-pool";
            e["display_name"] = Program.PoolName;
            e["context_length"] = 1048576;
            e["context_window"] = 1048576;
            e["max_input_tokens"] = 1048576;
            e["max_output_tokens"] = 65536;
            e["reasoning"] = true;
            e["reasoning_levels"] = new object[] { "low", "high" };
            e["tool_call"] = true;
            e["native_endpoints"] = new object[] { "/v1/chat/completions" };
            e["modalities"] = mod;
            e["capabilities"] = caps;
            e["pricing"] = pricing;
            e["api_types"] = new object[] { "chat_completions" };

            return e;
        }

        // ---------- 对话：池内调度 ----------

        private void HandleChat(HttpListenerContext ctx, byte[] body)
        {
            Dictionary<string, object> payload;
            try
            {
                payload = _json.DeserializeObject(Encoding.UTF8.GetString(body)) as Dictionary<string, object>;
            }
            catch
            {
                ProxyStream(ctx, body);
                return;
            }

            if (payload == null)
            {
                ProxyStream(ctx, body);
                return;
            }

            object mv;
            string requested = (payload.TryGetValue("model", out mv) ? mv : null) as string;

            if (requested != Program.PoolId)
            {
                ProxyStream(ctx, body);
                return;
            }

            string session = SessionFingerprint(payload);
            string remembered = State.Get(session);

            // 调度器按「记忆优先 + 额度排序 + 冷却排除」给出尝试顺序
            List<MemberHealth> order = Scheduler.BuildOrder(remembered);

            bool stream = false;
            object sv;
            if (payload.TryGetValue("stream", out sv) && sv is bool)
            {
                stream = (bool)sv;
            }

            for (int i = 0; i < order.Count; i++)
            {
                MemberHealth member = order[i];
                byte[] memberBody = ReplaceModel(payload, member.ModelId);

                if (!stream)
                {
                    int status;
                    List<KeyValuePair<string, string>> headers;
                    byte[] resp = ReadUpstream(ctx, memberBody, out status, out headers);
                    if (status >= 200 && status < 300)
                    {
                        Scheduler.RecordSuccess(member.ModelId);
                        // 仅在来源切换、或有成员额度告急/掉线时附加说明
                        string notice = (State.NotifyOnChange && Scheduler.ShouldNotify(remembered, member.ModelId))
                            ? Scheduler.BuildSwitchNotice(remembered, member.ModelId, session)
                            : null;
                        State.Set(session, member.ModelId, member.Label);
                        if (!string.IsNullOrEmpty(notice))
                        {
                            resp = AppendNoticeToBody(resp, notice);
                        }
                        AppendHeader(headers, "X-Pool-Member", member.ModelId);
                        Write(ctx, status, headers, resp);
                        return;
                    }
                    // 失败：进入冷却，下一轮自动跳过，稍后回归
                    Scheduler.RecordFailure(member.ModelId, "HTTP " + status);
                    continue;
                }

                // 流式：连上就锁定该成员，中途不切换，避免同一轮混用不同来源
                HttpWebRequest req = BuildRequest(ctx, memberBody);
                if (memberBody.Length > 0)
                {
                    req.ContentLength = memberBody.Length;
                    using (Stream s = req.GetRequestStream())
                    {
                        s.Write(memberBody, 0, memberBody.Length);
                    }
                }

                HttpWebResponse streamResp;
                try
                {
                    streamResp = (HttpWebResponse)req.GetResponse();
                }
                catch (WebException wex)
                {
                    streamResp = wex.Response as HttpWebResponse;
                    if (streamResp == null)
                    {
                        Scheduler.RecordFailure(member.ModelId, wex.Message);
                        continue;
                    }
                }

                int code = (int)streamResp.StatusCode;
                if (code >= 200 && code < 300)
                {
                    Scheduler.RecordSuccess(member.ModelId);
                    State.Set(session, member.ModelId, member.Label);
                    using (streamResp)
                    {
                        ctx.Response.StatusCode = code;
                        CopyHeaders(streamResp, ctx.Response);
                        try { ctx.Response.Headers["X-Pool-Member"] = member.ModelId; } catch { }
                        ctx.Response.SendChunked = true;
                        try
                        {
                            using (Stream up = streamResp.GetResponseStream())
                            {
                                byte[] buf = new byte[16384];
                                int n;
                                while ((n = up.Read(buf, 0, buf.Length)) > 0)
                                {
                                    ctx.Response.OutputStream.Write(buf, 0, n);
                                    ctx.Response.OutputStream.Flush();
                                }
                            }
                        }
                        catch { }
                        finally { TryClose(ctx); }
                    }
                    return;
                }

                Scheduler.RecordFailure(member.ModelId, "HTTP " + code);
                streamResp.Close();
            }

            Write(ctx, 502, null, Encoding.UTF8.GetBytes("all pool members failed"));
        }

        /// <summary>
        /// 会话指纹：取自 messages 里第一条 user 消息。
        /// Cursor 每轮都带完整历史，首条消息在整个对话里稳定，可作为「记忆共享」的键。
        /// </summary>
        private static string SessionFingerprint(Dictionary<string, object> payload)
        {
            object msgsObj;
            if (!payload.TryGetValue("messages", out msgsObj))
            {
                return null;
            }
            object[] msgs = msgsObj as object[];
            if (msgs == null)
            {
                return null;
            }
            foreach (object o in msgs)
            {
                Dictionary<string, object> m = o as Dictionary<string, object>;
                if (m == null)
                {
                    continue;
                }
                object roleObj, contentObj;
                if (!m.TryGetValue("role", out roleObj) || !"user".Equals(roleObj as string, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                if (!m.TryGetValue("content", out contentObj))
                {
                    continue;
                }
                string text = contentObj as string;
                if (text == null)
                {
                    // 多段内容（含图片等）取文本部分拼接
                    object[] parts = contentObj as object[];
                    if (parts != null)
                    {
                        StringBuilder sb = new StringBuilder();
                        foreach (object p in parts)
                        {
                            Dictionary<string, object> pd = p as Dictionary<string, object>;
                            object t;
                            if (pd != null && pd.TryGetValue("text", out t) && t is string)
                            {
                                sb.Append((string)t);
                            }
                        }
                        text = sb.ToString();
                    }
                }
                if (!string.IsNullOrEmpty(text))
                {
                    return Hash(text);
                }
                return "first-user-empty";
            }
            return null;
        }

        private static string Hash(string s)
        {
            using (SHA256 sha = SHA256.Create())
            {
                byte[] h = sha.ComputeHash(Encoding.UTF8.GetBytes(s));
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < 16; i++)
                {
                    sb.Append(h[i].ToString("x2"));
                }
                return sb.ToString();
            }
        }

        /// <summary>
        /// 把额度说明并入非流式响应。
        /// 用明显的前缀和分隔，读者一眼能看出这是程序插入的，而不是模型说的话。
        /// 只处理 chat.completion 结构；其它结构原样返回，避免破坏协议。
        /// </summary>
        private byte[] AppendNoticeToBody(byte[] body, string notice)
        {
            try
            {
                object parsed = _json.DeserializeObject(Encoding.UTF8.GetString(body));
                Dictionary<string, object> root = parsed as Dictionary<string, object>;
                if (root == null)
                {
                    return body;
                }
                object choicesObj;
                if (!root.TryGetValue("choices", out choicesObj))
                {
                    return body;
                }
                object[] choices = choicesObj as object[];
                if (choices == null || choices.Length == 0)
                {
                    return body;
                }

                string block = "\n\n---\n" + notice;
                bool changed = false;

                foreach (object co in choices)
                {
                    Dictionary<string, object> choice = co as Dictionary<string, object>;
                    if (choice == null)
                    {
                        continue;
                    }
                    object msgObj;
                    if (!choice.TryGetValue("message", out msgObj))
                    {
                        continue;
                    }
                    Dictionary<string, object> msg = msgObj as Dictionary<string, object>;
                    if (msg == null)
                    {
                        continue;
                    }
                    object contentObj;
                    string content = null;
                    if (msg.TryGetValue("content", out contentObj))
                    {
                        content = contentObj as string;
                    }
                    msg["content"] = (content ?? string.Empty) + block;
                    changed = true;
                }

                if (!changed)
                {
                    return body;
                }
                return Encoding.UTF8.GetBytes(_json.Serialize(root));
            }
            catch
            {
                // 解析失败就不动，保证响应可用
                return body;
            }
        }

        private byte[] ReplaceModel(Dictionary<string, object> payload, string modelId)
        {
            Dictionary<string, object> copy = new Dictionary<string, object>(payload);
            copy["model"] = modelId;
            return Encoding.UTF8.GetBytes(_json.Serialize(copy));
        }

        private static void AppendHeader(List<KeyValuePair<string, string>> headers, string key, string value)
        {
            if (headers == null)
            {
                return;
            }
            for (int i = 0; i < headers.Count; i++)
            {
                if (string.Equals(headers[i].Key, key, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }
            }
            headers.Add(new KeyValuePair<string, string>(key, value));
        }

        // ---------- 透传 ----------

        private void ProxyStream(HttpListenerContext ctx, byte[] body)
        {
            HttpWebRequest req = BuildRequest(ctx, body);
            if (body != null && body.Length > 0)
            {
                req.ContentLength = body.Length;
                using (Stream s = req.GetRequestStream())
                {
                    s.Write(body, 0, body.Length);
                }
            }

            HttpWebResponse resp;
            try
            {
                resp = (HttpWebResponse)req.GetResponse();
            }
            catch (WebException wex)
            {
                resp = wex.Response as HttpWebResponse;
                if (resp == null)
                {
                    Write(ctx, 502, null, Encoding.UTF8.GetBytes("Magpie gateway unavailable"));
                    return;
                }
            }

            using (resp)
            {
                ctx.Response.StatusCode = (int)resp.StatusCode;
                CopyHeaders(resp, ctx.Response);
                ctx.Response.SendChunked = true;
                try
                {
                    using (Stream up = resp.GetResponseStream())
                    {
                        byte[] buf = new byte[16384];
                        int n;
                        while ((n = up.Read(buf, 0, buf.Length)) > 0)
                        {
                            ctx.Response.OutputStream.Write(buf, 0, n);
                            ctx.Response.OutputStream.Flush();
                        }
                    }
                }
                catch { }
                finally { TryClose(ctx); }
            }
        }

        private byte[] ReadUpstream(HttpListenerContext ctx, byte[] body, out int status, out List<KeyValuePair<string, string>> headers)
        {
            headers = new List<KeyValuePair<string, string>>();
            status = 502;

            HttpWebRequest req = BuildRequest(ctx, body);
            if (body != null && body.Length > 0)
            {
                req.ContentLength = body.Length;
                using (Stream s = req.GetRequestStream())
                {
                    s.Write(body, 0, body.Length);
                }
            }

            HttpWebResponse resp;
            try
            {
                resp = (HttpWebResponse)req.GetResponse();
            }
            catch (WebException wex)
            {
                resp = wex.Response as HttpWebResponse;
                if (resp == null)
                {
                    return null;
                }
            }

            using (resp)
            {
                status = (int)resp.StatusCode;
                foreach (string key in resp.Headers.AllKeys)
                {
                    string lower = key.ToLowerInvariant();
                    if (lower == "content-length" || lower == "transfer-encoding" || lower == "connection")
                    {
                        continue;
                    }
                    headers.Add(new KeyValuePair<string, string>(key, resp.Headers[key]));
                }

                using (Stream up = resp.GetResponseStream())
                using (MemoryStream ms = new MemoryStream())
                {
                    byte[] buf = new byte[16384];
                    int n;
                    while ((n = up.Read(buf, 0, buf.Length)) > 0)
                    {
                        ms.Write(buf, 0, n);
                    }
                    return ms.ToArray();
                }
            }
        }

        private static HttpWebRequest BuildRequest(HttpListenerContext ctx, byte[] body)
        {
            string path = ctx.Request.Url.PathAndQuery;
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(Program.UpstreamOrigin + path);
            req.Method = ctx.Request.HttpMethod;
            req.Proxy = null;
            req.Timeout = 300000;
            req.ReadWriteTimeout = 300000;
            req.AllowAutoRedirect = false;
            req.KeepAlive = true;

            foreach (string key in ctx.Request.Headers.AllKeys)
            {
                string lower = key.ToLowerInvariant();
                if (lower == "host" || lower == "connection" || lower == "content-length" || lower.StartsWith("x-pool-"))
                {
                    continue;
                }
                string value = ctx.Request.Headers[key];
                try
                {
                    if (lower == "accept")
                    {
                        req.Accept = value;
                    }
                    else if (lower == "content-type")
                    {
                        req.ContentType = value;
                    }
                    else if (lower == "user-agent")
                    {
                        req.UserAgent = value;
                    }
                    else
                    {
                        req.Headers[key] = value;
                    }
                }
                catch
                {
                }
            }

            return req;
        }

        private static void CopyHeaders(HttpWebResponse resp, HttpListenerResponse outResp)
        {
            foreach (string key in resp.Headers.AllKeys)
            {
                string lower = key.ToLowerInvariant();
                if (lower == "content-length" || lower == "transfer-encoding" || lower == "connection")
                {
                    continue;
                }
                try
                {
                    outResp.Headers[key] = resp.Headers[key];
                }
                catch
                {
                }
            }
        }

        private static void Write(HttpListenerContext ctx, int status, List<KeyValuePair<string, string>> headers, byte[] body)
        {
            ctx.Response.StatusCode = status;
            if (headers != null)
            {
                foreach (KeyValuePair<string, string> h in headers)
                {
                    try
                    {
                        ctx.Response.Headers[h.Key] = h.Value;
                    }
                    catch
                    {
                    }
                }
            }
            if (body == null)
            {
                body = new byte[0];
            }
            ctx.Response.ContentLength64 = body.Length;
            if (body.Length > 0)
            {
                ctx.Response.OutputStream.Write(body, 0, body.Length);
            }
            TryClose(ctx);
        }

        private static void TryClose(HttpListenerContext ctx)
        {
            try { ctx.Response.OutputStream.Close(); } catch { }
            try { ctx.Response.Close(); } catch { }
        }

        public void Dispose()
        {
            _stopping = true;
            try
            {
                _listener.Stop();
                _listener.Close();
            }
            catch
            {
            }
        }
    }

    internal sealed class TrayApp : IDisposable
    {
        private readonly NotifyIcon _icon;
        private readonly ToolStripMenuItem _statusItem;
        private readonly ToolStripMenuItem _gatewayItem;
        private readonly ToolStripMenuItem _poolItem;
        private readonly ToolStripMenuItem _checkItem;
        private readonly ToolStripMenuItem _openMagpieItem;
        private readonly ToolStripMenuItem _copyHintItem;
        private readonly ToolStripMenuItem _exitItem;

        private readonly Icon _okIcon;
        private readonly Icon _badIcon;
        private readonly Icon _busyIcon;

        private GatewayProxy _proxy;
        private System.Threading.Timer _timer;
        private System.Threading.Timer _quotaTimer;
        private int _failures;
        private int _working;
        private int _refreshing;

        public TrayApp()
        {
            _okIcon = BuildDotIcon(Color.FromArgb(46, 160, 67));
            _badIcon = BuildDotIcon(Color.FromArgb(218, 54, 51));
            _busyIcon = BuildDotIcon(Color.FromArgb(210, 153, 34));

            _statusItem = new ToolStripMenuItem("正在检查…") { Enabled = false };
            _gatewayItem = new ToolStripMenuItem("网关：" + Program.ProxyBase) { Enabled = false };
            _poolItem = new ToolStripMenuItem("池：" + Program.PoolMembers.Length + " 个来源") { Enabled = false };
            _checkItem = new ToolStripMenuItem("立即检查网关与额度");
            _openMagpieItem = new ToolStripMenuItem("打开 Magpie 窗口");
            _copyHintItem = new ToolStripMenuItem("复制 Cursor 网关地址");
            _exitItem = new ToolStripMenuItem("退出守护");

            _checkItem.Click += delegate { ManualCheck(); };
            _openMagpieItem.Click += delegate { OpenMagpie(); };
            _copyHintItem.Click += delegate { CopyGateway(); };
            _exitItem.Click += delegate { Application.Exit(); };

            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Items.Add(_statusItem);
            menu.Items.Add(_gatewayItem);
            menu.Items.Add(_poolItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(_checkItem);
            menu.Items.Add(_openMagpieItem);
            menu.Items.Add(_copyHintItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(_exitItem);

            _icon = new NotifyIcon();
            _icon.Icon = _busyIcon;
            _icon.Text = "Magpie 网关守护：启动中";
            _icon.ContextMenuStrip = menu;
            _icon.Visible = true;
            _icon.DoubleClick += delegate { OpenMagpie(); };
        }

        public void Start()
        {
            StartGateway();
            _timer = new System.Threading.Timer(OnTick, null, 0, Program.PollSeconds * 1000);
            _quotaTimer = new System.Threading.Timer(OnQuotaTick, null, 3000, Program.QuotaRefreshSeconds * 1000);
        }

        private void StartGateway()
        {
            if (_proxy != null)
            {
                return;
            }
            GatewayProxy p = new GatewayProxy();
            string error;
            if (p.Start(out error))
            {
                _proxy = p;
                _gatewayItem.Text = "网关：" + Program.ProxyBase + " 运行中";
            }
            else
            {
                p.Dispose();
                _gatewayItem.Text = "网关：端口 " + Program.ProxyPort + " 占用 — " + error;
            }
        }

        // ---------- 额度刷新 ----------

        private void OnQuotaTick(object state)
        {
            if (_proxy == null)
            {
                return;
            }
            if (Interlocked.CompareExchange(ref _refreshing, 1, 0) != 0)
            {
                return;
            }
            try
            {
                RefreshQuotas(_proxy.Scheduler);
                RefreshPoolText();
            }
            catch
            {
            }
            finally
            {
                Interlocked.Exchange(ref _refreshing, 0);
            }
        }

        /// <summary>
        /// 逐个渠道读取额度并归一化。读不到的渠道保持「未知」，不阻断调度。
        /// </summary>
        private static void RefreshQuotas(PoolScheduler scheduler)
        {
            JavaScriptSerializer json = new JavaScriptSerializer();
            HashSet<string> done = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (MemberHealth h in scheduler.All)
            {
                string provider = PoolScheduler.ProviderOf(h.ModelId);
                if (!done.Add(provider))
                {
                    continue;
                }

                string body = RunMagpie("quota " + provider + " --json");
                if (string.IsNullOrEmpty(body))
                {
                    continue;
                }

                object parsed;
                try
                {
                    parsed = json.DeserializeObject(body);
                }
                catch
                {
                    continue;
                }

                double ratio = PoolScheduler.NormalizeQuota(parsed);
                double money = PoolScheduler.ExtractMoney(parsed);
                DateTime? recoverAt = PoolScheduler.ExtractRecovery(parsed);

                foreach (MemberHealth m in scheduler.All)
                {
                    if (!string.Equals(PoolScheduler.ProviderOf(m.ModelId), provider, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }
                    if (ratio >= 0)
                    {
                        m.Ratio = ratio;
                        m.RatioText = ((int)Math.Round(ratio * 100)) + "%";
                    }
                    if (money >= 0)
                    {
                        m.Balance = money;
                        m.BalanceText = "¥" + money.ToString("0.00");
                    }
                    if (recoverAt.HasValue)
                    {
                        m.RecoverAt = recoverAt;
                    }
                }
            }

            scheduler.LastQuotaRefresh = DateTime.UtcNow;
        }

        private static string RunMagpie(string arguments)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(Program.MagpiePath, arguments);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.StandardOutputEncoding = Encoding.UTF8;
                psi.StandardErrorEncoding = Encoding.UTF8;

                using (Process p = Process.Start(psi))
                {
                    string stdout = p.StandardOutput.ReadToEnd();
                    p.StandardError.ReadToEnd();
                    if (!p.WaitForExit(15000))
                    {
                        try { p.Kill(); } catch { }
                        return null;
                    }
                    return stdout;
                }
            }
            catch
            {
                return null;
            }
        }

        // ---------- 网关检查 ----------

        private void ManualCheck()
        {
            if (Interlocked.CompareExchange(ref _working, 1, 0) != 0)
            {
                return;
            }
            SetState(_busyIcon, "Magpie 网关守护：检查中");
            _statusItem.Text = "检查中…";
            try
            {
                string detail;
                bool ok = Program.ProbeGateway(out detail);
                if (_proxy != null)
                {
                    RefreshQuotas(_proxy.Scheduler);
                    RefreshPoolText();
                }
                if (ok)
                {
                    OnHealthy();
                }
                else
                {
                    EnsureGateway();
                }
            }
            finally
            {
                Interlocked.Exchange(ref _working, 0);
            }
        }

        private void OnTick(object state)
        {
            if (Interlocked.CompareExchange(ref _working, 1, 0) != 0)
            {
                return;
            }
            try
            {
                StartGateway();

                string detail;
                if (Program.ProbeGateway(out detail))
                {
                    OnHealthy();
                    _failures = 0;
                    return;
                }

                _failures++;
                if (_failures >= Program.FailuresBeforeRestart)
                {
                    EnsureGateway();
                    _failures = 0;
                }
                else
                {
                    SetState(_busyIcon, "Magpie 网关守护：网关无响应，将重试");
                    _statusItem.Text = "网关无响应，稍后重试";
                }
            }
            catch
            {
            }
            finally
            {
                Interlocked.Exchange(ref _working, 0);
            }
        }

        private void RefreshPoolText()
        {
            if (_proxy == null || _poolItem == null)
            {
                return;
            }
            string last = _proxy.State.LastLabel;
            string summary = _proxy.Scheduler.Summarize();
            if (summary.Length > 160)
            {
                summary = summary.Substring(0, 160) + "…";
            }
            _poolItem.Text = (string.IsNullOrEmpty(last) ? "" : "最近 " + last + "｜") + summary;
        }

        private void OnHealthy()
        {
            _failures = 0;
            SetState(_okIcon, "Magpie 网关守护：已连通");
            _statusItem.Text = DateTime.Now.ToString("HH:mm") + " Magpie 3425 正常";
        }

        private void EnsureGateway()
        {
            SetState(_busyIcon, "Magpie 网关守护：正在恢复网关");
            _statusItem.Text = "正在恢复网关…";

            if (!Program.MagpieRunning())
            {
                if (!Program.StartMagpie())
                {
                    SetState(_badIcon, "Magpie 网关守护：无法启动 Magpie");
                    _statusItem.Text = "无法启动 Magpie，请检查安装路径";
                    return;
                }
            }

            string detail;
            if (Program.WaitForGateway(Program.BootWaitSeconds, out detail))
            {
                OnHealthy();
                _statusItem.Text = "网关已恢复";
            }
            else
            {
                SetState(_badIcon, "Magpie 网关守护：网关启动失败");
                _statusItem.Text = "网关启动失败：" + (string.IsNullOrEmpty(detail) ? "超时" : detail);
            }
        }

        private void OpenMagpie()
        {
            string exe = Program.MagpiePath;
            if (!File.Exists(exe))
            {
                MessageBox.Show("找不到 Magpie：\r\n" + exe, "Magpie 网关守护",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe);
                psi.UseShellExecute = true;
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                MessageBox.Show("无法打开 Magpie：\r\n\r\n" + ex.Message, "Magpie 网关守护",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void CopyGateway()
        {
            string text = Program.ProxyBase + "\r\n" + Program.GatewayKey;
            try
            {
                Clipboard.SetText(text);
                _icon.ShowBalloonTip(4000, "已复制",
                    "Cursor 里填：\r\n" + Program.ProxyBase +
                    "\r\nAPI Key：" + Program.GatewayKey +
                    "\r\n\r\n模型选 " + Program.PoolId + "（" + Program.PoolName + "）",
                    ToolTipIcon.Info);
            }
            catch
            {
                MessageBox.Show("网关地址：\r\n" + Program.ProxyBase +
                    "\r\n\r\nAPI Key：\r\n" + Program.GatewayKey,
                    "Magpie 网关守护", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void SetState(Icon icon, string tooltip)
        {
            if (_icon == null)
            {
                return;
            }
            _icon.Icon = icon;
            if (tooltip.Length > 63)
            {
                tooltip = tooltip.Substring(0, 63);
            }
            _icon.Text = tooltip;
        }

        private static Icon BuildDotIcon(Color color)
        {
            Bitmap bmp = new Bitmap(16, 16);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                using (SolidBrush edge = new SolidBrush(Color.FromArgb(90, 0, 0, 0)))
                {
                    g.FillEllipse(edge, 0, 0, 15, 15);
                }
                using (SolidBrush fill = new SolidBrush(color))
                {
                    g.FillEllipse(fill, 1, 1, 13, 13);
                }
            }
            IntPtr h = bmp.GetHicon();
            Icon icon = Icon.FromHandle(h);
            bmp.Dispose();
            return icon;
        }

        public void Dispose()
        {
            if (_timer != null)
            {
                _timer.Dispose();
                _timer = null;
            }
            if (_quotaTimer != null)
            {
                _quotaTimer.Dispose();
                _quotaTimer = null;
            }
            if (_proxy != null)
            {
                _proxy.Dispose();
                _proxy = null;
            }
            if (_icon != null)
            {
                _icon.Visible = false;
                _icon.Dispose();
            }
        }
    }
}
