using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
public static class UpdateTests {
    static int count;
    static void Assert(bool ok,string name){if(!ok)throw new Exception(name);count++;}
    static string Json(string tag,string kind,string hash,string url,long size,bool preview,bool draft){
        string name="Thermal-Ops-Setup-"+tag.TrimStart('v')+"."+kind;
        return new JavaScriptSerializer().Serialize(new{tag_name=tag,prerelease=preview,draft=draft,assets=new[]{new{name=name,digest=hash,browser_download_url=url??AppUpdates.Releases+"/download/"+tag+"/"+name,size=size}}});
    }
    static void Reject(Action action,string name){try{action();}catch{count++;return;}throw new Exception("Accepted "+name);}
    public static int Main(string[] args){
        var current=new Version(1,4,0,0);string hash="sha256:"+new string('a',64);
        foreach(string kind in new[]{"msi","exe"}){
            var release=AppUpdates.Parse(Json("v1.5.0",kind,hash,null,100,false,false),current,kind);
            Assert(release!=null&&release.Name.EndsWith("."+kind)&&release.Version==new Version(1,5,0,0),kind+" selection");
            Assert(AppUpdates.Parse(Json("v1.4.0",kind,hash,null,100,false,false),current,kind)==null,"same version");
            Assert(AppUpdates.Parse(Json("v1.3.9",kind,hash,null,100,false,false),current,kind)==null,"downgrade");
            Assert(AppUpdates.Parse(Json("v1.5.0",kind,hash,null,100,true,false),current,kind)==null,"prerelease");
            Assert(AppUpdates.Parse(Json("v1.5.0",kind,hash,null,100,false,true),current,kind)==null,"draft");
        }
        Assert(AppUpdates.Parse(Json("v1.10.0","msi",hash,null,100,false,false),current,"msi").Version.Minor==10,"numeric versions");
        Assert(AppUpdates.Parse(Json("v1.5.0","msi",hash,null,100,false,false),current,null).Name==null,"portable release only");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0","exe",hash,null,100,false,false),current,"msi"),"wrong format");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0","msi",null,null,100,false,false),current,"msi"),"missing digest");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0","msi","sha256:no",null,100,false,false),current,"msi"),"bad digest");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0","msi",hash,"https://example.org/installer.msi",100,false,false),current,"msi"),"foreign host");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0","msi",hash,AppUpdates.Releases+"/download/v1.5.0/wrong.msi",100,false,false),current,"msi"),"wrong asset path");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0","msi",hash,null,268435457,false,false),current,"msi"),"oversized asset");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0","msi",hash,null,0,false,false),current,"msi"),"empty asset");
        Reject(()=>AppUpdates.Parse(Json("v1.5.0-beta","msi",hash,null,100,false,false),current,"msi"),"unsupported version");
        string file=Path.Combine(args[0],"hash-test.txt");File.WriteAllText(file,"abc");
        Assert(AppUpdates.HashMatches(file,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),"correct hash");
        File.AppendAllText(file,"corrupt");Assert(!AppUpdates.HashMatches(file,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),"corruption rejected");File.Delete(file);
        Console.WriteLine("PASS: "+count+" updater version, format, source, integrity and malformed-release checks.");return 0;
    }
}
