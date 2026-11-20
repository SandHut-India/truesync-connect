using System.Runtime.InteropServices;

namespace TrueSync;

static class PrinterStatus
{
    [DllImport("winspool.drv", EntryPoint = "OpenPrinterW", CharSet = CharSet.Unicode)]
    static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);

    [DllImport("winspool.drv", EntryPoint = "GetPrinterW")]
    static extern bool GetPrinter(IntPtr handle, uint level, out uint status, uint size, out uint needed);

    [DllImport("winspool.drv")]
    static extern bool ClosePrinter(IntPtr handle);

    public static string Read(string name)
    {
        if (!OpenPrinter(name, out var handle, IntPtr.Zero)) return "Status unavailable";
        try
        {
            return GetPrinter(handle, 6, out var flags, sizeof(uint), out _) ? Describe(flags) : "Status unavailable";
        }
        finally { ClosePrinter(handle); }
    }

    static string Describe(uint flags)
    {
        if ((flags & 0x80) != 0) return "Offline";
        if ((flags & 0x8) != 0) return "Paper jam";
        if ((flags & 0x10) != 0) return "Out of paper";
        if ((flags & 0x400000) != 0) return "Cover open";
        if ((flags & 0x40000) != 0) return "Out of toner";
        if ((flags & 0x800) != 0) return "Output tray full";
        if ((flags & 0x20) != 0) return "Load paper manually";
        if ((flags & 1) != 0) return "Queue paused";
        if ((flags & 0x100042) != 0) return "Needs attention";
        if ((flags & (0x800000 | 0x1000)) != 0) return "Status unavailable";
        if ((flags & 0x400) != 0) return "Printing";
        if ((flags & 0x10000) != 0) return "Warming up";
        if ((flags & 0x4000) != 0) return "Processing";
        if ((flags & 0x200) != 0) return "Busy";
        if ((flags & 0x20000) != 0) return "Toner low";
        if ((flags & 0x1000000) != 0) return "Power saving";
        return flags == 0 ? "No issues reported" : "Check Windows printer status";
    }
}
