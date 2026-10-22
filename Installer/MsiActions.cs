using System;
using System.Diagnostics;
using System.IO;
using System.Management;

public class MsiActions {
    public static bool CoolingActive(){
        foreach(string name in new[]{"ThermalOps","LocalWorker"}){
            var processes=Process.GetProcessesByName(name);
            try{if(processes.Length>0)return true;}finally{foreach(var process in processes)process.Dispose();}
        }
        using(var search=new ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'"))
        using(var rows=search.Get())foreach(ManagementObject row in rows){
            string command=Convert.ToString(row["CommandLine"]);
            if(command.IndexOf("Controller.ps1",StringComparison.OrdinalIgnoreCase)>=0||command.IndexOf("RedfishWorker.ps1",StringComparison.OrdinalIgnoreCase)>=0||command.IndexOf("R730-FanController",StringComparison.OrdinalIgnoreCase)>=0)return true;
        }
        return false;
    }
    public static int Main(string[] args){
        try{
            if(args.Length==1 && args[0]=="check") return CoolingActive()?1:0;
            if(args.Length!=2 || args[0]!="initialize")return 2;
            string directory=args[1];
            string destination=Path.Combine(directory,"settings.json");
            if(!File.Exists(destination))File.Copy(Path.Combine(directory,"settings.default.json"),destination,false);
            return 0;
        }catch{return 1;}
    }
}
