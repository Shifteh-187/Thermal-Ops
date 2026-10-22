using System;
using System.Collections.Generic;
using System.IO;
public static class BundledTools {
    public static string IpmiPath(string root){return Path.Combine(root,"Tools","IPMI","ipmitool.exe");}
    public static bool PreferBundled(string root,Dictionary<string,object> config){return config.ContainsKey("UseBundledIpmi")?Convert.ToBoolean(config["UseBundledIpmi"]):File.Exists(IpmiPath(root));}
    public static string ResolveIpmi(string root,Dictionary<string,object> config){
        string configured=config.ContainsKey("IpmiExe")?Convert.ToString(config["IpmiExe"]):"Bundled";string bundled=IpmiPath(root);
        if(PreferBundled(root,config)||configured=="Bundled"||String.IsNullOrWhiteSpace(configured)){if(!File.Exists(bundled))throw new Exception("Bundled IPMI runtime missing; repair the Thermal Ops installation.");return bundled;}
        return configured;
    }
    public static void Validate(string root){foreach(string name in new[]{"ipmitool.exe","cygwin1.dll","cygcrypto-1.1.dll","cyggcc_s-seh-1.dll","cygncursesw-10.dll","cygreadline7.dll","cygz.dll"})if(!File.Exists(Path.Combine(root,"Tools","IPMI",name)))throw new Exception("Missing bundled IPMI component: "+name);foreach(string name in new[]{"RedfishWorker.ps1","Redfish-Control.ps1","Hpe-Redfish.ps1"})if(!File.Exists(Path.Combine(root,name)))throw new Exception("Missing HPE/Redfish component: "+name);}
}
