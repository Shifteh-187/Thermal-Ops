using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

public sealed class AppUpdate {
    public Version Version; public string Name,Url,Hash; public long Size;public bool IsBeta;
}
public static class AppUpdates {
    public const bool BetaBuild=true;
    public const string Releases="https://github.com/Shifteh-187/Thermal-Ops/releases";
    public const string Api="https://api.github.com/repos/Shifteh-187/Thermal-Ops/releases/latest";
    public static Version Current {get{return Assembly.GetExecutingAssembly().GetName().Version;}}
    public static bool CheckOnStartup {
        get{return Convert.ToInt32(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Chris Ramsay\Thermal Ops\Updates","CheckOnStartup",1))!=0;}
        set{Registry.SetValue(@"HKEY_CURRENT_USER\Software\Chris Ramsay\Thermal Ops\Updates","CheckOnStartup",value?1:0,RegistryValueKind.DWord);}
    }
    public static bool IncludeBeta {
        get{return Convert.ToInt32(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Chris Ramsay\Thermal Ops\Updates","IncludeBeta",0))!=0;}
        set{Registry.SetValue(@"HKEY_CURRENT_USER\Software\Chris Ramsay\Thermal Ops\Updates","IncludeBeta",value?1:0,RegistryValueKind.DWord);}
    }
    public static string InstallerKind(){
        string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Chris Ramsay\Thermal Ops")){
            if(key!=null&&String.Equals(Convert.ToString(key.GetValue("InstallPath")).TrimEnd('\\'),root,StringComparison.OrdinalIgnoreCase))return "msi";
        }
        if(File.Exists(Path.Combine(root,"unins000.exe")))return "exe";
        return null;
    }
    public static AppUpdate Parse(string json,Version current,string kind,bool includeBeta=false){
        var data=new JavaScriptSerializer{MaxJsonLength=2097152}.Deserialize<Dictionary<string,object>>(json);
        if(Convert.ToBoolean(data["draft"])||Convert.ToBoolean(data["prerelease"])&&!includeBeta)return null;
        string tag=Convert.ToString(data["tag_name"]);
        if(!Regex.IsMatch(tag,@"^v?\d+\.\d+\.\d+$"))throw new InvalidDataException("Unrecognised release version.");
        Version version=new Version(tag.TrimStart('v')+".0");
        if(version<=current)return null;
        var update=new AppUpdate{Version=version,IsBeta=Convert.ToBoolean(data["prerelease"])};
        if(kind==null)return update;
        if(kind!="msi"&&kind!="exe")throw new InvalidDataException("Unknown installer type.");
        string name="Thermal-Ops-Setup-"+version.ToString(3)+"."+kind;
        foreach(var item in (IEnumerable)data["assets"]){
            var asset=(Dictionary<string,object>)item;
            if(Convert.ToString(asset["name"])!=name)continue;
            string url=Convert.ToString(asset["browser_download_url"]),hash=asset.ContainsKey("digest")?Convert.ToString(asset["digest"]):"";
            string expected=Releases+"/download/"+tag+"/"+name;
            long size=Convert.ToInt64(asset["size"]);
            if(url!=expected||!Regex.IsMatch(hash,@"^sha256:[0-9a-fA-F]{64}$")||size<1||size>268435456)throw new InvalidDataException("Release installer could not be verified.");
            update.Name=name;update.Url=url;update.Hash=hash.Substring(7);update.Size=size;return update;
        }
        throw new InvalidDataException("This release does not contain the matching installer yet. Try again later.");
    }
    static HttpWebResponse Open(string url){
        ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;
        var request=(HttpWebRequest)WebRequest.Create(url);request.UserAgent="ThermalOps/"+Current.ToString(3);request.Timeout=30000;request.ReadWriteTimeout=30000;
        var response=(HttpWebResponse)request.GetResponse();
        if(response.ResponseUri.Scheme!="https"){response.Dispose();throw new InvalidDataException("An insecure download redirect was blocked.");}return response;
    }
    public static AppUpdate ParseChannel(string json,Version current,string kind,bool includeBeta){
        var serializer=new JavaScriptSerializer{MaxJsonLength=2097152};var releases=serializer.Deserialize<object[]>(json);Dictionary<string,object> best=null;Version newest=current;
        foreach(var entry in releases){var item=entry as Dictionary<string,object>;if(item==null||Convert.ToBoolean(item["draft"])||Convert.ToBoolean(item["prerelease"])&&!includeBeta)continue;string tag=Convert.ToString(item["tag_name"]);if(!Regex.IsMatch(tag,@"^v?\d+\.\d+\.\d+$"))continue;var version=new Version(tag.TrimStart('v')+".0");if(version>newest){newest=version;best=item;}}
        return best==null?null:Parse(serializer.Serialize(best),current,kind,includeBeta);
    }
    public static AppUpdate Check(string kind){bool beta=IncludeBeta;using(var response=Open(beta?"https://api.github.com/repos/Shifteh-187/Thermal-Ops/releases?per_page=20":Api))using(var reader=new StreamReader(response.GetResponseStream())){
        char[] buffer=new char[2097153];int used=0,n;while(used<buffer.Length&&(n=reader.Read(buffer,used,buffer.Length-used))>0)used+=n;
        if(used==buffer.Length)throw new InvalidDataException("Release information is too large.");string json=new string(buffer,0,used);return beta?ParseChannel(json,Current,kind,true):Parse(json,Current,kind);
    }}
    public static bool HashMatches(string file,string expected){using(var sha=SHA256.Create())using(var input=File.OpenRead(file))return String.Equals(BitConverter.ToString(sha.ComputeHash(input)).Replace("-",""),expected,StringComparison.OrdinalIgnoreCase);}
    public static string Download(AppUpdate update){
        string directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ThermalOps","Updates",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        string path=Path.Combine(directory,update.Name),partial=path+".partial";
        try{
            using(var response=Open(update.Url))using(var input=response.GetResponseStream())using(var output=File.Create(partial)){
                var buffer=new byte[65536];long size=0;int n;
                while((n=input.Read(buffer,0,buffer.Length))>0){size+=n;if(size>update.Size)throw new InvalidDataException("Download size mismatch.");output.Write(buffer,0,n);}
                if(size!=update.Size)throw new InvalidDataException("Incomplete download.");
            }
            if(!HashMatches(partial,update.Hash))throw new InvalidDataException("Download checksum mismatch. Installation was blocked.");
            File.Move(partial,path);return path;
        }catch{if(File.Exists(partial))File.Delete(partial);throw;}
    }
    public static void StartInstallerAfterExit(string installer,string hash){
        string helper=Path.Combine(Path.GetDirectoryName(installer),"ThermalOpsUpdater.exe");
        File.Copy(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ThermalOpsUpdater.exe"),helper,true);
        Process.Start(new ProcessStartInfo(helper,""+Process.GetCurrentProcess().Id+" \""+installer+"\" "+hash){UseShellExecute=false,CreateNoWindow=true});
    }
}
