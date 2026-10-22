using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Windows.Forms;
// Runs from the download folder so the installed application files are unlocked.
public static class UpdateLauncher {
    [STAThread] public static int Main(string[] args){
        try{
            if(args.Length!=3)throw new Exception("Invalid update handoff.");
            int pid=int.Parse(args[0]);
            try{using(var app=Process.GetProcessById(pid)){if(!app.WaitForExit(120000))throw new Exception("The dashboard is still running. Update cancelled.");}}catch(ArgumentException){}
            if(MsiActions.CoolingActive())throw new Exception("Another dashboard or cooling worker is still running. Stop it safely before updating.");
            // Recheck the downloaded bytes after the dashboard exits.
            using(var sha=SHA256.Create())using(var file=File.OpenRead(args[1])){
                string actual=BitConverter.ToString(sha.ComputeHash(file)).Replace("-","");
                if(!String.Equals(actual,args[2],StringComparison.OrdinalIgnoreCase))throw new Exception("Installer checksum mismatch.");
            }
            string extension=Path.GetExtension(args[1]);
            if(extension==".msi")Process.Start(new ProcessStartInfo("msiexec.exe","/i \""+args[1]+"\" /norestart"){UseShellExecute=true});
            else if(extension==".exe")Process.Start(new ProcessStartInfo(args[1],"/NORESTART"){UseShellExecute=true});
            else throw new Exception("Unsupported installer format.");
            return 0;
        }catch(Exception ex){MessageBox.Show("The update could not start: "+ex.Message+"\nSetup was not started. Reopen Thermal Ops to check and resume your saved controllers.","Thermal Ops update");return 1;}
    }
}
