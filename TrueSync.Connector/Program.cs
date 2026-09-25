using System.Net.Http.Json;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using System.Drawing.Printing;
using System.Runtime.InteropServices;
namespace TrueSync;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var mutex = new Mutex(true, "Local\\TrueSyncConnector", out bool first);
        if (!first)
        {
            MessageBox.Show("TrueSync Connector is already running. Open it from the system tray.");
            return;
        }
        Application.Run(new ConnectorForm());
    }

}
record Pair(string Id, string Secret, string Code, long ExpiresAt);
record PrintOptions(int Copies, bool Color, bool Duplex, double Width, double Height, string Orientation, bool Fit, double Margin, int Dpi, string Tray);
record Command(string Id, string JobId, string Printer, PrintOptions Options);
record Poll(bool Paired, Command? Command);
record Result(string Id, string ResultValue, string Error);
class ConnectorForm : Form
{
    static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TrueSyncConnector");
    static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    static readonly string ApiBase = Config.ApiBase();
    static readonly string Site = Config.SiteUrl(ApiBase);
    readonly HttpClient http = new() { BaseAddress = new Uri(ApiBase), Timeout = TimeSpan.FromSeconds(110) };
    readonly Label status = new() { AutoSize = false, Width = 490, Height = 125, Text = "Connecting…", Font = new Font("Segoe UI", 12) };
    readonly TextBox code = new() { ReadOnly = true, Width = 360, Font = new Font("Segoe UI", 24, FontStyle.Bold) };
    readonly NotifyIcon tray = new() { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application, Text = "TrueSync Connector", Visible = true };
    Pair? pair; bool closing; bool printing; readonly CancellationTokenSource stop = new();
    public ConnectorForm()
    {
        Text = "TrueSync Connector";
        ClientSize = new Size(550, 415);
        BackColor = Color.FromArgb(247, 249, 244);
        Font = new Font("Segoe UI", 11);
        var layout = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), FlowDirection = FlowDirection.TopDown, WrapContents = false };
        Controls.Add(layout);
        layout.Controls.Add(new Label { Text = "TrueSync. Your printer, connected.", AutoSize = true, Font = new Font("Segoe UI", 18, FontStyle.Bold) });
        layout.Controls.Add(status);
        layout.Controls.Add(code);
        var site = new Button { Text = "Open TrueSync → Printers", AutoSize = true };
        site.Click += (_, _) => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Site) { UseShellExecute = true });
        layout.Controls.Add(site);
        var startup = new CheckBox { Text = "Open automatically when I sign in to Windows", AutoSize = true };
        using (var run = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
        {
            startup.Checked = run?.GetValue("TrueSyncConnector") != null;
        }
        startup.CheckedChanged += (_, _) => { using var run = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"); if (startup.Checked) run.SetValue("TrueSyncConnector", "\"" + Environment.ProcessPath + "\""); else run.DeleteValue("TrueSyncConnector", false); };
        layout.Controls.Add(startup);
        var forget = new Button { Text = "Disconnect this computer", AutoSize = true };
        forget.Click += (_, _) => { if (MessageBox.Show("Stop receiving jobs? Remove this computer in TrueSync → Printers too.", "Disconnect", MessageBoxButtons.YesNo) == DialogResult.Yes) { File.Delete(Path.Combine(Folder, "pair.bin")); closing = true; Close(); } };
        layout.Controls.Add(forget);
        var menu = new ContextMenuStrip();
        menu.Items.Add("Open TrueSync Connector", null, (_, _) => { Show(); WindowState = FormWindowState.Normal; Activate(); });
        menu.Items.Add("Exit", null, (_, _) => { closing = true; Close(); });
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => { Show(); WindowState = FormWindowState.Normal; };
        FormClosing += (_, e) => { if (!closing && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } else { stop.Cancel(); tray.Dispose(); } };
        Shown += async (_, _) => { _ = Heartbeat(); await Loop(); };
    }
    async Task Heartbeat()
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(10000, stop.Token);
                if (printing && pair != null)
                    await Call<JsonElement>("connector/poll", new
                    {
                        ready = false,
                        printers = GetPrinterNames()
                    });
            }
            catch (OperationCanceledException) { break; }
            catch {/* Main loop reports network failures. */}
        }
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PrinterInfo4 { public IntPtr Name, Server; public uint Attributes; }
    [DllImport("winspool.drv", EntryPoint = "EnumPrintersW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool EnumPrinters(uint flags, string? name, uint level, IntPtr buffer, uint size, out uint needed, out uint returned);
    // PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS: local queues plus per-user network queues.
    static string[] EnumSpoolerPrinters()
    {
        try
        {
            EnumPrinters(2 | 4, null, 4, IntPtr.Zero, 0, out var needed, out _);
            if (needed == 0 || needed > 16000000)
                return [];
            var buffer = Marshal.AllocHGlobal((int)needed);
            try
            {
                if (!EnumPrinters(2 | 4, null, 4, buffer, needed, out _, out var count))
                    return [];
                var names = new List<string>((int)count);
                for (int i = 0; i < count; i++)
                {
                    var info = Marshal.PtrToStructure<PrinterInfo4>(IntPtr.Add(buffer, i * Marshal.SizeOf<PrinterInfo4>()));
                    var name = Marshal.PtrToStringUni(info.Name);
                    if (!string.IsNullOrWhiteSpace(name))
                        names.Add(name);
                }
                return names.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        catch { return []; }
    }
    static string[] GetPrinterNames()
    {
        string[] all;
        try
        {
            all = PrinterSettings.InstalledPrinters.Cast<string>().Where(p => !string.IsNullOrWhiteSpace(p)).ToArray();
        }
        catch { all = []; }
        // Some machines return nothing from the managed list even with working queues.
        if (all.Length == 0)
            all = EnumSpoolerPrinters();
        var printers = all.Where(p =>
        {
            var name = p.Trim();
            return !name.Equals("Microsoft Print to PDF", StringComparison.OrdinalIgnoreCase)
                && !name.Equals("Microsoft XPS Document Writer", StringComparison.OrdinalIgnoreCase)
                && !name.Contains("OneNote", StringComparison.OrdinalIgnoreCase)
                && !name.Equals("Fax", StringComparison.OrdinalIgnoreCase);
        }).ToArray();
        // Prefer real printers, but still report every queue so the shop can
        // choose one when only virtual queues are present.
        return printers.Length > 0 ? printers : all;
    }
    static string Describe(Exception e)
    {
        var message = e.Message.Replace('\r', ' ').Replace('\n', ' ').Trim();
        if (message.Length > 100)
            message = message[..100] + "…";
        var code = e is HttpRequestException { StatusCode: { } status } ? " " + (int)status : "";
        return e.GetType().Name + code + (message.Length > 0 ? ": " + message : "");
    }
    void SavePair()
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllBytes(Path.Combine(Folder, "pair.bin"), ProtectedData.Protect(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(pair, Json)), null, DataProtectionScope.CurrentUser));
    }
    async Task<T> Call<T>(string path, object? body = null)
    {
        using var request = new HttpRequestMessage(body == null ? HttpMethod.Get : HttpMethod.Post, path);
        if (pair != null)
            request.Headers.Authorization = new("Bearer", pair.Id + "." + pair.Secret);
        if (body != null)
            request.Content = JsonContent.Create(body, body.GetType(), options: Json);
        using var response = await http.SendAsync(request, stop.Token);
        if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            throw new UnauthorizedAccessException();
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<T>(Json, stop.Token))!;
    }
    async Task Loop()
    {
        Directory.CreateDirectory(Folder);
        try
        {
            var path = Path.Combine(Folder, "pair.bin");
            if (File.Exists(path))
                pair = JsonSerializer.Deserialize<Pair>(ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser), Json);
        }
        catch (Exception e) { status.Text = "Please pair this computer again.\n" + Describe(e); } while (!stop.IsCancellationRequested)
        {
            try
            {
                if (pair == null)
                {
                    pair = await Call<Pair>("connector/pair", new
                    {
                        name = Environment.MachineName
                    });
                    foreach (var old in Directory.GetFiles(Folder, "*.json"))
                        File.Move(old, old + ".orphan", true);
                    SavePair();
                }
                code.Text = pair.Code;
                var printers = GetPrinterNames();
                await FlushResults();
                var poll = await Call<Poll>("connector/poll", new
                {
                    printers
                });
                if (!poll.Paired)
                {
                    status.Text = "In TrueSync → Printers, enter this code to approve this computer once.";
                    code.Visible = true;
                }
                else
                {
                    code.Visible = false;
                    status.Text = $"Connected · {printers.Length} printer(s)\nKeep this app running while your shop is open.";
                    if (poll.Command is { } command)
                    {
                        status.Text = "Printing on " + command.Printer + "…";
                        printing = true;
                        try
                        {
                            await Execute(command);
                        }
                        finally { printing = false; }
                    }
                }
            }
            catch (UnauthorizedAccessException) { pair = null; File.Delete(Path.Combine(Folder, "pair.bin")); status.Text = "Connection removed or code expired. Preparing a new code…"; }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { break; }
            catch (Exception e) { status.Text = "Waiting for internet or TrueSync. Your connection will retry automatically.\n" + Describe(e); }
            try
            {
                await Task.Delay(4000, stop.Token);
            }
            catch (OperationCanceledException) { break; }
        }
    }
    static void WriteResult(string path, Result result)
    {
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(result, Json));
        File.Move(path + ".tmp", path, true);
    }
    async Task Execute(Command c)
    {
        string path = Path.Combine(Folder, c.Id + ".json");
        if (File.Exists(path))
            return;
        var result = new Result(c.Id, "unconfirmed", "Printing was interrupted. Check the pages before retrying.");
        WriteResult(path, result);
        try
        {
            var data = await Call<JsonElement>("connector/file/" + c.Id);
            var bytes = Convert.FromBase64String(data.GetProperty("file").GetString()!);
            var outcome = await Task.Run(() => PdfPrinter.Print(bytes, c), stop.Token);
            result = new(c.Id, outcome, "");
            Array.Clear(bytes);
        }
        catch (Exception e) { result = new(c.Id, "failed", "Check the printer and its Windows queue before retrying. " + Describe(e)); }
        WriteResult(path, result);
        await FlushResults();
    }
    async Task FlushResults()
    {
        foreach (var path in Directory.GetFiles(Folder, "*.json"))
        {
            Result? r = null;
            try { r = JsonSerializer.Deserialize<Result>(File.ReadAllText(path), Json); }
            catch { }
            if (r == null || string.IsNullOrEmpty(r.Id))
            {
                // Unreadable journal entries can never be delivered; park them instead of retrying forever.
                File.Move(path, path + ".orphan", true);
                continue;
            }
            try
            {
                await Call<JsonElement>("connector/result", new
                {
                    id = r.Id,
                    result = r.ResultValue,
                    error = r.Error
                });
            }
            catch (HttpRequestException e) when (e.StatusCode is System.Net.HttpStatusCode.Forbidden or System.Net.HttpStatusCode.NotFound or System.Net.HttpStatusCode.Gone) { /* The server expired or removed this command. Never replay it. */ }
            catch (OperationCanceledException) { throw; }
            catch (UnauthorizedAccessException) { throw; }
            catch (Exception e)
            {
                // Network failure or server error: keep the file so the result is retried.
                status.Text = "Sending the last print result to TrueSync… it will retry automatically.\n" + Describe(e);
                return;
            }
            File.Delete(path);
        }
    }
}

static class Config
{
    const string DefaultApi = "https://truesync-2026.web.app/api/";

    public static string ApiBase()
    {
        var fromEnv = Environment.GetEnvironmentVariable("TRUESYNC_API_BASE");
        if (!string.IsNullOrWhiteSpace(fromEnv))
            return Normalize(fromEnv);
        try
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TrueSyncConnector",
                "config.json");
            if (File.Exists(path))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                if (doc.RootElement.TryGetProperty("apiBase", out var value)
                    && value.GetString() is string configured
                    && !string.IsNullOrWhiteSpace(configured))
                    return Normalize(configured);
            }
        }
        catch
        {
            /* fall back to default */
        }
        return DefaultApi;
    }

    public static string SiteUrl(string apiBase)
    {
        var trimmed = apiBase.TrimEnd('/');
        if (trimmed.EndsWith("/api", StringComparison.OrdinalIgnoreCase))
            trimmed = trimmed[..^4];
        return trimmed.TrimEnd('/') + "/";
    }

    static string Normalize(string value)
    {
        var trimmed = value.Trim().TrimEnd('/');
        if (!trimmed.EndsWith("/api", StringComparison.OrdinalIgnoreCase))
            trimmed += "/api";
        return trimmed + "/";
    }
}
