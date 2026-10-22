using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Web.Script.Serialization;
using LibreHardwareMonitor.Hardware;
class LocalWorker {
    static JavaScriptSerializer json=new JavaScriptSerializer();static Computer computer;
    static IEnumerable<IHardware> Walk(IHardware h){yield return h;foreach(var child in h.SubHardware)foreach(var item in Walk(child))yield return item;}
    static List<IHardware> Hardware(){return computer.Hardware.SelectMany(Walk).ToList();}
    static void Update(){foreach(var h in Hardware())h.Update();}
    static bool Valid(float? n){return n.HasValue&&!Single.IsNaN(n.Value)&&!Single.IsInfinity(n.Value);}
    static double? Max(IEnumerable<ISensor> sensors){var values=sensors.Where(s=>Valid(s.Value)).Select(s=>(double)s.Value.Value).ToArray();return values.Length==0?(double?)null:values.Max();}
    public static float Duty(float temp,float limit,float previous){if(temp>=limit)return 100;float target=Math.Max(50,Math.Min(100,50+(temp-(limit-30))*50/30));return target>=previous?Math.Min(target,previous+15):Math.Max(target,previous-2);}
    static string Text(Dictionary<string,object> d,string key){return d.ContainsKey(key)?Convert.ToString(d[key]):"";}
    static void Write(string path,object data){File.WriteAllText(path+".tmp",json.Serialize(data));if(File.Exists(path))File.Replace(path+".tmp",path,null);else File.Move(path+".tmp",path);}
    static void Main(string[] args){
        if(args.Length>0&&args[0]=="--self-test"){if(Duty(70,70,50)!=100||Duty(20,70,80)!=78||Duty(65,70,50)>65)Environment.Exit(1);return;}
        computer=new Computer{IsCpuEnabled=true,IsGpuEnabled=true,IsMotherboardEnabled=true,IsControllerEnabled=true};
        var selected=new List<IControl>();var touched=new HashSet<IControl>();bool attempted=false;Mutex mutex=null;bool owns=false;string status=args.Length>1?args[1]:"",stop=args.Length>2?args[2]:"";Dictionary<string,object> config=null;var clock=Stopwatch.StartNew();
        Action<string,string,object,float> report=(state,message,telemetry,fan)=>{if(config!=null)Write(status,new{Time=DateTime.UtcNow.ToString("o"),State=state,Message=message,Live=attempted,Smart=false,Fan=fan,Ipmi=telemetry,Gpu=(object)null,ManagementProvider="Local",IdracHost=Text(config,"IdracHost"),ProfileName=Text(config,"ProfileName"),TargetIdentity=new{Manufacturer="Local PC",Model=Environment.MachineName,Source="LibreHardwareMonitor",CoolingProfile=attempted?"Selected fan / temperature curve":"Hardware automatic / monitor only"},CooldownRemaining=0,UptimeSeconds=(int)clock.Elapsed.TotalSeconds});};
        try{
            mutex=new Mutex(false,"Global\\ThermalOps-LocalHardware");try{owns=mutex.WaitOne(0);}catch(AbandonedMutexException){owns=true;}if(!owns)throw new Exception("A local hardware worker already owns this computer");computer.Open();Update();
            if(args[0]=="--scan"){
                var controls=new List<object>();var temperatures=new List<object>();foreach(var h in Hardware())foreach(var s in h.Sensors){if(s.SensorType==SensorType.Control&&s.Control!=null&&!s.Name.ToLowerInvariant().Contains("pump"))controls.Add(new{Id=s.Identifier.ToString(),Name=h.Name+" / "+s.Name,Min=s.Control.MinSoftwareValue,Max=s.Control.MaxSoftwareValue,Mode=s.Control.ControlMode.ToString()});if(s.SensorType==SensorType.Temperature&&Valid(s.Value))temperatures.Add(new{Id=s.Identifier.ToString(),Name=h.Name+" / "+s.Name,Value=s.Value});}
                Write(args[1],new{Controls=controls,Temperatures=temperatures,Notice="Only channels exposed by the installed hardware driver are listed. No fan commands were requested."});return;
            }
            config=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(args[0]));bool live=args.Length>3&&args[3]=="--control";

            string source=Text(config,"LocalTemperature");float limit=config.ContainsKey("LocalLimit")?Convert.ToSingle(config["LocalLimit"]):70;
            if(live){if(!config.ContainsKey("LocalConfirmed")||!Convert.ToBoolean(config["LocalConfirmed"])||!Valid(limit)||limit<40||limit>110)throw new Exception("Confirm the physical fan channels, source and temperature limit first");var ids=new HashSet<string>();if(config.ContainsKey("LocalChannels")){var entries=config["LocalChannels"] as System.Collections.IEnumerable;if(entries!=null)foreach(var entry in entries)ids.Add(Convert.ToString(entry));}else ids.Add(Text(config,"LocalChannel"));if(ids.Count==0)throw new Exception("Select at least one fan channel");foreach(string channel in ids){var matches=Hardware().SelectMany(h=>h.Sensors).Where(s=>s.Identifier.ToString()==channel&&s.Control!=null).ToArray();if(matches.Length!=1)throw new Exception("Configured fan channel is missing or ambiguous");var control=matches[0].Control;if(control.ControlMode==ControlMode.Software)throw new Exception("Another software configuration already owns a selected channel");if(!Valid(control.MinSoftwareValue)||!Valid(control.MaxSoftwareValue)||control.MinSoftwareValue>50||control.MaxSoftwareValue<100)throw new Exception("Channel does not support the required 50-100 percent safety range");selected.Add(control);}}
            float command=100;int good=0;
            while(!File.Exists(stop)){
                Update();var hardware=Hardware();var sensors=hardware.SelectMany(h=>h.Sensors).ToArray();var temps=sensors.Where(s=>s.SensorType==SensorType.Temperature&&Valid(s.Value)).ToArray();var measured=sensors.Where(s=>s.SensorType==SensorType.Fan&&Valid(s.Value)).ToArray();
                var input=temps.SingleOrDefault(s=>s.Identifier.ToString()==source);double? inputValue=source=="@cpu-gpu-max"?Max(hardware.Where(h=>h.HardwareType==HardwareType.Cpu||h.HardwareType.ToString().StartsWith("Gpu")).SelectMany(h=>h.Sensors).Where(s=>s.SensorType==SensorType.Temperature)):input==null?(double?)null:input.Value;if(live&&(!inputValue.HasValue||inputValue.Value< -20||inputValue.Value>150))throw new Exception("Selected temperature source unavailable; restoring default control");
                if(live){good++;if(good>=2){command=Duty((float)inputValue.Value,limit,command);attempted=true;foreach(var control in selected){touched.Add(control);control.SetSoftware(command);}}}
                var data=new{Temps=temps.Select(s=>new{Name=s.Name,Value=s.Value}).ToArray(),Fans=measured.Select(s=>new{Name=s.Name,Value=s.Value,Units="RPM"}).ToArray(),Watts=(double?)null,CpuMax=Max(hardware.Where(h=>h.HardwareType==HardwareType.Cpu).SelectMany(h=>h.Sensors).Where(s=>s.SensorType==SensorType.Temperature)),Inlet=(double?)null,Exhaust=(double?)null,SystemMax=Max(temps),HottestSystemSensor=source=="@cpu-gpu-max"?"Highest CPU/GPU":input==null?"Available local sensors":input.Name,ReportedHealth=temps.Length==0?"UNKNOWN":live&&inputValue>=limit?"ATTENTION":"TELEMETRY OK"};
                report(live?"LOCAL COOLING":"MONITORING",live?"Only confirmed fan channels are controlled; driver acceptance only":"Local telemetry; no whole-PC power meter is available",data,live&&attempted?command:-1);
                for(int n=0;n<20&&!File.Exists(stop);n++)Thread.Sleep(100);
            }
        }catch(Exception ex){if(attempted)foreach(var control in touched)try{control.SetSoftware(100);}catch{}try{report("FAULT",ex.Message,null,-1);}catch{}}
        finally{
            if(attempted){bool restored=true;foreach(var control in touched){bool channelRestored=false;for(int n=0;n<3;n++)try{control.SetDefault();if(control.ControlMode!=ControlMode.Default)throw new Exception();channelRestored=true;break;}catch{Thread.Sleep(250);}if(!channelRestored)restored=false;}try{report(restored?"Stopped":"RESTORE FAILED",restored?"Hardware default restore command accepted":"Local default control restore unconfirmed; check hardware",null,-1);}catch{}}
            else if(config!=null&&File.Exists(stop))try{report("Stopped","Read-only monitor stopped",null,-1);}catch{}
            if(computer!=null)computer.Close();if(owns)mutex.ReleaseMutex();if(mutex!=null)mutex.Dispose();
        }
    }
}
