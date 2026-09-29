using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

class ZapretRKN
{
    [STAThread]
    static void Main()
    {
        try
        {
            string exePath = Assembly.GetEntryAssembly().Location;
            string dir = Path.GetDirectoryName(exePath);
            string batPath = Path.Combine(dir, "install.bat");

            if (!File.Exists(batPath))
            {
                MessageBox.Show(
                    "Файл install.bat не найден рядом с ZapretRKN.exe.\n\n" +
                    "Убедитесь, что архив распакован полностью\n" +
                    "и запускаете ZapretRKN.exe из папки проекта.",
                    "ZapretRKN - Ошибка",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                return;
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c \"" + batPath + "\"";
            psi.WorkingDirectory = dir;
            psi.UseShellExecute = true;
            psi.Verb = "runas";

            try
            {
                Process.Start(psi);
            }
            catch (System.ComponentModel.Win32Exception)
            {
                // пользователь отменил UAC - молча выходим
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Ошибка: " + ex.Message, "ZapretRKN",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}