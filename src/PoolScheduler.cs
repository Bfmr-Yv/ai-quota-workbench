// 池调度插件：额度感知 + 故障冷却 + 记忆互通
//
// 与 MagpieGatewayKeeper.cs 一起编译。职责边界：
//   - 定时读取各渠道额度，换算成统一的健康分
//   - 健康分低的成员降权，额度耗尽的成员暂时退出调度
//   - 请求失败时立即冷却该成员，冷却到期自动回归
//   - 同一对话优先复用上次成功的成员，做到无感切换
//
// 额度格式在各渠道间差异很大（数值窗口 / 文本窗口 / 金额），这里统一归一化。
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace MagpieGatewayKeeper
{
    /// <summary>
    /// 单个池成员的运行状态与额度快照。
    /// </summary>
    internal sealed class MemberHealth
    {
        public string ModelId;
        public string Label;
        public string Provider;

        // 额度健康度：0 = 耗尽，1 = 满额，-1 = 未知（读不到）
        public double Ratio = -1;
        public string RatioText = "未知";

        // 单位：DeepSeek 用金额，其它用积分/额度比例
        public double Balance = -1;
        public string BalanceText = "未知";

        // 额度重置时间，用于「明天可回复」这类提示
        public DateTime? RecoverAt;

        // 失败冷却
        public DateTime CooldownUntil = DateTime.MinValue;
        public int ConsecutiveFailures;
        // 池内声明顺序，作为同分时的稳定决胜条件
        public int Order;
        public string LastError;

        public bool InCooldown
        {
            get { return DateTime.UtcNow < CooldownUntil; }
        }

        /// <summary>
        /// 排序用的权重。越大越优先。额度越低权重越低，冷却中降到底。
        /// </summary>
        public double Score
        {
            get
            {
                if (InCooldown)
                {
                    return -1000;
                }
                // 额度未知的成员放在已知健康的成员之后、低额度成员之前
                double baseScore = Ratio < 0 ? 0.5 : Ratio;
                // 连续失败少量扣分，避免抖动
                return baseScore - (0.05 * Math.Min(ConsecutiveFailures, 3));
            }
        }
    }

    /// <summary>
    /// 额度读取与调度的总控。
    /// </summary>
    internal sealed class PoolScheduler
    {
        // 低于这个比例的成员不再作为首选
        internal const double LowWatermark = 0.10;
        // 首次失败后的冷却时长，连续失败会翻倍
        internal static readonly TimeSpan BaseCooldown = TimeSpan.FromSeconds(30);
        internal static readonly TimeSpan MaxCooldown = TimeSpan.FromMinutes(10);

        private readonly Dictionary<string, MemberHealth> _byModel =
            new Dictionary<string, MemberHealth>(StringComparer.OrdinalIgnoreCase);
        private readonly object _lock = new object();

        public DateTime LastQuotaRefresh = DateTime.MinValue;

        public PoolScheduler(IEnumerable<PoolMember> members)
        {
            foreach (PoolMember m in members)
            {
                MemberHealth h = new MemberHealth();
                h.ModelId = m.ModelId;
                h.Label = m.Label;
                h.Provider = ProviderOf(m.ModelId);
                _byModel[m.ModelId] = h;
            }
        }

        public static string ProviderOf(string modelId)
        {
            if (string.IsNullOrEmpty(modelId))
            {
                return string.Empty;
            }
            int slash = modelId.IndexOf('/');
            return slash > 0 ? modelId.Substring(0, slash) : modelId;
        }

        public MemberHealth Get(string modelId)
        {
            lock (_lock)
            {
                MemberHealth h;
                return _byModel.TryGetValue(modelId, out h) ? h : null;
            }
        }

        public IEnumerable<MemberHealth> All
        {
            get
            {
                lock (_lock)
                {
                    return new List<MemberHealth>(_byModel.Values);
                }
            }
        }

        /// <summary>
        /// 按「记忆优先 + 额度排序 + 冷却排除」给出本次尝试顺序。
        /// remembered 是同一对话上次成功的成员，只要它健康就排最前，保证无感。
        /// </summary>
        public List<MemberHealth> BuildOrder(string remembered)
        {
            List<MemberHealth> list = new List<MemberHealth>(All);

            // 分数相同时按池内声明顺序决定先后。
            // .NET 的 List<T>.Sort 不稳定，只比分数会让同分成员的顺序随机漂移，
            // 破坏「按优先级」的语义，所以显式加上序号作为决胜条件。
            for (int i = 0; i < list.Count; i++)
            {
                list[i].Order = i;
            }

            list.Sort(delegate (MemberHealth a, MemberHealth b)
            {
                int c = b.Score.CompareTo(a.Score);
                return c != 0 ? c : a.Order.CompareTo(b.Order);
            });

            if (!string.IsNullOrEmpty(remembered))
            {
                int idx = list.FindIndex(delegate (MemberHealth h)
                {
                    return string.Equals(h.ModelId, remembered, StringComparison.OrdinalIgnoreCase);
                });
                // 只有在记忆成员仍然健康时才优先它，避免坚持用一个快耗尽的来源
                if (idx > 0 && list[idx].Score > -1000 && list[idx].Ratio >= LowWatermark)
                {
                    MemberHealth h = list[idx];
                    list.RemoveAt(idx);
                    list.Insert(0, h);
                }
                else if (idx > 0)
                {
                    // 记忆成员已不可用：不再排前面，但也不移除，仅作为后备
                    MemberHealth h = list[idx];
                    list.RemoveAt(idx);
                    list.Add(h);
                }
            }

            return list;
        }

        /// <summary>
        /// 记录一次成功：清零失败计数。
        /// </summary>
        public void RecordSuccess(string modelId)
        {
            MemberHealth h = Get(modelId);
            if (h == null)
            {
                return;
            }
            lock (_lock)
            {
                h.ConsecutiveFailures = 0;
                h.CooldownUntil = DateTime.MinValue;
                h.LastError = null;
            }
        }

        /// <summary>
        /// 记录一次失败：进入冷却，连续失败指数退避。
        /// </summary>
        public void RecordFailure(string modelId, string error)
        {
            MemberHealth h = Get(modelId);
            if (h == null)
            {
                return;
            }
            lock (_lock)
            {
                h.ConsecutiveFailures++;
                h.LastError = error;
                double factor = Math.Pow(2, Math.Min(h.ConsecutiveFailures - 1, 5));
                TimeSpan cd = TimeSpan.FromTicks((long)Math.Min(
                    BaseCooldown.Ticks * factor, MaxCooldown.Ticks));
                h.CooldownUntil = DateTime.UtcNow.Add(cd);
            }
        }

        // ---------- 额度归一化 ----------

        /// <summary>
        /// 把一家渠道的 quota JSON 归一化成 0..1 的比例。
        /// 各渠道窗口结构不同，这里逐类处理：
        ///   - 数值窗口（有 limit / used）：按剩余比例
        ///   - 文本窗口（text=true，如 Loomy '4994 credits'）：取最大可用数
        ///   - 金额窗口（如 DeepSeek '¥27.23'）：记录金额，比例视为未知
        /// 返回 -1 表示无法判断。
        /// </summary>
        public static double NormalizeQuota(object parsed)
        {
            List<object> accounts = AsList(parsed);
            if (accounts.Count == 0)
            {
                return -1;
            }

            double best = -1;

            foreach (object ao in accounts)
            {
                Dictionary<string, object> acct = ao as Dictionary<string, object>;
                if (acct == null)
                {
                    continue;
                }
                object errObj;
                if (acct.TryGetValue("error", out errObj) && errObj != null
                    && !string.IsNullOrEmpty(errObj.ToString()))
                {
                    // 这家读不到额度，无法预判
                    continue;
                }

                object winsObj;
                if (acct.TryGetValue("windows", out winsObj))
                {
                    foreach (object wo in AsList(winsObj))
                    {
                        Dictionary<string, object> w = wo as Dictionary<string, object>;
                        if (w == null)
                        {
                            continue;
                        }

                        // 1) 数值窗口
                        double limit = Num(w, "limit");
                        double used = Num(w, "used");
                        if (limit > 0 && used >= 0)
                        {
                            double r = (limit - used) / limit;
                            if (r > best)
                            {
                                best = r;
                            }
                            continue;
                        }

                        // 2) 文本窗口：'4994 credits' / '5000 credits'
                        string disp = Str(w, "display");
                        if (!string.IsNullOrEmpty(disp))
                        {
                            double n = ExtractLeadingNumber(disp);
                            if (n >= 0)
                            {
                                // 文本窗口没有上限，按「有余额即可用」处理，
                                // 但余额为 0 时视为耗尽
                                double r = n <= 0 ? 0 : 1.0;
                                if (r > best)
                                {
                                    best = r;
                                }
                            }
                        }
                    }
                }
            }

            return best;
        }

        /// <summary>
        /// 从金额字符串里取出数值，例如 '¥27.23 · $0.00' -> 27.23。
        /// </summary>
        public static double ExtractMoney(object parsed)
        {
            List<object> accounts = AsList(parsed);
            foreach (object ao in accounts)
            {
                Dictionary<string, object> acct = ao as Dictionary<string, object>;
                if (acct == null)
                {
                    continue;
                }
                string bal = Str(acct, "balance");
                if (!string.IsNullOrEmpty(bal))
                {
                    double v = ExtractLeadingNumber(bal);
                    if (v >= 0)
                    {
                        return v;
                    }
                }
            }
            return -1;
        }

        /// <summary>
        /// 从额度 JSON 里取出最早的重置时间。
        /// 优先 resetsAt（窗口重置），没有就用 runsOutAt（按当前速度耗尽时间）。
        /// 各渠道给的是 ISO 8601（带 Z 或偏移），统一转成本地时间。
        /// </summary>
        public static DateTime? ExtractRecovery(object parsed)
        {
            DateTime? best = null;
            foreach (DateTime? candidate in new[] { ExtractTimeField(parsed, "resetsAt"), ExtractTimeField(parsed, "runsOutAt") })
            {
                if (!candidate.HasValue)
                {
                    continue;
                }
                if (!best.HasValue || candidate.Value < best.Value)
                {
                    best = candidate;
                }
            }
            return best;
        }

        private static DateTime? ExtractTimeField(object parsed, string field)
        {
            DateTime? best = null;
            foreach (object ao in AsList(parsed))
            {
                Dictionary<string, object> acct = ao as Dictionary<string, object>;
                if (acct == null)
                {
                    continue;
                }
                object winsObj;
                if (!acct.TryGetValue("windows", out winsObj))
                {
                    continue;
                }
                foreach (object wo in AsList(winsObj))
                {
                    Dictionary<string, object> w = wo as Dictionary<string, object>;
                    if (w == null)
                    {
                        continue;
                    }
                    string raw = Str(w, field);
                    if (string.IsNullOrEmpty(raw))
                    {
                        continue;
                    }
                    DateTime parsedTime;
                    if (DateTime.TryParse(raw, CultureInfo.InvariantCulture,
                            DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out parsedTime))
                    {
                        // JSON 里是 UTC，转成本地时间用于显示
                        DateTime local = parsedTime.ToLocalTime();
                        if (!best.HasValue || local < best.Value)
                        {
                            best = local;
                        }
                    }
                }
            }
            return best;
        }

        private static double ExtractLeadingNumber(string s)
        {
            if (string.IsNullOrEmpty(s))
            {
                return -1;
            }
            Match m = Regex.Match(s, "([0-9]+(?:\\.[0-9]+)?)");
            if (!m.Success)
            {
                return -1;
            }
            double v;
            if (double.TryParse(m.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out v))
            {
                return v;
            }
            return -1;
        }

        private static List<object> AsList(object o)
        {
            List<object> list = new List<object>();
            if (o == null)
            {
                return list;
            }
            object[] arr = o as object[];
            if (arr != null)
            {
                list.AddRange(arr);
                return list;
            }
            list.Add(o);
            return list;
        }

        private static double Num(Dictionary<string, object> d, string key)
        {
            object v;
            if (!d.TryGetValue(key, out v) || v == null)
            {
                return -1;
            }
            if (v is double)
            {
                return (double)v;
            }
            if (v is int)
            {
                return (int)v;
            }
            if (v is long)
            {
                return (long)v;
            }
            double r;
            if (double.TryParse(v.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out r))
            {
                return r;
            }
            return -1;
        }

        private static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            if (!d.TryGetValue(key, out v) || v == null)
            {
                return null;
            }
            return v as string ?? v.ToString();
        }

        /// <summary>
        /// 托盘里展示的一行摘要。
        /// </summary>
        public string Summarize()
        {
            List<MemberHealth> list = new List<MemberHealth>(All);
            for (int i = 0; i < list.Count; i++) { list[i].Order = i; }
            list.Sort(delegate (MemberHealth a, MemberHealth b)
            {
                int c = b.Score.CompareTo(a.Score);
                return c != 0 ? c : a.Order.CompareTo(b.Order);
            });

            StringBuilder sb = new StringBuilder();
            foreach (MemberHealth h in list)
            {
                if (sb.Length > 0)
                {
                    sb.Append("  ");
                }
                sb.Append(h.Label);
                if (h.InCooldown)
                {
                    sb.Append("(冷却)");
                }
                else if (h.Ratio >= 0)
                {
                    sb.Append("(").Append(PercentText(h)).Append(")");
                }
            }
            return sb.ToString();
        }

        // ---------- 切换提示 ----------

        /// <summary>
        /// 生成一次切换说明。只在「本轮与上一轮来源不同」或缺额时才输出，
        /// 让调用方不必关心具体格式。
        /// </summary>
        /// <summary>
        /// 判断这次是否值得提示。
        /// 只在两种情况下输出：来源发生切换，或有成员额度低于阈值 / 处于冷却。
        /// 全部健康且同源时返回 null，避免每条回复都附带噪音。
        /// </summary>
        public bool ShouldNotify(string previous, string current)
        {
            // 来源切换了一定要说，用户需要知道换了地方
            if (!string.IsNullOrEmpty(previous) && !string.Equals(previous, current, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
            // 有成员额度告急或掉了，也值得说一次
            foreach (MemberHealth h in All)
            {
                if (h.InCooldown)
                {
                    return true;
                }
                if (h.Ratio >= 0 && h.Ratio < LowWatermark)
                {
                    return true;
                }
            }
            return false;
        }

        public string BuildSwitchNotice(string previous, string current, string session)
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("[额度提示] ");

            if (!string.IsNullOrEmpty(previous) && !string.Equals(previous, current, StringComparison.OrdinalIgnoreCase))
            {
                MemberHealth prev = Get(previous);
                string prevLabel = prev != null ? prev.Label : previous;
                MemberHealth cur = Get(current);
                string curLabel = cur != null ? cur.Label : current;

                sb.Append(prevLabel).Append(" 已结束");
                if (prev != null && prev.Ratio >= 0)
                {
                    sb.Append("（剩 ").Append(PercentText(prev)).Append('）');
                }
                string back = prev != null ? RecoveryHint(prev) : null;
                if (!string.IsNullOrEmpty(back))
                {
                    sb.Append("，").Append(back);
                }
                sb.Append("。已切到 ").Append(curLabel);
                if (cur != null && cur.Ratio >= 0)
                {
                    sb.Append("（剩 ").Append(PercentText(cur)).Append('）');
                    // 新来源本身也接近耗尽时说清楚，避免误以为额度充足
                    if (cur.Ratio < LowWatermark)
                    {
                        sb.Append("，它也快用完了");
                    }
                }
                sb.Append('。');
            }
            else
            {
                MemberHealth cur = Get(current);
                string curLabel = cur != null ? cur.Label : current;
                sb.Append("本条走 ").Append(curLabel);
                if (cur != null && cur.Ratio >= 0)
                {
                    sb.Append("（剩 ").Append(PercentText(cur)).Append('）');
                }
                sb.Append('。');
            }

            // 附上其余仍可用的来源，各带剩余量与恢复时间
            List<MemberHealth> others = new List<MemberHealth>();
            foreach (MemberHealth h in All)
            {
                if (string.Equals(h.ModelId, current, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                others.Add(h);
            }
            for (int i = 0; i < others.Count; i++)
            {
                others[i].Order = i;
            }
            others.Sort(delegate (MemberHealth a, MemberHealth b)
            {
                int c = b.Score.CompareTo(a.Score);
                return c != 0 ? c : a.Order.CompareTo(b.Order);
            });

            if (others.Count > 0)
            {
                sb.Append(" 其余：");
                for (int i = 0; i < others.Count; i++)
                {
                    MemberHealth h = others[i];
                    if (i > 0)
                    {
                        sb.Append('；');
                    }
                    sb.Append(h.Label);
                    if (h.InCooldown)
                    {
                        sb.Append(" 冷却中");
                    }
                    else if (h.Ratio >= 0)
                    {
                        sb.Append(' ').Append(PercentText(h));
                    }
                    else if (h.Balance >= 0)
                    {
                        sb.Append(' ').Append(h.BalanceText);
                    }
                    else
                    {
                        sb.Append(" 未知");
                    }
                    string back = RecoveryHint(h);
                    if (!string.IsNullOrEmpty(back))
                    {
                        sb.Append('（').Append(back).Append('）');
                    }
                }
                sb.Append('。');
            }

            return sb.ToString();
        }

        /// <summary>
        /// 用自然语言描述某个成员的恢复时间。
        /// 依据窗口的 resetsAt / runsOutAt，转成「明天」「3 小时后」「1 个月后」等。
        /// </summary>
        public static string RecoveryHint(MemberHealth h)
        {
            if (h == null)
            {
                return null;
            }
            if (!h.RecoverAt.HasValue)
            {
                return null;
            }
            TimeSpan span = h.RecoverAt.Value - DateTime.Now;
            if (span.TotalMinutes <= 0)
            {
                return "即将恢复";
            }
            string when = Humanize(span);
            if (h.InCooldown)
            {
                return when + "后恢复";
            }
            // 说明这是额度重置时间，区别于失败冷却
            return when + "重置后恢复";
        }

        /// <summary>
        /// 由 Ratio 实时算出百分比文本，避免缓存字段与数值不同步。
        /// </summary>
        internal static string PercentText(MemberHealth h)
        {
            if (h == null || h.Ratio < 0)
            {
                return "未知";
            }
            return ((int)Math.Round(h.Ratio * 100)) + "%";
        }

        private static string Humanize(TimeSpan span)
        {
            double days = span.TotalDays;
            if (days >= 1)
            {
                int d = (int)Math.Round(days);
                return d + " 天";
            }
            if (span.TotalHours >= 1)
            {
                return ((int)Math.Round(span.TotalHours)) + " 小时";
            }
            return Math.Max(1, (int)Math.Round(span.TotalMinutes)) + " 分钟";
        }
    }
}
