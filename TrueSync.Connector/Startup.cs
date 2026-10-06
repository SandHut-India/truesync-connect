using Microsoft.Win32;
using Windows.ApplicationModel;
namespace TrueSync;

// MSIX packages virtualise HKCU\...\Run, so packaged builds must use the manifest's StartupTask instead.
static class Startup
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string Name = "TrueSyncConnector";
    const string TaskId = "TrueSyncConnectorStartup";

    static readonly bool Packaged = IsPackaged();

    static bool IsPackaged()
    {
        try { return Package.Current?.Id != null; }
        catch { return false; }
    }

    public static async Task<bool> IsEnabled()
    {
        if (Packaged)
        {
            var task = await StartupTask.GetAsync(TaskId);
            return task.State is StartupTaskState.Enabled or StartupTaskState.EnabledByPolicy;
        }
        using var run = Registry.CurrentUser.OpenSubKey(RunKey);
        return run?.GetValue(Name) != null;
    }

    public static async Task<bool> Set(bool enabled)
    {
        if (Packaged)
        {
            var task = await StartupTask.GetAsync(TaskId);
            if (!enabled)
            {
                task.Disable();
                return false;
            }
            var state = await task.RequestEnableAsync();
            return state is StartupTaskState.Enabled or StartupTaskState.EnabledByPolicy;
        }
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(Name, "\"" + Environment.ProcessPath + "\"");
        else key.DeleteValue(Name, false);
        return enabled;
    }
}
