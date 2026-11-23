// CPSaverLauncher.cs - the tiny program the shortcuts and .bat files run.
// Compiled by install.ps1 into CPSaverLauncher.exe (no console window).
//
//   CPSaverLauncher.exe [open|quick|browse|templates|settings|tray]
//
// If the tray host is already running, it just signals it through a named
// event and exits (instant). Otherwise it starts the host (hidden PowerShell)
// with the command; the host stays in the tray for next time.

using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace CPSaverNative
{
    public static class Launcher
    {
        [STAThread]
        public static int Main(string[] args)
        {
            string cmd = args.Length > 0 ? args[0].TrimStart('-', '/').ToLowerInvariant() : "open";
            if (cmd == "") cmd = "open";
            string dir = AppDomain.CurrentDomain.BaseDirectory;
            string inst = Environment.GetEnvironmentVariable("CPSAVER_INSTANCE");
            string prefix = @"Local\CPSolutionSaver" + (string.IsNullOrEmpty(inst) ? "" : "_" + inst);
            try
            {
                if (cmd != "tray")
                {
                    EventWaitHandle ev;
                    if (EventWaitHandle.TryOpenExisting(prefix + "_cmd_" + cmd, out ev))
                    {
                        using (ev) { ev.Set(); }
                        Log(dir, "signalled running host: " + cmd);
                        return 0;
                    }
                }
                else
                {
                    // already running? nothing to do
                    EventWaitHandle ev;
                    if (EventWaitHandle.TryOpenExisting(prefix + "_cmd_open", out ev)) { ev.Dispose(); return 0; }
                }

                if (cmd == "exit") return 0;   // nothing is running: nothing to close

                string script = Path.Combine(dir, "CPSaver.ps1");
                string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
                var psi = new ProcessStartInfo(ps,
                    "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\" -Tray -Command " + cmd);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WorkingDirectory = dir;
                Process.Start(psi);
                Log(dir, "started host: " + cmd);
                return 0;
            }
            catch (Exception ex)
            {
                Log(dir, "error: " + ex.Message);
                return 1;
            }
        }

        private static void Log(string dir, string msg)
        {
            try
            {
                string data = Environment.GetEnvironmentVariable("CPSAVER_DATA_DIR");
                if (string.IsNullOrEmpty(data)) data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CPSolutionSaver");
                Directory.CreateDirectory(data);
                File.AppendAllText(Path.Combine(data, "launcher.log"), DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "  " + msg + Environment.NewLine);
            }
            catch (Exception) { }
        }
    }
}
