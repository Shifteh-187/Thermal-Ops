using System;
using System.Collections.Generic;
using System.IO;
public static class FeedDiscovery {
    public static string Find(string root,string profile,string address){
        var folders=new HashSet<string>(StringComparer.OrdinalIgnoreCase);folders.Add(Path.Combine(profile,"Runs"));
        try{var config=ProfileStore.Read(profile);if(config.ContainsKey("ExternalFeedDirectory"))folders.Add(Convert.ToString(config["ExternalFeedDirectory"]));}catch{}
        string parent=Path.GetDirectoryName(root.TrimEnd(Path.DirectorySeparatorChar));
        foreach(string app in Directory.GetDirectories(parent,"R730-App*")){
            string profiles=Path.Combine(app,"Profiles");if(!Directory.Exists(profiles))continue;
            foreach(string item in Directory.GetDirectories(profiles))try{var config=ProfileStore.Read(item);if(ProfileStore.Normalize(Convert.ToString(config["IdracHost"]))==ProfileStore.Normalize(address))folders.Add(Path.Combine(item,"Runs"));}catch{}
            folders.Add(Path.Combine(app,"Runs"));
        }
        string best=null;DateTime newest=DateTime.MinValue;
        foreach(string folder in folders){if(!Directory.Exists(folder))continue;foreach(string file in Directory.GetFiles(folder,"*.json"))try{
            var d=ProfileStore.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file));if(d.ContainsKey("State")&&(Convert.ToString(d["State"])=="Stopped"||Convert.ToString(d["State"])=="RESTORE FAILED"))continue;if(!d.ContainsKey("IdracHost")||ProfileStore.Normalize(Convert.ToString(d["IdracHost"]))!=ProfileStore.Normalize(address))continue;
            DateTime time;if(!DateTime.TryParse(Convert.ToString(d["Time"]),null,System.Globalization.DateTimeStyles.RoundtripKind,out time))continue;time=time.ToUniversalTime();double age=(DateTime.UtcNow-time).TotalSeconds;
            if(age< -5||age>45||!d.ContainsKey("Ipmi")||d["Ipmi"]==null)continue;
            if(time>newest){newest=time;best=file;}
        }catch{}}
        return best;
    }
}
