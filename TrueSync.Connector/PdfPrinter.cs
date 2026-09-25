using System.Drawing.Printing;
using System.Runtime.InteropServices;
using Windows.Data.Pdf;
using Windows.Storage.Streams;
namespace TrueSync;

static class PdfPrinter
{
    // JOB_STATUS_* bits from winspool. JOB_STATUS_PRINTING (0x10) is normal progress — never treat as failure.
    const uint StatusError = 2;
    const uint StatusPrinting = 16;
    const uint StatusOffline = 32;
    const uint StatusPaperOut = 64;
    const uint StatusPrinted = 128;
    const uint StatusDeleted = 256;
    const uint StatusBlockedDevQ = 512;
    const uint StatusUserIntervention = 1024;
    const uint StatusComplete = 0x1000;
    const uint FailedBits =
        StatusError
        | StatusOffline
        | StatusPaperOut
        | StatusDeleted
        | StatusBlockedDevQ
        | StatusUserIntervention;
    // Only cancel jobs that cannot resume; offline/paper-out/user-intervention can recover.
    const uint CancelBits = StatusError | StatusDeleted | StatusBlockedDevQ;
    const uint DoneBits = StatusPrinted | StatusComplete;

    public static async Task<string> Print(byte[] bytes, Command command)
    {
        using var input = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(input))
        {
            writer.WriteBytes(bytes);
            await writer.StoreAsync();
            writer.DetachStream();
        }
        input.Seek(0);
        var pdf = await PdfDocument.LoadFromStreamAsync(input);
        using var doc = new PrintDocument();
        var o = command.Options;
        doc.PrinterSettings.PrinterName = command.Printer;
        if (!doc.PrinterSettings.IsValid)
            throw new InvalidOperationException("Printer unavailable");
        // Drivers frequently misreport CanDuplex/SupportsColor and tray names, so every
        // capability-dependent setting is applied best effort and never blocks the job.
        doc.DocumentName = "TrueSync-" + command.Id;
        doc.PrintController = new StandardPrintController();
        Apply(() => doc.PrinterSettings.Copies = (short)Math.Clamp(o.Copies, 1, short.MaxValue));
        Apply(() => doc.PrinterSettings.Collate = true);
        Apply(() => doc.PrinterSettings.Duplex = o.Duplex ? Duplex.Vertical : Duplex.Simplex);
        Apply(() => doc.DefaultPageSettings.Color = o.Color);
        int w = (int)Math.Round(o.Width / 25.4 * 100), h = (int)Math.Round(o.Height / 25.4 * 100);
        Apply(() => doc.DefaultPageSettings.PaperSize = doc.PrinterSettings.PaperSizes.Cast<PaperSize>().FirstOrDefault(p => Math.Abs(p.Width - w) < 3 && Math.Abs(p.Height - h) < 3) ?? new PaperSize("TrueSync custom", w, h));
        int margin = (int)Math.Round(o.Margin / 25.4 * 100);
        Apply(() => doc.DefaultPageSettings.Margins = new Margins(margin, margin, margin, margin));
        if (o.Tray.Length > 0)
            Apply(() =>
            {
                var source = doc.PrinterSettings.PaperSources.Cast<PaperSource>().FirstOrDefault(p => string.Equals(p.SourceName?.Trim(), o.Tray.Trim(), StringComparison.OrdinalIgnoreCase));
                if (source != null)
                    doc.DefaultPageSettings.PaperSource = source;
            });
        uint index = 0;
        doc.QueryPageSettings += (_, e) => { using var p = pdf.GetPage(index); e.PageSettings.Landscape = o.Orientation == "landscape" || (o.Orientation == "auto" && p.Size.Width > p.Size.Height); };
        doc.PrintPage += (_, e) => { using var page = pdf.GetPage(index); using var bitmap = Render(page, o.Dpi).GetAwaiter().GetResult(); var settings = e.PageSettings; var area = RectangleF.Intersect(new RectangleF(e.MarginBounds.X, e.MarginBounds.Y, e.MarginBounds.Width, e.MarginBounds.Height), settings.PrintableArea); float actualW = (float)(page.Size.Width / 96 * 100), actualH = (float)(page.Size.Height / 96 * 100); float scale = o.Fit ? Math.Min(area.Width / actualW, area.Height / actualH) : 1; float width = actualW * scale, height = actualH * scale; e.Graphics!.DrawImage(bitmap, area.X - settings.HardMarginX + (area.Width - width) / 2, area.Y - settings.HardMarginY + (area.Height - height) / 2, width, height); index++; e.HasMorePages = index < pdf.PageCount; };
        using var cancel = new CancellationTokenSource();
        // Snapshot existing spooler jobs so we can bind to the TrueSync job after Print starts.
        var before = SnapshotIds(command.Printer);
        var observe = Observe(command.Printer, doc.DocumentName, before, cancel.Token);
        try
        {
            doc.Print();
            return await observe;
        }
        finally { cancel.Cancel(); }
    }
    static void Apply(Action setting)
    {
        try { setting(); }
        catch {/* The driver rejected this preference; print with its own default. */}
    }
    static async Task<Bitmap> Render(PdfPage page, int dpi)
    {
        using var stream = new InMemoryRandomAccessStream();
        double factor = Math.Min(dpi / 96d, Math.Sqrt(12000000 / (page.Size.Width * page.Size.Height)));
        await page.RenderToStreamAsync(stream, new PdfPageRenderOptions { DestinationWidth = (uint)Math.Max(1, page.Size.Width * factor), DestinationHeight = (uint)Math.Max(1, page.Size.Height * factor) });
        stream.Seek(0);
        using var reader = new DataReader(stream);
        await reader.LoadAsync((uint)stream.Size);
        byte[] bytes = new byte[(int)stream.Size];
        reader.ReadBytes(bytes);
        using var memory = new MemoryStream(bytes);
        using var image = Image.FromStream(memory);
        return new Bitmap(image);
    }
    static async Task<string> Observe(string printer, string name, HashSet<uint> before, CancellationToken token)
    {
        bool seen = false;
        int missing = 0;
        uint? boundId = null;
        uint lastPagesPrinted = 0;
        // Allow the spooler time to create the job after Print() returns pages to GDI.
        for (int i = 0; i < 720; i++)
        {
            var state = ReadStatus(printer, name, before, ref boundId, out var pagesPrinted, out var totalPages);
            if (pagesPrinted > lastPagesPrinted)
                lastPagesPrinted = pagesPrinted;
            if (state is uint value)
            {
                seen = true;
                missing = 0;
                if ((value & FailedBits) != 0)
                    return "failed";
                if ((value & DoneBits) != 0)
                    return "printed";
                // Still spooling or printing — keep waiting.
                _ = StatusPrinting;
            }
            else
            {
                missing++;
                // Job vanished after we saw progress: treat as printed (Windows clears the queue by default).
                if (seen && missing >= 12)
                    return lastPagesPrinted > 0 || boundId != null ? "printed" : "unconfirmed";
                // Give the job ~45s to appear before giving up.
                if (!seen && i >= 180)
                    return "unconfirmed";
            }
            await Task.Delay(250, token);
        }
        return seen && lastPagesPrinted > 0 ? "printed" : "unconfirmed";
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct JobInfo
    {
        public uint Id; public IntPtr Printer, Machine, User, Document, Datatype, StatusText; public uint Status, Priority, Position, TotalPages, PagesPrinted; public ushort Year, Month, DayOfWeek, Day, Hour, Minute, Second, Milliseconds;
    }
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool EnumJobs(IntPtr handle, uint first, uint count, uint level, IntPtr buffer, uint size, out uint needed, out uint returned);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool SetJob(IntPtr handle, uint job, uint level, IntPtr info, uint command);
    [DllImport("winspool.drv")] static extern bool ClosePrinter(IntPtr handle);
    static HashSet<uint> SnapshotIds(string printer)
    {
        var ids = new HashSet<uint>();
        if (!OpenPrinter(printer, out var handle, IntPtr.Zero))
            return ids;
        try
        {
            foreach (var j in EnumerateJobs(handle))
                ids.Add(j.Id);
        }
        finally { ClosePrinter(handle); }
        return ids;
    }
    static uint? ReadStatus(string printer, string name, HashSet<uint> before, ref uint? boundId, out uint pagesPrinted, out uint totalPages)
    {
        pagesPrinted = 0;
        totalPages = 0;
        if (!OpenPrinter(printer, out var handle, IntPtr.Zero))
            return null;
        try
        {
            foreach (var j in EnumerateJobs(handle))
            {
                var document = Marshal.PtrToStringUni(j.Document) ?? "";
                var isOurs =
                    (boundId is uint id && j.Id == id)
                    || document == name
                    || (document.StartsWith("TrueSync-", StringComparison.Ordinal) && !before.Contains(j.Id));
                if (!isOurs)
                    continue;
                boundId ??= j.Id;
                pagesPrinted = j.PagesPrinted;
                totalPages = j.TotalPages;
                if ((j.Status & CancelBits) != 0)
                    SetJob(handle, j.Id, 0, IntPtr.Zero, 3);
                return j.Status;
            }
        }
        finally { ClosePrinter(handle); }
        return null;
    }
    static List<JobInfo> EnumerateJobs(IntPtr handle)
    {
        var list = new List<JobInfo>();
        EnumJobs(handle, 0, 1000, 1, IntPtr.Zero, 0, out var needed, out _);
        if (needed == 0 || needed > 16000000)
            return list;
        var buffer = Marshal.AllocHGlobal((int)needed);
        try
        {
            if (!EnumJobs(handle, 0, 1000, 1, buffer, needed, out _, out var count))
                return list;
            for (int i = 0; i < count; i++)
                list.Add(Marshal.PtrToStructure<JobInfo>(IntPtr.Add(buffer, i * Marshal.SizeOf<JobInfo>())));
        }
        finally { Marshal.FreeHGlobal(buffer); }
        return list;
    }
}
