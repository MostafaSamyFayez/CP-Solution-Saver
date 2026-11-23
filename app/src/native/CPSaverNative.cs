// CPSaverNative.cs - small Windows helpers for CP Solution Saver's tray host.
// Compiled once by install.ps1 into CPSaver.Native.dll (C# 5 / .NET Framework 4.x,
// so it builds with the compiler that ships with Windows).
//
//  - HostWindow: a hidden message window that
//      * registers system-wide hotkeys (RegisterHotKey) and raises Command("open"|...)
//      * listens for named events set by CPSaverLauncher.exe and raises Command(name)
//    Commands are always raised on the UI thread.
//  - Dpi.Enable(): makes the process DPI aware so text is sharp on scaled screens.

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace CPSaverNative
{
    public static class Dpi
    {
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

        /// <summary>System DPI awareness: sharp text on scaled screens (Windows Forms scales the layout).</summary>
        public static void Enable()
        {
            try { SetProcessDPIAware(); } catch (Exception) { }
        }
    }

    public class HostWindow : NativeWindow, IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        private const int WM_APP_COMMAND = 0x8000 + 77;

        [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool AllowSetForegroundWindow(int processId);

        public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_NOREPEAT = 0x4000;

        private readonly Dictionary<int, string> hotkeys = new Dictionary<int, string>();
        private readonly List<string> commandNames = new List<string>();
        private readonly List<EventWaitHandle> events = new List<EventWaitHandle>();
        private readonly List<RegisteredWaitHandle> waits = new List<RegisteredWaitHandle>();
        private readonly Queue<string> pending = new Queue<string>();
        private int nextId = 1;

        /// <summary>Raised on the UI thread with the command name (e.g. "open", "quick").</summary>
        public event Action<string> Command;

        public HostWindow()
        {
            CreateHandle(new CreateParams());
        }

        /// <summary>Registers a system-wide hotkey. Returns false if another app already uses it.</summary>
        public bool AddHotkey(string command, uint modifiers, Keys key)
        {
            int id = nextId++;
            if (!RegisterHotKey(Handle, id, modifiers | MOD_NOREPEAT, (uint)key)) return false;
            hotkeys[id] = command;
            return true;
        }

        /// <summary>Listens for the named event "Local\CPSolutionSaver_cmd_{command}" (set by the launcher).</summary>
        public void ListenFor(string command)
        {
            bool created;
            var ev = new EventWaitHandle(false, EventResetMode.AutoReset, EventName(command), out created);
            events.Add(ev);
            commandNames.Add(command);
            string name = command;
            IntPtr hwnd = Handle;
            RegisteredWaitHandle rw = ThreadPool.RegisterWaitForSingleObject(ev, (state, timedOut) =>
            {
                lock (pending) { pending.Enqueue(name); }
                PostMessage(hwnd, WM_APP_COMMAND, IntPtr.Zero, IntPtr.Zero);
            }, null, Timeout.Infinite, false);
            waits.Add(rw);
        }

        /// <summary>CPSAVER_INSTANCE lets a second, separate copy run (used by the tests).</summary>
        public static string Prefix
        {
            get { string i = Environment.GetEnvironmentVariable("CPSAVER_INSTANCE"); return @"Local\CPSolutionSaver" + (string.IsNullOrEmpty(i) ? "" : "_" + i); }
        }
        public static string EventName(string command) { return Prefix + "_cmd_" + command; }
        public static string MutexName { get { return Prefix + "_Host"; } }

        /// <summary>Brings a window to the front (works after a hotkey press).</summary>
        public static void BringToFront(IntPtr hwnd)
        {
            try { AllowSetForegroundWindow(-1); SetForegroundWindow(hwnd); } catch (Exception) { }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                string cmd;
                if (hotkeys.TryGetValue(m.WParam.ToInt32(), out cmd)) Raise(cmd);
                return;
            }
            if (m.Msg == WM_APP_COMMAND)
            {
                while (true)
                {
                    string cmd = null;
                    lock (pending) { if (pending.Count > 0) cmd = pending.Dequeue(); }
                    if (cmd == null) break;
                    Raise(cmd);
                }
                return;
            }
            base.WndProc(ref m);
        }

        private void Raise(string cmd)
        {
            var h = Command;
            if (h != null)
            {
                try { h(cmd); } catch (Exception) { }
            }
        }

        public void Dispose()
        {
            foreach (int id in hotkeys.Keys) UnregisterHotKey(Handle, id);
            hotkeys.Clear();
            foreach (var w in waits) w.Unregister(null);
            foreach (var e in events) e.Dispose();
            waits.Clear(); events.Clear();
            DestroyHandle();
        }
    }
}
