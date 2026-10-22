using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

public class FleetReading {
    public string Name,Address,Model="--",State="NO DATA",Health="UNKNOWN",Message="No telemetry received",Mode="--";
    public DateTime SampleUtc;public double? Watts,Gpu,Cpu,Fan;public double Age=Double.PositiveInfinity;public bool Fresh=false,Smart=false;
    public static Dictionary<string,object> Object(object value){return value as Dictionary<string,object>;}
    public static double? Number(Dictionary<string,object> data,string key){if(data==null||!data.ContainsKey(key)||data[key]==null)return null;try{double n=Convert.ToDouble(data[key]);return Double.IsNaN(n)||Double.IsInfinity(n)?(double?)null:n;}catch{return null;}}
    public static double? GpuTotal(Dictionary<string,object> gpu){if(gpu==null||!gpu.ContainsKey("Cards"))return null;var cards=gpu["Cards"] as IEnumerable;if(cards==null)return null;double sum=0;int count=0;foreach(var item in cards){var power=Number(Object(item),"Power");if(!power.HasValue||power.Value<0)return null;sum+=power.Value;count++;}return count==0?(double?)null:sum;}
    static string Text(Dictionary<string,object> d,string key){return d!=null&&d.ContainsKey(key)&&d[key]!=null?Convert.ToString(d[key]):"";}
    public static double SumKnown(List<FleetReading> rows,out int reporting){double watts=0;reporting=0;var addresses=new HashSet<string>();foreach(var row in rows)if(row.Watts.HasValue&&addresses.Add(ProfileStore.Normalize(row.Address))){watts+=row.Watts.Value;reporting++;}return watts;}
    public static bool CompleteTotal(List<FleetReading> rows,out double watts,out DateTime time){watts=0;time=DateTime.MinValue;var seen=new HashSet<string>();if(rows.Count==0)return false;foreach(var row in rows){if(!row.Fresh||!row.Watts.HasValue)return false;if(seen.Add(ProfileStore.Normalize(row.Address))){watts+=row.Watts.Value;if(row.SampleUtc>time)time=row.SampleUtc;}}return true;}
    public static FleetReading Evaluate(string name,string address,Dictionary<string,object> d,DateTime now){
        var r=new FleetReading{Name=name,Address=address};if(d==null)return r;
        if(ProfileStore.Normalize(Text(d,"IdracHost"))!=ProfileStore.Normalize(address)){r.Health="ATTENTION";r.Message="Status target mismatch; telemetry rejected";return r;}
        r.State=Text(d,"State");r.Message=Text(d,"Message");r.Smart=d.ContainsKey("Smart")&&Convert.ToBoolean(d["Smart"]);r.Mode=r.Smart?"Smart":"Original";
        DateTime time;if(!DateTime.TryParse(Text(d,"Time"),null,System.Globalization.DateTimeStyles.RoundtripKind,out time)){r.Message="Invalid sample time";return r;}
        r.SampleUtc=time.ToUniversalTime();r.Age=(now.ToUniversalTime()-time.ToUniversalTime()).TotalSeconds;r.Fresh=r.Age>=-5&&r.Age<=45;
        var ipmi=Object(d.ContainsKey("Ipmi")?d["Ipmi"]:null);var gpu=Object(d.ContainsKey("Gpu")?d["Gpu"]:null);var identity=Object(d.ContainsKey("TargetIdentity")?d["TargetIdentity"]:null);
        if(identity!=null)r.Model=Text(identity,"Model");r.Gpu=Number(gpu,"Temp");r.Cpu=Number(ipmi,"CpuMax");r.Fan=Number(d,"Fan");
        var watts=Number(ipmi,"Watts");if(r.Fresh&&watts.HasValue&&watts.Value>=0)r.Watts=watts;
        if(!r.Fresh){r.Health="STALE";r.Message=r.Age< -5?"Clock mismatch":"No fresh data; excluded from current power total";return r;}
        if(r.State=="FAULT"||r.State=="RESTORE FAILED"||r.State=="EMERGENCY"){r.Health=r.Message.IndexOf("Configure",StringComparison.OrdinalIgnoreCase)>=0?"CONFIGURE":"ATTENTION";return r;}
        if(r.State=="Starting"||r.State=="Restoring"){r.Health="TRANSITION";return r;}
        if(ipmi==null||r.State=="Stopped"){r.Health="NOT MONITORED";return r;}
        if(Text(d,"ManagementProvider")=="HPE"||Text(d,"ManagementProvider")=="Redfish"||Text(d,"ManagementProvider")=="Local"){r.Mode=d.ContainsKey("Live")&&Convert.ToBoolean(d["Live"])?"Native control":"Automatic";r.Fan=null;r.Health=Text(ipmi,"ReportedHealth");if(r.Health!="TELEMETRY OK"&&r.Health!="ATTENTION"&&r.Health!="DEGRADED")r.Health="UNKNOWN";return r;}
        if(Text(d,"ManagementProvider")=="Dell"&&ipmi.ContainsKey("ReportedHealth")){r.Mode="Monitoring";r.Fan=null;r.Health=Text(ipmi,"ReportedHealth");return r;}
        r.Health="TELEMETRY OK";
        if(!r.Cpu.HasValue||!Number(ipmi,"Exhaust").HasValue||!Number(ipmi,"Inlet").HasValue){r.Health="UNKNOWN";r.Message="Required temperature readings missing";}
        if(gpu!=null&&gpu.ContainsKey("OptionalMissing")&&Convert.ToBoolean(gpu["OptionalMissing"]))r.Health="DEGRADED";
        if((r.Gpu.HasValue&&r.Gpu.Value>=83)||(r.Cpu.HasValue&&r.Cpu.Value>=85)||(Number(ipmi,"Exhaust")>=60)||(Number(ipmi,"SystemMax")>=85))r.Health="ATTENTION";
        int fanCount=0;if(ipmi.ContainsKey("Fans")){var fans=ipmi["Fans"] as IEnumerable;if(fans!=null)foreach(var f in fans){fanCount++;var rpm=Number(Object(f),"Value");if(!rpm.HasValue){if(r.Health!="ATTENTION")r.Health="UNKNOWN";}else if(rpm.Value<=0)r.Health="ATTENTION";}}
        if(fanCount!=6&&r.Health!="ATTENTION"){r.Health="UNKNOWN";r.Message="Required fan telemetry incomplete";}
        return r;
    }
    public static void SelfTest(){
        DateTime now=DateTime.UtcNow;var source=new Dictionary<string,object>{{"Time",now.ToString("o")},{"IdracHost","192.0.2.1"},{"State","NORMAL"},{"Message",""},{"Smart",true},{"Fan",55},{"Ipmi",new Dictionary<string,object>{{"Watts",400},{"CpuMax",40},{"Exhaust",30}}},{"Gpu",new Dictionary<string,object>{{"Temp",60}}}};
        var ipmi=Object(source["Ipmi"]);ipmi["Inlet"]=24;var fans=new List<object>();for(int n=0;n<6;n++)fans.Add(new Dictionary<string,object>{{"Value",3000}});ipmi["Fans"]=fans;
        var ok=Evaluate("A","192.0.2.1",source,now);if(ok.Watts!=400||ok.Health!="TELEMETRY OK")throw new Exception("Valid telemetry summary failed");
        var stale=Evaluate("A","192.0.2.1",source,now.AddMinutes(2));if(stale.Watts.HasValue||stale.Health!="STALE")throw new Exception("Stale power counted");
        if(Evaluate("B","192.0.2.2",source,now).Watts.HasValue)throw new Exception("Wrong-target power counted");
        if(Evaluate("C","192.0.2.3",null,now).Watts.HasValue)throw new Exception("Unknown power became zero");
        int reporting;double total=SumKnown(new List<FleetReading>{ok,stale,Evaluate("C","192.0.2.3",null,now),ok},out reporting);if(total!=400||reporting!=1)throw new Exception("Partial coverage/duplicate endpoint aggregate failed");
        double complete;DateTime sample;if(!CompleteTotal(new List<FleetReading>{ok,ok},out complete,out sample)||complete!=400||CompleteTotal(new List<FleetReading>{ok,stale},out complete,out sample))throw new Exception("Complete fleet total validation failed");
        var gpu=new Dictionary<string,object>{{"Cards",new object[]{new Dictionary<string,object>{{"Power",100}},new Dictionary<string,object>{{"Power",200}}}}};if(GpuTotal(gpu)!=300)throw new Exception("GPU total failed");
        gpu["Cards"]=new object[]{new Dictionary<string,object>{{"Power",100}},new Dictionary<string,object>{{"Power",null}}};if(GpuTotal(gpu).HasValue)throw new Exception("Partial GPU sum treated as complete");
        var powerHistory=new TemperatureHistory(null,true,100000,0);if(!powerHistory.Add(now,new double?[]{400,120,null,null,null})||powerHistory.Add(now.AddSeconds(1),new double?[]{-1,120,null,null,null}))throw new Exception("Power history validation failed");
        source["ManagementProvider"]="HPE";ipmi["ReportedHealth"]="TELEMETRY OK";ipmi["Fans"]=new object[]{new Dictionary<string,object>{{"Name","Fan A"},{"Value",35},{"Units","Percent"}}};if(Evaluate("HPE","192.0.2.1",source,now).Health!="TELEMETRY OK")throw new Exception("HPE incorrectly required six Dell fans");ipmi["ReportedHealth"]="ATTENTION";if(Evaluate("HPE","192.0.2.1",source,now).Health!="ATTENTION")throw new Exception("HPE health lost");source["ManagementProvider"]="Dell";if(Evaluate("Dell","192.0.2.1",source,now).Health!="ATTENTION")throw new Exception("Dell generic health lost");ipmi["ReportedHealth"]="TELEMETRY OK";if(Evaluate("Dell","192.0.2.1",source,now).Health!="TELEMETRY OK"||Evaluate("Dell","192.0.2.1",source,now).Fan.HasValue)throw new Exception("Dell monitoring incorrectly used R730 counts/commands");source.Remove("ManagementProvider");
        var startup=new Dictionary<string,object>{{"ManagementProvider","HPE"}};if(!ServerManager.CanAutoStart(startup))throw new Exception("HPE startup disabled");startup["ManagementProvider"]="Dell";if(ServerManager.CanAutoStart(startup))throw new Exception("Unconfigured Dell auto-start enabled");startup["GpuMode"]="Local";startup["GpuSourceConfirmed"]=true;if(!ServerManager.CanAutoStart(startup))throw new Exception("Configured Dell startup disabled");
        ipmi.Remove("Fans");if(Evaluate("A","192.0.2.1",source,now).Health=="TELEMETRY OK")throw new Exception("Missing fans shown healthy");
    }
}

public class FleetOverview : UserControl {
    Label title=new Label(),health=new Label(),power=new Label(),coverage=new Label(),counts=new Label(),note=new Label();DataGridView grid=new DataGridView();
    TemperatureTrends totalPower=new TemperatureTrends(null,FanApp.PreviewMode,true,true);
    public event Action<int> ServerSelected;
    public FleetOverview(){Dock=DockStyle.Fill;BackColor=Color.FromArgb(6,14,17);ForeColor=Color.White;Font=new Font("Consolas",10);
        var layout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(20),ColumnCount=1,RowCount=7};layout.RowStyles.Add(new RowStyle(SizeType.Absolute,45));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,65));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,65));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,45));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,260));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,60));Controls.Add(layout);
        title.Text="[ FLEET // HEALTH HUD ]";title.Font=new Font("Consolas",22,FontStyle.Bold);title.ForeColor=Color.FromArgb(82,255,159);title.Dock=DockStyle.Fill;layout.Controls.Add(title,0,0);
        health.Font=new Font("Consolas",21,FontStyle.Bold);health.Dock=DockStyle.Fill;layout.Controls.Add(health,0,1);
        var watts=new FlowLayoutPanel{Dock=DockStyle.Fill};power.Font=new Font("Consolas",25,FontStyle.Bold);power.ForeColor=Color.FromArgb(38,215,255);power.AutoSize=true;coverage.AutoSize=true;coverage.Margin=new Padding(24,15,0,0);watts.Controls.Add(power);watts.Controls.Add(coverage);layout.Controls.Add(watts,0,2);
        counts.Dock=DockStyle.Fill;counts.ForeColor=Color.LightSteelBlue;layout.Controls.Add(counts,0,3);
        grid.Dock=DockStyle.Fill;grid.ReadOnly=true;grid.AllowUserToAddRows=false;grid.AllowUserToDeleteRows=false;grid.RowHeadersVisible=false;grid.BackgroundColor=BackColor;grid.AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill;grid.EnableHeadersVisualStyles=false;grid.ColumnHeadersDefaultCellStyle.BackColor=Color.FromArgb(26,47,47);grid.ColumnHeadersDefaultCellStyle.ForeColor=Color.White;grid.DefaultCellStyle.BackColor=Color.FromArgb(14,27,29);grid.DefaultCellStyle.ForeColor=Color.White;grid.DefaultCellStyle.SelectionBackColor=Color.FromArgb(40,69,67);grid.RowTemplate.Height=32;
        foreach(string name in new[]{"Server","Management","Model","Health","State","GPU C","CPU C","Input W","Fan %","Age","Curves"}){var col=grid.Columns.Add(name,name);grid.Columns[col].SortMode=DataGridViewColumnSortMode.NotSortable;}float[] widths={130,125,140,150,110,50,50,70,55,50,65};for(int n=0;n<widths.Length;n++)grid.Columns[n].FillWeight=widths[n];
        grid.CellDoubleClick+=(s,e)=>{if(e.RowIndex>=0&&ServerSelected!=null)ServerSelected(e.RowIndex);};layout.Controls.Add(totalPower,0,4);layout.Controls.Add(grid,0,5);
        note.Text="POWER = FRESH REPORTED SERVER INPUT ONLY. UNKNOWN / STALE READINGS ARE EXCLUDED.\r\nHealth reflects available controller telemetry, not a full hardware diagnostic. Double-click a server for details.";note.Dock=DockStyle.Fill;note.Padding=new Padding(0,10,0,0);note.ForeColor=Color.FromArgb(119,174,160);layout.Controls.Add(note,0,6);
    }
    static string Value(double? value,string suffix=""){return value.HasValue?value.Value.ToString("0.##")+suffix:"--";}
    public void RefreshReadings(List<FleetReading> rows){
        var endpoints=new List<string>();foreach(var row in rows)endpoints.Add(ProfileStore.Normalize(row.Address));endpoints.Sort(StringComparer.Ordinal);string key=String.Join("|",endpoints.ToArray());string hash;using(var sha=System.Security.Cryptography.SHA256.Create())hash=BitConverter.ToString(sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(key))).Replace("-","").Substring(0,16);totalPower.SetTarget(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"fleet-power-"+hash+".jsonl"));double completeWatts;DateTime sampleTime;if(FleetReading.CompleteTotal(rows,out completeWatts,out sampleTime))totalPower.Feed(sampleTime,new double?[]{completeWatts,null,null,null,null});else totalPower.NewSession();totalPower.Tick();
        int critical=0,unknown=0,degraded=0,reporting=0,fresh=0;double watts=FleetReading.SumKnown(rows,out reporting);foreach(var r in rows){if(r.Health=="ATTENTION")critical++;else if(r.Health=="DEGRADED"||r.Health=="CONFIGURE"||r.Health=="TRANSITION")degraded++;else if(r.Health!="TELEMETRY OK")unknown++;if(r.Fresh&&r.Health=="TELEMETRY OK")fresh++;}
        health.Text=critical>0?"!! ATTENTION REQUIRED":degraded>0?"! DEGRADED / CONFIGURATION":unknown>0||rows.Count==0?"? INCOMPLETE VISIBILITY":"+ TELEMETRY NOMINAL";health.ForeColor=critical>0?Color.Salmon:degraded>0||unknown>0?Color.Orange:Color.FromArgb(82,255,159);
        power.Text=(reporting==0?"--":watts.ToString("0.#"))+" W";coverage.Text=(reporting==rows.Count&&rows.Count>0?"TOTAL INPUT":"KNOWN INPUT / PARTIAL")+"  |  "+reporting+" / "+rows.Count+" servers reporting";
        counts.Text=rows.Count+" SAVED    "+fresh+" NOMINAL    "+critical+" ATTENTION    "+degraded+" DEGRADED / SETUP    "+unknown+" STALE / UNKNOWN";
        int selected=grid.CurrentCell==null?-1:grid.CurrentCell.RowIndex;grid.Rows.Clear();foreach(var r in rows){int index=grid.Rows.Add(r.Name,r.Address,r.Model,r.Health,r.State,Value(r.Gpu),Value(r.Cpu),Value(r.Watts),Value(r.Fan),Double.IsInfinity(r.Age)?"--":Math.Max(0,r.Age).ToString("0")+"s",r.Mode);grid.Rows[index].DefaultCellStyle.ForeColor=r.Health=="ATTENTION"?Color.Salmon:r.Health=="TELEMETRY OK"?Color.FromArgb(182,244,211):Color.FromArgb(235,195,119);grid.Rows[index].Cells[3].ToolTipText=r.Message;}if(selected>=0&&selected<grid.Rows.Count)grid.CurrentCell=grid.Rows[selected].Cells[0];
    }
}
