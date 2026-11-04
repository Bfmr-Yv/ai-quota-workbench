using System; using System.Diagnostics; using System.IO;
class Launcher { [STAThread] static void Main() { var p=new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \""+Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"大肥鱼额度桌宠.ps1")+"\""); p.UseShellExecute=false; p.CreateNoWindow=true; Process.Start(p); } }
