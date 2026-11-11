using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main()
    {
        string runtime = null;
        try
        {
            runtime = Path.Combine(Path.GetTempPath(), "ChromeSweep-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(runtime);
            Extract(runtime, "ChromeCacheCleaner.ps1");
            Extract(runtime, "ChromeSweep.ico");
            string gui = Extract(runtime, "ChromeCacheCleaner.GUI.ps1");

            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string powershell = Path.Combine(windows, @"System32\WindowsPowerShell\v1.0\powershell.exe");
            var startInfo = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + gui + "\"",
                WorkingDirectory = runtime,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true
            };

            using (Process process = Process.Start(startInfo))
            {
                string errors = process.StandardError.ReadToEnd();
                process.WaitForExit();
                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException(
                        String.IsNullOrWhiteSpace(errors)
                            ? "PowerShell kết thúc với mã lỗi " + process.ExitCode + "."
                            : errors.Trim());
                }
            }
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Chrome Sweep", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            if (runtime != null)
            {
                try
                {
                    File.Delete(Path.Combine(runtime, "ChromeCacheCleaner.GUI.ps1"));
                    File.Delete(Path.Combine(runtime, "ChromeCacheCleaner.ps1"));
                    File.Delete(Path.Combine(runtime, "ChromeSweep.ico"));
                    Directory.Delete(runtime);
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        }
    }

    private static string Extract(string directory, string name)
    {
        string path = Path.Combine(directory, name);
        using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        {
            if (resource == null)
            {
                throw new InvalidOperationException("Thiếu tài nguyên " + name + " trong EXE.");
            }
            using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write))
            {
                resource.CopyTo(output);
            }
        }
        return path;
    }
}