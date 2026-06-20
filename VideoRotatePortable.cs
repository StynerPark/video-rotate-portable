using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace VideoRotatePortable
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDir, "RotateTagTool.ps1");

            if (!File.Exists(scriptPath))
            {
                MessageBox.Show(
                    "RotateTagTool.ps1 파일을 찾을 수 없습니다.\r\n\r\n" + scriptPath,
                    "VideoRotatePortable",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            psi.Arguments =
                "-NoProfile -STA -ExecutionPolicy Bypass -File " +
                Quote(scriptPath);

            try
            {
                using (var process = Process.Start(psi))
                {
                    if (process != null)
                    {
                        process.WaitForExit();
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "PowerShell 실행에 실패했습니다.\r\n\r\n" + ex.Message,
                    "VideoRotatePortable",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }
    }
}
