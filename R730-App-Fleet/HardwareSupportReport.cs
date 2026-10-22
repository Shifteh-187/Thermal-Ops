using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

public static class HardwareSupportReport {
    static Dictionary<string,object> Map(object value){return value as Dictionary<string,object>;}
    static object Value(Dictionary<string,object> map,string key){return map!=null&&map.ContainsKey(key)?map[key]:null;}
    static string Clean(object value,string address,bool firmware=false){
        string text=value==null?"Not reported":Convert.ToString(value);
        if(!String.IsNullOrEmpty(address))text=text.Replace(address,"[address removed]");
        if(!firmware)text=Regex.Replace(text,@"\b(?:\d{1,3}\.){3}\d{1,3}\b","[address removed]");
        text=text.Replace("`","'").Replace("\r"," ").Replace("\n"," ");
        return text.Length>160?text.Substring(0,160):text;
    }
    public static string Create(Dictionary<string,object> snapshot){
        if(snapshot==null||Map(Value(snapshot,"TargetIdentity"))==null)throw new Exception("Start Monitor only and wait for system detection, then open Hardware support request.");
        string address=Convert.ToString(Value(snapshot,"IdracHost"));
        var identity=Map(Value(snapshot,"TargetIdentity"));var ipmi=Map(Value(snapshot,"Ipmi"));
        var text=new StringBuilder("## Thermal Ops hardware support report\r\n\r\nVersion: 1.3.0\r\nCollection: read-only snapshot; no fan-control probes were sent.\r\n\r\n```text\r\n");
        text.AppendLine("Interface: "+Clean(Value(snapshot,"ManagementProvider"),address));
        foreach(string key in new[]{"Manufacturer","Model","IdracGeneration","FirmwareRevision","FirmwareAux","FirmwareSource","ManufacturerId","ProductId","ManualControlAllowed","CoolingProfile","Capabilities","NativeMinimumAvailable","NativeMinimum","NativeMinimumLimit","NativeMaximumLimit"})
            text.AppendLine(key+": "+Clean(Value(identity,key),address,key=="FirmwareRevision"));
        text.AppendLine("Sensor health: "+Clean(Value(ipmi,"ReportedHealth"),address));
        foreach(string group in new[]{"Fans","Temps"}){
            text.AppendLine(group+":");var rows=Value(ipmi,group) as IEnumerable;int count=0;
            if(rows!=null)foreach(var row in rows){if(count++>=64){text.AppendLine("  [truncated]");break;}var sensor=Map(row);text.AppendLine("  "+Clean(Value(sensor,"Name"),address)+" | "+Clean(Value(sensor,"Value"),address)+" | "+Clean(Value(sensor,"Units"),address)+" | "+Clean(Value(sensor,"Status"),address));}
            if(count==0)text.AppendLine("  No readings available");
        }
        text.AppendLine("```");
        text.AppendLine("\r\nRequested support / observed behaviour: (please describe)");
        text.AppendLine("\r\nReview before posting. Credentials, management address, hostname, service tag, GPU identifiers and raw logs are not included. Capabilities not reported here are unknown, not proof that the hardware lacks them.");
        return text.ToString();
    }
    public static void Show(IWin32Window owner,Dictionary<string,object> snapshot){
        try{
            string content=Create(snapshot);
            using(var dialog=new Form{Text="Hardware support request",Size=new Size(850,650),StartPosition=FormStartPosition.CenterParent}){
                var body=new TextBox{Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,Dock=DockStyle.Fill,Font=new Font("Consolas",10),Text=content,WordWrap=false};
                var buttons=new FlowLayoutPanel{Dock=DockStyle.Bottom,Height=48};
                var copy=new Button{Text="Copy report",Width=140,Height=32};copy.Click+=(s,e)=>{Clipboard.SetText(content);copy.Text="Copied";};
                var issue=new Button{Text="Open GitHub issue",Width=165,Height=32};issue.Click+=(s,e)=>{try{Process.Start(new ProcessStartInfo("https://github.com/Shifteh-187/Thermal-Ops/issues/new?template=hardware-support.md"){UseShellExecute=true});}catch(Exception ex){MessageBox.Show(dialog,ex.Message,"Could not open browser");}};
                buttons.Controls.Add(copy);buttons.Controls.Add(issue);dialog.Controls.Add(body);dialog.Controls.Add(buttons);dialog.ShowDialog(owner);
            }
        }catch(Exception ex){MessageBox.Show(owner,ex.Message,"Hardware support report");}
    }
    public static void SelfTest(){
        var privateFields=new Dictionary<string,object>{{"Manufacturer","Dell Inc."},{"Model","PowerEdge R740"},{"FirmwareRevision","7.00.00.00"},{"SerialNumber","SECRET-SERVICE-TAG"},{"Password","SECRET-PASSWORD"}};
        var snapshot=new Dictionary<string,object>{{"TargetIdentity",privateFields},{"IdracHost","private-server.example"},{"IdracPassProtected","SECRET-BLOB"},{"Message","SECRET-LOG"},{"Gpu",new Dictionary<string,object>{{"Id","SECRET-GPU"}}}};
        string report=Create(snapshot);
        if(report.Contains("SECRET-")||report.Contains("private-server.example")||!report.Contains("PowerEdge R740")||!report.Contains("7.00.00.00"))throw new Exception("Report privacy/identity check failed");
        bool rejected=false;try{Create(null);}catch{rejected=true;}if(!rejected)throw new Exception("Report accepted missing identity");
    }
}
