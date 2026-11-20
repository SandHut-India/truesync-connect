using System.Drawing.Printing;
using System.Runtime.InteropServices;
using Windows.Data.Pdf;
using Windows.Storage.Streams;
namespace TrueSync;

static class PdfPrinter
{
    public record Outcome(string State, string Detail);

    public static async Task<Outcome> Print(byte[] bytes, Command command, IProgress<string> progress, CancellationToken token)
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
        doc.DocumentName = "TrueSync-" + command.Id;
        doc.PrintController = new StandardPrintController();
        var settings = doc.PrinterSettings;
        if (o.Copies > Math.Max(1, (int)settings.MaximumCopies))
            throw new InvalidOperationException($"The driver supports up to {Math.Max(1, (int)settings.MaximumCopies)} copies per job.");
        settings.Copies = (short)Math.Clamp(o.Copies, 1, short.MaxValue);
        settings.Collate = o.Copies > 1;
        if (o.Duplex && !settings.CanDuplex)
            throw new InvalidOperationException("This driver does not report automatic two-sided printing. Choose one side or check the driver settings.");
        if (settings.CanDuplex) settings.Duplex = o.Duplex ? Duplex.Vertical : Duplex.Simplex;
        if (o.Color && !settings.SupportsColor)
            throw new InvalidOperationException("This driver does not report colour support. Choose black and white or check its Windows preferences.");
        doc.DefaultPageSettings.Color = o.Color;
        int w = (int)Math.Round(o.Width / 25.4 * 100), h = (int)Math.Round(o.Height / 25.4 * 100);
        var sizes = settings.PaperSizes.Cast<PaperSize>().ToArray();
        static bool Match(PaperSize p, int width, int height) =>
            Math.Abs(p.Width - width) <= 2 && Math.Abs(p.Height - height) <= 2;
        var size = sizes.FirstOrDefault(p => Match(p, w, h));
        var rotated = size == null && sizes.Any(p => Match(p, h, w));
        doc.DefaultPageSettings.PaperSize = size
            ?? sizes.FirstOrDefault(p => Match(p, h, w))
            ?? new PaperSize("TrueSync custom", w, h);
        int margin = (int)Math.Round(o.Margin / 25.4 * 100);
        doc.DefaultPageSettings.Margins = new Margins(margin, margin, margin, margin);
        if (!string.IsNullOrWhiteSpace(o.Tray))
        {
            var source = settings.PaperSources.Cast<PaperSource>().FirstOrDefault(p =>
                string.Equals(p.SourceName?.Trim(), o.Tray.Trim(), StringComparison.OrdinalIgnoreCase));
            doc.DefaultPageSettings.PaperSource = source
                ?? throw new InvalidOperationException("This paper tray is not listed by the driver. Choose a listed tray or clear the tray setting.");
        }
        // Guard against drivers substituting their default for an unsupported custom form.
        void VerifyPage(Rectangle bounds)
        {
            bool requestedSize = Math.Abs(bounds.Width - w) <= 3 && Math.Abs(bounds.Height - h) <= 3;
            bool requestedSizeRotated = Math.Abs(bounds.Width - h) <= 3 && Math.Abs(bounds.Height - w) <= 3;
            if (!requestedSize && !requestedSizeRotated)
                throw new InvalidOperationException($"The printer driver substituted a different paper size. Add {o.Width:0.#} × {o.Height:0.#} mm in Windows printer settings.");
        }
        uint index = 0;
        doc.QueryPageSettings += (_, e) => { using var p = pdf.GetPage(index); e.PageSettings.Landscape = rotated ^ (o.Orientation == "landscape" || (o.Orientation == "auto" && p.Size.Width > p.Size.Height)); };
        doc.PrintPage += (_, e) => { VerifyPage(e.PageBounds); using var page = pdf.GetPage(index); using var bitmap = Render(page, o.Dpi).GetAwaiter().GetResult(); var settings = e.PageSettings; var area = RectangleF.Intersect(new RectangleF(e.MarginBounds.X, e.MarginBounds.Y, e.MarginBounds.Width, e.MarginBounds.Height), settings.PrintableArea); float actualW = (float)(page.Size.Width / 96 * 100), actualH = (float)(page.Size.Height / 96 * 100); float scale = o.Fit ? Math.Min(area.Width / actualW, area.Height / actualH) : 1; float width = actualW * scale, height = actualH * scale; e.Graphics!.DrawImage(bitmap, area.X - settings.HardMarginX + (area.Width - width) / 2, area.Y - settings.HardMarginY + (area.Height - height) / 2, width, height); index++; e.HasMorePages = index < pdf.PageCount; };
        using var cancel = CancellationTokenSource.CreateLinkedTokenSource(token);
        var observe = Task.Run(() => Observe(command.Printer, doc.DocumentName, progress, cancel.Token));
        try
        {
            doc.Print();
            return await observe;
        }
        finally
        {
            cancel.Cancel();
        }
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
    static async Task<Outcome> Observe(string printer, string name, IProgress<string> progress, CancellationToken token)
    {
        int missing = 0;
        bool seen = false;
        string detail = "Waiting for Windows to queue the job.";
        string? lastReported = null;
        DateTime until = DateTime.UtcNow.AddMinutes(3);
        while (DateTime.UtcNow < until)
        {
            var job = ReadJob(printer, name);
            if (job != null)
            {
                seen = true;
                missing = 0;
                if ((job.Flags & (0x4 | 0x100)) != 0) return new("failed", "The Windows queue removed or cancelled this job.");
                if ((job.Flags & 0x80) != 0) return new("printed", "The driver reported that printing finished.");
                detail = JobMessage(job);
            }
            else if (++missing >= (seen ? 12 : 180))
            {
                break;
            }
            if (detail != lastReported)
            {
                progress.Report(detail);
                lastReported = detail;
            }
            await Task.Delay(250, token);
        }
        return new("unconfirmed", $"{detail} Windows did not confirm completion. Check the printer and its queue before retrying.");
    }

    static string JobMessage(SpoolJob job)
    {
        if ((job.Flags & 0x40) != 0) return "The printer reports that it is out of paper.";
        if ((job.Flags & 0x20) != 0) return "The printer reports that it is offline.";
        if ((job.Flags & 1) != 0) return "The print job is paused in the Windows queue.";
        if ((job.Flags & (2 | 0x200 | 0x400)) != 0) return "The printer needs attention. Check paper, toner and the Windows queue.";
        if ((job.Flags & 0x10) != 0) return job.Pages > 0 ? $"Printing · {job.Pages} page(s) reported." : "The driver reports that it is printing.";
        if ((job.Flags & 0x1000) != 0) return "Windows sent the job to the printer.";
        return "The job is in the Windows print queue.";
    }

    sealed record SpoolJob(uint Flags, uint Pages);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct JobInfo
    {
        public uint Id; public IntPtr Printer, Machine, User, Document, Datatype, StatusText; public uint Status, Priority, Position, TotalPages, PagesPrinted; public ushort Year, Month, DayOfWeek, Day, Hour, Minute, Second, Milliseconds;
    }
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool EnumJobs(IntPtr handle, uint first, uint count, uint level, IntPtr buffer, uint size, out uint needed, out uint returned);
    [DllImport("winspool.drv")] static extern bool ClosePrinter(IntPtr handle);
    static SpoolJob? ReadJob(string printer, string name)
    {
        if (!OpenPrinter(printer, out var handle, IntPtr.Zero))
            return null;
        try
        {
            EnumJobs(handle, 0, 1000, 1, IntPtr.Zero, 0, out var needed, out _);
            if (needed == 0 || needed > 16000000) return null;
            var buffer = Marshal.AllocHGlobal((int)needed);
            try
            {
                if (!EnumJobs(handle, 0, 1000, 1, buffer, needed, out _, out var count)) return null;
                for (int i = 0; i < count; i++)
                {
                    var job = Marshal.PtrToStructure<JobInfo>(IntPtr.Add(buffer, i * Marshal.SizeOf<JobInfo>()));
                    // The string belongs to the spooler buffer and must be read before freeing it.
                    if (string.Equals(Marshal.PtrToStringUni(job.Document), name, StringComparison.Ordinal))
                        return new(job.Status, job.PagesPrinted);
                }
                return null;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        finally { ClosePrinter(handle); }
    }
}
