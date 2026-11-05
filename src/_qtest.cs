using System;
namespace MagpieGatewayKeeper {
  internal sealed class PoolMember {
    public readonly string ModelId; public readonly string Label;
    public PoolMember(string id, string label) { ModelId = id; Label = label; }
  }
  class QTest {
    static void Main() {
      Console.OutputEncoding = System.Text.Encoding.UTF8;
      var s = new PoolScheduler(new PoolMember[]{ new PoolMember("a/x","X") });
      var h = s.Get("a/x");
      s.ApplyProfile("a/x", 116000, new[]{"low","high","xhigh"});
      Console.WriteLine("成员档位: low/high/xhigh，窗口 116000");
      Console.WriteLine();
      foreach (var req in new[]{"low","medium","high","xhigh","max","none"}) {
        var mapped = h.MapReasoningLevel(req);
        Console.WriteLine("  请求 {0,-8} -> {1}", req, mapped == null ? "(原生支持，不改)" : mapped);
      }
      Console.WriteLine();
      foreach (var n in new[]{10000, 50000, 100000, 150000, 300000}) {
        Console.WriteLine("  上下文 {0,7} tokens -> {1}", n, h.CanHold(n) ? "可容纳" : "排除");
      }
    }
  }
}