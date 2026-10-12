using System;
using System.Runtime.InteropServices;

namespace ArkResmon
{
    public static class CpuSampler
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime { public uint Low; public uint High; }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);
        private static ulong lastIdle, lastTotal;
        private static bool ready;

        private static ulong Ticks(FileTime value) { return ((ulong)value.High << 32) | value.Low; }

        public static double Read()
        {
            FileTime idle, kernel, user;
            if (!GetSystemTimes(out idle, out kernel, out user)) { ready = false; return double.NaN; }
            ulong idleNow = Ticks(idle);
            ulong totalNow = Ticks(kernel) + Ticks(user);
            double result = double.NaN;
            if (ready && totalNow > lastTotal && idleNow >= lastIdle)
            {
                ulong totalDelta = totalNow - lastTotal;
                ulong idleDelta = idleNow - lastIdle;
                result = Math.Max(0.0, Math.Min(100.0, 100.0 * (1.0 - (double)idleDelta / totalDelta)));
            }
            lastIdle = idleNow; lastTotal = totalNow; ready = true;
            return result;
        }
    }
}
