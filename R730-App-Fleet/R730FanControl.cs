using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management;
using System.Threading.Tasks;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public class FanApp : Form {
    public static bool PreviewMode=false;
    TemperatureTrends trends,powerTrends;
    readonly FanCurveEditor curveEditor=new FanCurveEditor();readonly TextBox serverNameBox=new TextBox();
    public Dictionary<string,object> Snapshot {get;private set;}
    bool observing=false;
    readonly string root=AppDomain.CurrentDomain.BaseDirectory;
    readonly JavaScriptSerializer json=new JavaScriptSerializer();
    readonly Color bg=Color.FromArgb(18,23,31), card=Color.FromArgb(29,36,47), ink=Color.FromArgb(226,234,243);
    Label state=new Label(), detail=new Label(), age=new Label(), machine=new Label();
    string localMachine="Detecting Windows hardware...",targetMachine="Cooling target: waiting for iDRAC identification";
    Label[] values=new Label[8];
    Label summary=new Label();
    DataGridView temperatures=new BufferedDataGridView();
    DataGridView fans=new BufferedDataGridView(), gpus=new BufferedDataGridView();
    CheckBox bundledIpmi=new ReadableCheckBox();
    ComboBox nativeProfile=new ComboBox();NumericUpDown nativeMinimum=new NumericUpDown{Minimum=0,Maximum=100,Value=50};CheckBox nativeMinimumEnabled=new ReadableCheckBox();
    ComboBox provider=new ComboBox(),gpuScope=new ComboBox();
    CheckBox sourceConfirmed=new ReadableCheckBox();
    readonly string profileDirectory;
    public string ProfileDirectory {get{return profileDirectory;}}
    public string ProfileName {get{return settings!=null&&settings.ContainsKey("ProfileName")?Convert.ToString(settings["ProfileName"]):"Server";}}
    public bool IsRunning {get{return worker!=null&&!worker.HasExited;}}
    public bool IsObserving {get{return observing;}}
    public string CurrentState {get{return state.Text.Length>24?state.Text.Substring(0,24):state.Text;}}
    bool restorationFailed=false;
    public bool RestorationFailed {get{return restorationFailed;}}
    public void StopCooling(){RequestStop();}
    bool IsNative{get{return settings!=null&&settings.ContainsKey("ManagementProvider")&&Convert.ToString(settings["ManagementProvider"])!="Dell";}}
    bool IsLocal{get{return IsNative&&Convert.ToString(settings["ManagementProvider"])=="Local";}}
    public void StartCooling(){StartWorker(!IsNative||settings.ContainsKey("ControlOnStartup")&&Convert.ToBoolean(settings["ControlOnStartup"]));}
    void ApplyProviderUi(){nativeMinimumEnabled.Text=settings!=null&&settings.ContainsKey("ManagementProvider")&&Convert.ToString(settings["ManagementProvider"])=="DellRedfish"?"Dell min fan %":"HPE min fan %";nativeProfile.Visible=nativeMinimum.Visible=nativeMinimumEnabled.Visible=IsNative&&!IsLocal;bundledIpmi.Visible=!IsNative;if(!IsNative)return;monitor.Text=IsLocal?"Monitor PC":"Monitor BMC";control.Text=IsLocal?"Start fan curve":"Apply native cooling";control.Enabled=!IsRunning&&!observing;smart.Enabled=false;smart.Checked=false;provider.Enabled=gpuScope.Enabled=sourceConfirmed.Enabled=false;stop.Text=observing?"Stop viewing":"Stop / restore";ipmiBox.Enabled=gpuBox.Enabled=false;if(IsLocal)hostBox.Enabled=userBox.Enabled=passBox.Enabled=false;}
    public void ObserveExisting(string path){
        var d=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(path));
        if(!d.ContainsKey("IdracHost")||ProfileStore.Normalize(Convert.ToString(d["IdracHost"]))!=ProfileStore.Normalize(hostBox.Text))throw new Exception("Observed status belongs to another server");
        if(IsRunning)throw new Exception("Stop this profile's worker before observing another controller");
        statusFile=path;observing=true;lastStatus="";trends.NewSession();powerTrends.NewSession();stop.Text="Stop viewing";stop.Enabled=true;
        monitor.Enabled=control.Enabled=save.Enabled=smart.Enabled=provider.Enabled=gpuScope.Enabled=sourceConfirmed.Enabled=bundledIpmi.Enabled=nativeProfile.Enabled=nativeMinimum.Enabled=nativeMinimumEnabled.Enabled=false;
        foreach(var field in new[]{hostBox,userBox,passBox,ipmiBox,gpuBox})field.Enabled=false;
        Log("Following an existing controller read-only. No fan commands or stop signals will be sent.");RefreshState();
    }
    TextBox messages=new TextBox();
    TextBox hostBox=new TextBox(), userBox=new TextBox(), passBox=new TextBox(), ipmiBox=new TextBox(), gpuBox=new TextBox();
    Button monitor=new ReadableButton(), control=new ReadableButton(), stop=new ReadableButton(), save=new ReadableButton();
    CheckBox smart=new ReadableCheckBox();
    Timer timer=new Timer();
    Process worker; string statusFile,stopFile,logFile,lastStatus="";
    bool closing=false, stopping=false; DateTime started;
    StringBuilder output=new StringBuilder(); readonly object gate=new object();
    Dictionary<string,object> settings;
    [STAThread] public static void Main(string[] args) {
        PreviewMode=args.Length>0&&(args[0]=="--preview"||args[0]=="--manager-preview"||args[0]=="--server-preview");
        ThermalBrand.SetIdentity();Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        if(args.Length>0&&args[0]=="--local-setup-preview"){using(var f=new LocalSetupDialog(AppDomain.CurrentDomain.BaseDirectory)){f.Show();Application.DoEvents();using(var bitmap=new Bitmap(f.Width,f.Height)){f.DrawToBitmap(bitmap,new Rectangle(0,0,f.Width,f.Height));bitmap.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"local-setup-preview.png"));}f.Hide();}return;}
        if(args.Length>0&&(args[0]=="--manager-preview"||args[0]=="--server-preview")){using(var f=new ServerManager()){if(args.Length>1)f.PreviewSnapshot(args[1]);if(args[0]=="--server-preview")f.ShowFirstServer();f.Show();Application.DoEvents();using(var bitmap=new Bitmap(f.Width,f.Height)){f.DrawToBitmap(bitmap,new Rectangle(0,0,f.Width,f.Height));bitmap.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"manager-preview.png"));}f.Hide();}return;}
        if (args.Length>0 && args[0]=="--preview") {
            using(var f=new FanApp()){f.localMachine=DetectLocalMachine();f.UpdateMachineLabel();if(args.Length>1){var sample=f.json.Deserialize<Dictionary<string,object>>(File.ReadAllText(args[1]));f.UpdateReadings(sample);f.state.Text=Convert.ToString(sample["State"]);f.detail.Text=Convert.ToString(sample["Message"]);f.monitor.Enabled=f.control.Enabled=f.save.Enabled=f.smart.Enabled=false;f.stop.Enabled=true;}f.Show();Application.DoEvents();using(var bitmap=new Bitmap(f.Width,f.Height)){f.DrawToBitmap(bitmap,new Rectangle(0,0,f.Width,f.Height));bitmap.Save(Path.Combine(f.root,"preview.png"));}f.Hide();}return;
        }
        if (args.Length>0 && args[0]=="--self-test") {
            try { var f=new FanApp(); f.ValidateBundle(); f.Dispose(); File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"self-test.txt"),"PASS: UI, configuration decryption, and worker bundle loaded."); Environment.Exit(0); }
            catch(Exception ex) { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"self-test.txt"),"FAIL: "+ex.Message); Environment.Exit(1); }
        }
        if(args.Length==3&&args[0]=="--import-profiles"){try{int count=ProfileStore.ImportLegacy(args[1],args[2]).Count;File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"import-result.txt"),"Imported "+count+" profile(s).");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"import-result.txt"),"Import failed: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--bundle-test"){try{string root=AppDomain.CurrentDomain.BaseDirectory;BundledTools.Validate(root);var config=new Dictionary<string,object>{{"IpmiExe","E:\\OldIPMI\\ipmitool.exe"}};if(BundledTools.ResolveIpmi(root,config)!=BundledTools.IpmiPath(root))throw new Exception("Legacy profile did not choose bundled transport");config["UseBundledIpmi"]=false;if(BundledTools.ResolveIpmi(root,config)!=Convert.ToString(config["IpmiExe"]))throw new Exception("Custom tool override lost");File.WriteAllText(Path.Combine(root,"bundle-test.txt"),"PASS: bundled IPMI files, HPE/Redfish modules, legacy defaults and custom overrides.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"bundle-test.txt"),"FAIL: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--profile-test"){try{ProfileStore.SelfTest(AppDomain.CurrentDomain.BaseDirectory);File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"profile-test.txt"),"PASS: separate credentials, profile paths, duplicate-target prevention and GPU defaults.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"profile-test.txt"),"FAIL: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--trend-test"){try{TemperatureHistory.SelfTest();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"trend-test.txt"),"PASS: windows, duplicate/out-of-order/future samples, missing values, gaps, session breaks, retention.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"trend-test.txt"),"FAIL: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>2&&args[0]=="--feed-test"){string root=AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);string found=FeedDiscovery.Find(root,args[1],args[2]);File.WriteAllText(Path.Combine(root,"feed-test.txt"),found??"NO MATCH");return;}
        if(args.Length>0&&args[0]=="--report-test"){try{HardwareSupportReport.SelfTest();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"report-test.txt"),"PASS: support-report identity, privacy whitelist and missing identity rejection.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"report-test.txt"),"FAIL: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--fleet-test"){try{FleetReading.SelfTest();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"fleet-test.txt"),"PASS: fresh/partial/stale/wrong-target power, GPU sums, missing telemetry and power-range validation.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"fleet-test.txt"),"FAIL: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--tray-test"){try{ServerManager.TraySelfTest();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"tray-test.txt"),"PASS: tray menu, X hides, dashboard restores, explicit exit disposes.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"tray-test.txt"),"FAIL: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--shutdown-test"){try{var now=DateTime.UtcNow;var data=new Dictionary<string,object>{{"Time",now.ToString("o")},{"State","Stopped"},{"Message","Dell automatic control command accepted"}};if(!CoolingShutdownDialog.Accepted(data,now))throw new Exception("Restore acknowledgement rejected");data["State"]="RESTORE FAILED";if(CoolingShutdownDialog.Accepted(data,now))throw new Exception("Failure accepted");data["State"]="Stopped";data["Time"]=now.AddMinutes(-2).ToString("o");if(CoolingShutdownDialog.Accepted(data,now))throw new Exception("Old acknowledgement accepted");data["Time"]=now.ToString("o");data["Message"]="Unknown exit";if(CoolingShutdownDialog.Accepted(data,now))throw new Exception("Unknown exit accepted");foreach(string acknowledgement in new[]{"Original native cooling settings verified","Hardware default restore command accepted"}){data["Message"]=acknowledgement;if(!CoolingShutdownDialog.Accepted(data,now))throw new Exception("Native/local acknowledgement rejected");}File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"shutdown-test.txt"),"PASS: restore acknowledgement, failed restore, stale status and unknown exit.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"shutdown-test.txt"),"FAIL: "+ex.Message);Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--reconnect-test"){ReconnectPolicy.SelfTest();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"reconnect-test.txt"),"PASS: retry intent, backoff, cancellation, fault latches and unknown crash rejection.");return;}
        if(args.Length>0&&args[0]=="--curves-test"){try{CurveAndNameSelfTest();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"curves-test.txt"),"PASS: curve editor, validation, discovery, persistence, locks, rename and tab order.");}catch(Exception ex){File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"curves-test.txt"),"FAIL: "+ex.ToString());Environment.Exit(1);}return;}
        if(args.Length>0&&args[0]=="--curves-preview"){PreviewMode=true;using(var f=new FanApp()){if(args.Length>1)f.PreviewSnapshot(args[1]);var tab=(TabControl)f.curveEditor.Parent.Parent;tab.SelectedTab=(TabPage)f.curveEditor.Parent;f.Show();Application.DoEvents();using(var bitmap=new Bitmap(f.Width,f.Height)){f.DrawToBitmap(bitmap,new Rectangle(0,0,f.Width,f.Height));bitmap.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"curves-preview.png"));}f.Hide();}return;}
        if(args.Length>0&&args[0]=="--discovery-preview"){PreviewMode=true;HardwareDiscoveryDialog.Preview();return;}
        var manager=new ServerManager();
        if(args.Length>1&&args[0]=="--observe")manager.Shown+=(sender,eventArgs)=>manager.ObserveExisting(args[1]);
        if(args.Length>1&&args[0]=="--resume-profile")manager.Shown+=(sender,eventArgs)=>manager.StartProfile(args[1]);
        if(args.Length==0||(args.Length==1&&args[0]=="--startup"))manager.Shown+=(sender,eventArgs)=>{manager.StartConfiguredServers();if(args.Length==1)manager.BeginInvoke((Action)(()=>manager.HideToTray()));};
        using(var appMutex=new System.Threading.Mutex(false,"ThermalOps.AppRunning")){Application.Run(manager);}
    }
    public FanApp() : this(null) {}
    public FanApp(string directory) {
        profileDirectory=directory??root;
        Text="Fan Control - System Overview"; Size=new Size(1180,1000); MinimumSize=new Size(1000,850);
        StartPosition=FormStartPosition.CenterScreen; BackColor=bg; ForeColor=ink; Font=new Font("Segoe UI",10);
        var layout=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(10),RowCount=5,ColumnCount=1};
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute,76)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,48));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent,100)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,92)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,34)); Controls.Add(layout);
        var header=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,RowCount=2,ColumnCount=1};header.RowStyles.Add(new RowStyle(SizeType.Absolute,34));header.RowStyles.Add(new RowStyle(SizeType.Percent,100));
        var heading=new Label{Text="FAN CONTROL // THERMAL OPS",Font=new Font("Consolas",18,FontStyle.Bold),ForeColor=Color.FromArgb(82,255,159),Dock=DockStyle.Fill};header.Controls.Add(heading,0,0);
        machine.Dock=DockStyle.Fill;machine.ForeColor=Color.LightSteelBlue;machine.Font=new Font("Segoe UI",9);machine.Text=localMachine+"\r\n"+targetMachine;header.Controls.Add(machine,0,1);layout.Controls.Add(header,0,0);
        var statusPanel=new BufferedPanel{Dock=DockStyle.Fill}; state.Text="READY"; state.ForeColor=Color.Turquoise; state.AutoSize=true;
        detail.Text="Start monitoring to view live readings. Cooling control is separate."; detail.Location=new Point(0,27); detail.AutoSize=true;
        statusPanel.Controls.Add(state);statusPanel.Controls.Add(detail);layout.Controls.Add(statusPanel,0,1);
        var tabs=new BufferedTabControl{Dock=DockStyle.Fill};layout.Controls.Add(tabs,0,2);
        var overview=new TabPage("Overview"){BackColor=bg,ForeColor=ink};tabs.TabPages.Add(overview);
        var data=new BufferedTableLayoutPanel{Dock=DockStyle.Top,Height=825,RowCount=5,ColumnCount=1,Padding=new Padding(8)};
        data.RowStyles.Add(new RowStyle(SizeType.Absolute,136));data.RowStyles.Add(new RowStyle(SizeType.Absolute,300));data.RowStyles.Add(new RowStyle(SizeType.Absolute,110));data.RowStyles.Add(new RowStyle(SizeType.Absolute,205));data.RowStyles.Add(new RowStyle(SizeType.Absolute,56));
        var scroll=new BufferedPanel{Dock=DockStyle.Fill,AutoScroll=true};scroll.Controls.Add(data);overview.Controls.Add(scroll);
        var graphs=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,RowCount=1};graphs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));graphs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));trends=new TemperatureTrends(null,PreviewMode);powerTrends=new TemperatureTrends(null,PreviewMode,true);trends.Margin=new Padding(0,4,6,4);powerTrends.Margin=new Padding(6,4,0,4);graphs.Controls.Add(trends,0,0);graphs.Controls.Add(powerTrends,1,0);data.Controls.Add(graphs,0,1);
        var cards=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=4,RowCount=2};data.Controls.Add(cards,0,0);
        for(int i=0;i<4;i++)cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,25));
        cards.RowStyles.Add(new RowStyle(SizeType.Percent,50));cards.RowStyles.Add(new RowStyle(SizeType.Percent,50));
        string[] titles={"GPU MAXIMUM","CPU MAXIMUM","EXHAUST","FAN COMMAND","INLET","SERVER POWER","GPU MAX LOAD","GPU MAX POWER"};
        for(int i=0;i<8;i++){
            var p=new BufferedPanel{Dock=DockStyle.Fill,BackColor=card,Margin=new Padding(4),Padding=new Padding(10)};
            p.Controls.Add(new Label{Text=titles[i],Dock=DockStyle.Top,Height=21,ForeColor=Color.Silver,Font=new Font("Segoe UI",9)});
            values[i]=new Label{Text="--",Location=new Point(10,28),AutoSize=true,Font=new Font("Segoe UI",18,FontStyle.Bold)};
            p.Controls.Add(values[i]);cards.Controls.Add(p,i%4,i/4);
        }
        StyleGrid(gpus);foreach(string name in new[]{"Graphics card","Vendor","Provider","Core C","Load %","Power W","Bus","Identity"})gpus.Columns.Add(name,name);
        gpus.Columns[0].FillWeight=180;gpus.Columns[7].FillWeight=180;
        data.Controls.Add(Section("GRAPHICS CARDS",gpus),0,2);
        var lower=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2};lower.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,45));lower.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,55));data.Controls.Add(lower,0,3);
        StyleGrid(fans);fans.Columns.Add("fan","Chassis fan");fans.Columns.Add("rpm","Measured RPM");for(int i=1;i<=6;i++)fans.Rows.Add("Fan "+i,"--");
        StyleGrid(temperatures);temperatures.Columns.Add("sensor","Temperature probe");temperatures.Columns.Add("temperature","Reading C");
        lower.Controls.Add(Section("CHASSIS FANS",fans),0,0);lower.Controls.Add(Section("SERVER TEMPERATURE PROBES",temperatures),1,0);
        summary.Dock=DockStyle.Fill;summary.Padding=new Padding(5,8,5,0);summary.ForeColor=Color.LightGray;
        summary.Text="Live GPU, fan and server telemetry appears here after the first scan.";data.Controls.Add(summary,0,4);
        var connection=new TabPage("Connection"){BackColor=bg,ForeColor=ink};tabs.TabPages.Add(connection);
        var form=new BufferedTableLayoutPanel{Dock=DockStyle.Top,Height=650,ColumnCount=2,Padding=new Padding(15)};form.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,150));form.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));connection.Controls.Add(form);
        string[] names={"iDRAC / iLO address","Username","Password","ipmitool path","nvidia-smi path"};TextBox[] fields={hostBox,userBox,passBox,ipmiBox,gpuBox};
        for(int i=0;i<5;i++){form.RowStyles.Add(new RowStyle(SizeType.Absolute,43));form.Controls.Add(new Label{Text=names[i],AutoSize=true,Padding=new Padding(0,5,0,0)},0,i);fields[i].Dock=DockStyle.Fill;form.Controls.Add(fields[i],1,i);}passBox.UseSystemPasswordChar=true;
        provider.DropDownStyle=ComboBoxStyle.DropDownList;provider.Items.AddRange(new object[]{"Auto","NVIDIA","LibreHardwareMonitor","OpenHardwareMonitor"});provider.SelectedIndex=0;provider.Dock=DockStyle.Fill;
        form.Controls.Add(new Label{Text="GPU provider",AutoSize=true,Padding=new Padding(0,5,0,0)},0,5);form.Controls.Add(provider,1,5);
        gpuScope.DropDownStyle=ComboBoxStyle.DropDownList;gpuScope.Items.AddRange(new object[]{"Configure first","Local GPUs (this Windows computer)","Server sensors only (no chassis-cooled GPUs)"});gpuScope.SelectedIndex=0;gpuScope.Dock=DockStyle.Fill;
        form.Controls.Add(new Label{Text="GPU source",AutoSize=true},0,6);form.Controls.Add(gpuScope,1,6);
        sourceConfirmed.Text="I confirm this GPU source matches this server";sourceConfirmed.AutoSize=true;form.Controls.Add(sourceConfirmed,1,7);
        bundledIpmi.Text="Use built-in IPMI tool (included)";bundledIpmi.AutoSize=true;bundledIpmi.CheckedChanged+=(s,e)=>{ipmiBox.Enabled=!bundledIpmi.Checked&&!IsRunning&&!observing;if(bundledIpmi.Checked)ipmiBox.Text=BundledTools.IpmiPath(root);};form.Controls.Add(bundledIpmi,1,11);
        save.Text="Save connection";save.Width=160;save.Click+=(s,e)=>SaveSettings();form.Controls.Add(save,1,8);
        nativeProfile.DropDownStyle=ComboBoxStyle.DropDownList;nativeProfile.Items.AddRange(new object[]{"IncreasedCooling","OptimalCooling","MaximumCooling","EnhancedCooling","FullSpeed","Standard","Optimal","HeavyIO","PUE2","FullSpeedOverride","DellMinimum"});nativeProfile.SelectedIndex=0;nativeProfile.Width=360;form.Controls.Add(new Label{Text="Native cooling profile",AutoSize=true},0,9);form.Controls.Add(nativeProfile,1,9);nativeMinimumEnabled.Text="HPE min fan %";nativeMinimumEnabled.AutoSize=true;form.Controls.Add(nativeMinimumEnabled,0,10);form.Controls.Add(nativeMinimum,1,10);
        foreach(Control field in form.Controls)form.SetRow(field,form.GetRow(field)+1);form.RowStyles.Insert(0,new RowStyle(SizeType.Absolute,43));form.Height+=43;
        form.Controls.Add(new Label{Text="Server name",AutoSize=true,Padding=new Padding(0,5,0,0)},0,0);
        var nameRow=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2};nameRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));nameRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,135));serverNameBox.BackColor=card;serverNameBox.ForeColor=ink;serverNameBox.Dock=DockStyle.Fill;serverNameBox.MaxLength=80;nameRow.Controls.Add(serverNameBox,0,0);var rename=new ReadableButton{Text="Rename server",Dock=DockStyle.Fill};rename.Click+=(s,e)=>RenameProfile();nameRow.Controls.Add(rename,1,0);form.Controls.Add(nameRow,1,0);
        var curveTab=new TabPage("Fan curves"){BackColor=bg,ForeColor=ink};curveTab.Controls.Add(curveEditor);tabs.TabPages.Add(curveTab);curveEditor.SaveRequested+=()=>{try{SaveCurveConfiguration();}catch(Exception ex){MessageBox.Show(this,ex.Message,"Cannot save curve");}};curveEditor.RestoreRequested+=()=>RequestStop();
        var logTab=new TabPage("Activity");messages.Multiline=true;messages.ReadOnly=true;messages.ScrollBars=ScrollBars.Vertical;messages.Dock=DockStyle.Fill;messages.BackColor=bg;messages.ForeColor=ink;logTab.Controls.Add(messages);tabs.TabPages.Add(logTab);
        var buttons=new BufferedFlowLayoutPanel{AutoScroll=true,Dock=DockStyle.Fill,Padding=new Padding(0,8,0,0)};
        monitor.Text="Monitor only";control.Text="Start cooling";stop.Text="Stop / Dell auto";
        foreach(var b in new[]{monitor,control,stop}){b.Width=154;b.Height=35;b.FlatStyle=FlatStyle.Flat;buttons.Controls.Add(b);}

        var report=new ReadableButton{Text="Hardware support request",Width=205,Height=35};report.Click+=(s,e)=>HardwareSupportReport.Show(this,Snapshot,profileDirectory,()=>Snapshot);buttons.Controls.Add(report);
        monitor.Click+=(s,e)=>StartWorker(false);control.Click+=(s,e)=>StartWorker(true);stop.Click+=(s,e)=>RequestStop();stop.Enabled=false;
        layout.Controls.Add(buttons,0,3);age.Dock=DockStyle.Fill;age.ForeColor=Color.Silver;age.Text="No readings yet";layout.Controls.Add(age,0,4);
        FormClosing+=OnClosing;timer.Interval=1000;timer.Tick+=(s,e)=>RefreshState();timer.Start();
        try { LoadSettings();serverNameBox.Text=ProfileName;curveEditor.LoadConfig(settings,IsNative);ApplyProviderUi(); } catch(Exception ex){Log("Connection settings: "+ex.Message);}
        Shown+=(sender,eventArgs)=>Task.Run(()=>{string detected=DetectLocalMachine();try{if(!IsDisposed)BeginInvoke((Action)(()=>{localMachine=detected;UpdateMachineLabel();}));}catch(InvalidOperationException){}});
    }
    void StyleGrid(DataGridView grid){
        grid.Dock=DockStyle.Fill;grid.ReadOnly=true;grid.AllowUserToAddRows=false;grid.AllowUserToDeleteRows=false;grid.AllowUserToResizeRows=false;
        grid.RowHeadersVisible=false;grid.AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill;grid.BackgroundColor=card;grid.BorderStyle=BorderStyle.None;
        grid.DefaultCellStyle.BackColor=card;grid.DefaultCellStyle.ForeColor=ink;grid.DefaultCellStyle.SelectionBackColor=Color.FromArgb(48,75,98);grid.DefaultCellStyle.SelectionForeColor=Color.White;
        grid.ColumnHeadersDefaultCellStyle.BackColor=Color.FromArgb(37,47,61);grid.ColumnHeadersDefaultCellStyle.ForeColor=ink;grid.EnableHeadersVisualStyles=false;grid.RowTemplate.Height=25;
        grid.ColumnAdded+=(s,e)=>{e.Column.SortMode=DataGridViewColumnSortMode.NotSortable;};
    }
    Control Section(string title,Control content){var p=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,RowCount=2,Margin=new Padding(4)};p.RowStyles.Add(new RowStyle(SizeType.Absolute,29));p.RowStyles.Add(new RowStyle(SizeType.Percent,100));p.Controls.Add(new Label{Text=title,Dock=DockStyle.Fill,ForeColor=Color.LightSteelBlue,Font=new Font("Segoe UI",9,FontStyle.Bold),Padding=new Padding(2,5,0,0)},0,0);p.Controls.Add(content,0,1);return p;}
    public void PreviewSnapshot(string path){localMachine=DetectLocalMachine();var d=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(path));UpdateReadings(d);UpdateMachineLabel();state.Text=Convert.ToString(d["State"]);detail.Text=Convert.ToString(d["Message"]);monitor.Enabled=control.Enabled=save.Enabled=smart.Enabled=false;stop.Enabled=true;}
    void UpdateMachineLabel(){machine.Text=localMachine+"\r\n"+targetMachine;}
    static string DetectLocalMachine(){
        try{
            var options=new EnumerationOptions{Timeout=TimeSpan.FromSeconds(5)};
            using(var search=new ManagementObjectSearcher("root\\cimv2","SELECT Manufacturer,Model,PCSystemType,Name FROM Win32_ComputerSystem",options))
            using(var results=search.Get())foreach(ManagementObject system in results){
                int code=Convert.ToInt32(system["PCSystemType"]);
                string[] types={"Unspecified type","Desktop","Laptop / mobile","Workstation","Enterprise server","Small-office server","Appliance","Performance server","Tablet"};
                string type=code>=0&&code<types.Length?types[code]:"Unknown type";
                return "Running on: "+Convert.ToString(system["Manufacturer"])+" "+Convert.ToString(system["Model"])+"  |  "+type+"  |  "+Convert.ToString(system["Name"]);
            }
            return "Running on: hardware identity unavailable";
        }catch{return "Running on: hardware identity unavailable";}
    }
    void UpdateReadings(Dictionary<string,object> d){
        Snapshot=d;
        curveEditor.Feed(d);
        if(d.ContainsKey("TargetIdentity")&&Obj(d["TargetIdentity"])!=null){var target=Obj(d["TargetIdentity"]);targetMachine="Cooling target: "+Val(target,"Manufacturer","")+" "+Val(target,"Model","")+"  |  Profile: "+Val(target,"CoolingProfile","")+"  |  "+Val(target,"IdracGeneration","")+"  |  Firmware: "+Val(target,"FirmwareRevision","");UpdateMachineLabel();}
        else if(observing){targetMachine="Cooling target: "+Val(d,"IdracHost","")+"  |  External feed (model not included)";UpdateMachineLabel();}
        var i=Obj(d["Ipmi"]);var g=Obj(d["Gpu"]);
        if(i!=null||g!=null){DateTime stamp;if(DateTime.TryParse(Convert.ToString(d["Time"]),null,System.Globalization.DateTimeStyles.RoundtripKind,out stamp)){trends.Feed(stamp,new double?[]{Number(g,"Temp"),Number(i,"CpuMax"),Number(i,"Exhaust"),Number(i,"Inlet"),Number(i,"SystemMax")});powerTrends.Feed(stamp,new double?[]{Number(i,"Watts"),FleetReading.GpuTotal(g),null,null,null});}}
        values[0].Text=Val(g,"Temp"," C");values[1].Text=Val(i,"CpuMax"," C");values[2].Text=Val(i,"Exhaust"," C");
        int command=Convert.ToInt32(d["Fan"]);values[3].Text=command<0?"--":command+"%";
        values[4].Text=Val(i,"Inlet"," C");values[5].Text=Val(i,"Watts"," W");values[6].Text=Val(g,"Util"," %");values[7].Text=Val(g,"Power"," W");
        gpus.Rows.Clear();temperatures.Rows.Clear();fans.Rows.Clear();fans.Columns[1].HeaderText="Measured speed";
        if(g!=null&&g.ContainsKey("Cards")){var cards=g["Cards"] as IEnumerable;if(cards!=null)foreach(var item in cards){var c=Obj(item);gpus.Rows.Add(Val(c,"Name",""),Val(c,"Vendor",""),Val(c,"Provider",""),Val(c,"Temp",""),Val(c,"Util",""),Val(c,"Power",""),Val(c,"Bus",""),Val(c,"Id",""));}}
        if(i!=null&&i.ContainsKey("Fans")){var list=i["Fans"] as IEnumerable;if(list!=null)foreach(var item in list){var f=Obj(item);fans.Rows.Add(Val(f,"Name",""),Val(f,"Value",f!=null&&f.ContainsKey("Units")?" "+Convert.ToString(f["Units"]):" RPM"));}}
        if(i!=null&&i.ContainsKey("Temps")){int cpu=0;var list=i["Temps"] as IEnumerable;if(list!=null)foreach(var item in list){var t=Obj(item);string name=Val(t,"Name","");if(name=="Temp")name="CPU "+(++cpu);temperatures.Rows.Add(name,Val(t,"Value",""));}}
        summary.Text="Management: "+Val(d,"IdracHost","")+"    |    Cooldown: "+Val(d,"CooldownRemaining"," s")+"    |    Uptime: "+Val(d,"UptimeSeconds"," s")+
            "\r\nAdditional system maximum: "+Val(i,"SystemMax"," C")+"    |    "+Val(i,"HottestSystemSensor","");
        if(g!=null&&g.ContainsKey("Warning")&&!String.IsNullOrEmpty(Convert.ToString(g["Warning"])))summary.Text+="\r\n"+Convert.ToString(g["Warning"]);
    }
    void Log(string text){messages.AppendText(DateTime.Now.ToString("HH:mm:ss")+"  "+text+Environment.NewLine);}
    void ValidateBundle(){foreach(string file in new[]{"Controller.ps1","R730-SmartControl.ps1","GpuProviders.ps1","SystemIdentity.ps1","DellCompatibility.ps1","HardwareDiscovery.ps1","CustomFanCurves.ps1"})if(!File.Exists(Path.Combine(root,file)))throw new Exception("Missing "+file);LoadSettings();}
    string Protect(string text){return Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(text),null,DataProtectionScope.CurrentUser));}
    string Unprotect(string text){if(String.IsNullOrEmpty(text))return "";return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(text),null,DataProtectionScope.CurrentUser));}
    void LoadSettings(){settings=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(profileDirectory,"settings.json")));smart.Checked=settings.ContainsKey("Smart")&&Convert.ToBoolean(settings["Smart"]);provider.SelectedItem=settings.ContainsKey("GpuProvider")?Convert.ToString(settings["GpuProvider"]):"Auto";gpuScope.SelectedIndex=settings.ContainsKey("GpuMode")&&Convert.ToString(settings["GpuMode"])=="Local"?1:settings.ContainsKey("GpuMode")&&Convert.ToString(settings["GpuMode"])=="ServerOnly"?2:0;sourceConfirmed.Checked=settings.ContainsKey("GpuSourceConfirmed")&&Convert.ToBoolean(settings["GpuSourceConfirmed"]);hostBox.Text=(string)settings["IdracHost"];trends.SetTarget(HistoryFile(hostBox.Text));powerTrends.SetTarget(HistoryFile(hostBox.Text).Replace("temperature-","power-"));userBox.Text=(string)settings["IdracUser"];bundledIpmi.Checked=BundledTools.PreferBundled(root,settings);ipmiBox.Text=bundledIpmi.Checked?BundledTools.IpmiPath(root):(string)settings["IpmiExe"];ipmiBox.Enabled=!bundledIpmi.Checked;gpuBox.Text=(string)settings["NvidiaSmi"];passBox.Text=Unprotect((string)settings["IdracPassProtected"]);nativeProfile.SelectedItem=settings.ContainsKey("NativeCoolingProfile")?Convert.ToString(settings["NativeCoolingProfile"]):settings.ContainsKey("ManagementProvider")&&Convert.ToString(settings["ManagementProvider"])=="DellRedfish"?"DellMinimum":settings.ContainsKey("ManagementProvider")&&Convert.ToString(settings["ManagementProvider"])=="HPE"?"IncreasedCooling":settings.ContainsKey("ManagementProvider")&&Convert.ToString(settings["ManagementProvider"])=="Supermicro"?"FullSpeed":"FullSpeedOverride";nativeMinimumEnabled.Checked=settings.ContainsKey("NativeMinimumEnabled")&&Convert.ToBoolean(settings["NativeMinimumEnabled"]);nativeMinimum.Value=settings.ContainsKey("NativeMinimum")?Math.Max(0,Math.Min(100,Convert.ToDecimal(settings["NativeMinimum"]))):50;}
    void SaveSettings(){try{
        ProfileStore.Validate(ProfileName,hostBox.Text);
        string parent=Path.GetDirectoryName(profileDirectory);
        if(Path.GetFileName(parent)=="Profiles")foreach(string sibling in Directory.GetDirectories(parent))if(sibling!=profileDirectory&&File.Exists(Path.Combine(sibling,"settings.json"))&&ProfileStore.Normalize(Convert.ToString(ProfileStore.Read(sibling)["IdracHost"]))==ProfileStore.Normalize(hostBox.Text))throw new Exception("Another profile already uses that iDRAC address.");
        string profileName=ProfileName;string management=IsNative?Convert.ToString(settings["ManagementProvider"]):"Dell";
        var updated=new Dictionary<string,object>{{"UseBundledIpmi",bundledIpmi.Checked},{"NativeCoolingProfile",Convert.ToString(nativeProfile.SelectedItem)},{"NativeMinimumEnabled",nativeMinimumEnabled.Checked},{"NativeMinimum",(int)nativeMinimum.Value},{"ManagementProvider",management},{"Smart",smart.Checked},{"ProfileName",profileName},{"GpuMode",gpuScope.SelectedIndex==1?"Local":gpuScope.SelectedIndex==2?"ServerOnly":"Unconfigured"},{"GpuSourceConfirmed",sourceConfirmed.Checked},{"GpuProvider",Convert.ToString(provider.SelectedItem)},{"IdracHost",hostBox.Text.Trim()},{"IdracUser",userBox.Text.Trim()},{"IpmiExe",ipmiBox.Text.Trim()},{"NvidiaSmi",gpuBox.Text.Trim()},{"IdracPassProtected",Protect(passBox.Text)}};foreach(var pair in updated)settings[pair.Key]=pair.Value;File.WriteAllText(Path.Combine(profileDirectory,"settings.json"),json.Serialize(settings));ApplyProviderUi();Log("Connection saved for this Windows user.");}catch(Exception ex){MessageBox.Show(this,ex.Message,"Save failed");}}
    static string Quote(string text){if(text.Contains("\"")||text.EndsWith("\\"))throw new Exception("Invalid launch path");return "\""+text+"\"";}
    void SaveCurveConfiguration(bool cancelRetry=true){
        if(IsRunning||observing)throw new Exception("Stop this profile before saving curve changes.");
        if(IsNative)return;if(cancelRetry)CancelReconnect(false);settings=ProfileStore.Read(profileDirectory);smart.Checked=curveEditor.CaptureSettings(settings);WriteProfile(settings);if(cancelRetry){state.Text="CURVES SAVED";detail.Text="Ready for the next Start cooling; automatic reconnect is cancelled.";stop.Enabled=false;}Log("Fan mode/curves saved for the next cooling start. Original thermal safety floors remain active.");
    }
    void WriteProfile(Dictionary<string,object> data){string path=Path.Combine(profileDirectory,"settings.json"),temp=path+".edit-"+Guid.NewGuid().ToString("N");try{File.WriteAllText(temp,json.Serialize(data));File.Replace(temp,path,null);}finally{if(File.Exists(temp))File.Delete(temp);}}
    void RenameProfile(){try{string name=serverNameBox.Text.Trim();ProfileStore.Validate(name,hostBox.Text);var latest=ProfileStore.Read(profileDirectory);latest["ProfileName"]=name;WriteProfile(latest);settings["ProfileName"]=name;serverNameBox.Text=name;Log("Server renamed to "+name+".");}catch(Exception ex){MessageBox.Show(this,ex.Message,"Could not rename server");}}
    static void CurveAndNameSelfTest(){
        FanCurveEditor.SelfTest();string dir=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Profiles","CurveNameFixture-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);
        var config=ProfileStore.Read(AppDomain.CurrentDomain.BaseDirectory);config["ProfileName"]="Before rename";config["ControlOnStartup"]=false;File.WriteAllText(Path.Combine(dir,"settings.json"),ProfileStore.Json.Serialize(config));
        try{using(var form=new FanApp(dir)){form.serverNameBox.Text="Media R730";form.RenameProfile();var saved=ProfileStore.Read(dir);if(form.ProfileName!="Media R730"||Convert.ToString(saved["ProfileName"])!="Media R730"||Convert.ToString(saved["IdracHost"])!=Convert.ToString(config["IdracHost"])||Convert.ToString(saved["IdracPassProtected"])!=Convert.ToString(config["IdracPassProtected"]))throw new Exception("Rename changed endpoint or credentials");var tab=(TabControl)form.curveEditor.Parent.Parent;if(tab.TabPages[2].Text!="Fan curves"||tab.TabPages[3].Text!="Activity")throw new Exception("Fan curves tab order incorrect");}}finally{foreach(string file in Directory.GetFiles(dir))File.Delete(file);Directory.Delete(dir);}
    }
    readonly ReconnectPolicy reconnect=new ReconnectPolicy();string reconnectCause="";
    void CancelReconnect(bool saveStop){reconnect.Cancel();if(saveStop&&settings!=null){settings["ControlOnStartup"]=false;try{File.WriteAllText(Path.Combine(profileDirectory,"settings.json"),json.Serialize(settings));}catch(Exception ex){Log("Could not save stopped startup preference: "+ex.Message);}}}
    void StartWorker(bool live,bool automaticRetry=false){
        if(worker!=null && !worker.HasExited)return;
        if(!automaticRetry){if(!IsNative)reconnect.Start(live);else reconnect.Cancel();}reconnect.Due=null;
        try {
            if(live&&!automaticRetry&&!IsNative)SaveCurveConfiguration(false);
            bool selectedBundled=bundledIpmi.Checked;bool selectedSmart=smart.Checked;string selectedNative=Convert.ToString(nativeProfile.SelectedItem);bool selectedMinimum=nativeMinimumEnabled.Checked;int minimum=(int)nativeMinimum.Value;ValidateBundle();bundledIpmi.Checked=selectedBundled;if(!IsNative&&selectedBundled)BundledTools.Validate(root);settings["UseBundledIpmi"]=selectedBundled;if(IsNative){selectedSmart=false;if(!IsLocal&&(!File.Exists(Path.Combine(root,"RedfishWorker.ps1"))||!File.Exists(Path.Combine(root,"Redfish-Control.ps1"))))throw new Exception("Missing Redfish control bundle");}smart.Checked=selectedSmart;nativeProfile.SelectedItem=selectedNative;nativeMinimumEnabled.Checked=selectedMinimum;nativeMinimum.Value=minimum;settings["Smart"]=selectedSmart;settings["NativeCoolingProfile"]=selectedNative;settings["NativeMinimumEnabled"]=selectedMinimum;settings["NativeMinimum"]=minimum;settings["ControlOnStartup"]=live;File.WriteAllText(Path.Combine(profileDirectory,"settings.json"),json.Serialize(settings)); string run=DateTime.Now.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N").Substring(0,6);
            string runs=Path.Combine(profileDirectory,"Runs");Directory.CreateDirectory(runs);
            statusFile=Path.Combine(runs,run+".json");stopFile=Path.Combine(runs,run+".stop");logFile=Path.Combine(runs,run+".log");
            string args="-NoProfile -ExecutionPolicy Bypass -File "+Quote(Path.Combine(root,IsNative?"RedfishWorker.ps1":"Controller.ps1"))+" -SettingsPath "+Quote(Path.Combine(profileDirectory,"settings.json"))+" -StatusPath "+Quote(statusFile)+" -StopPath "+Quote(stopFile)+(live?" -Live":"")+(!IsNative&&smart.Checked?" -Smart":"");
            string executable=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe");if(IsLocal){executable=Path.Combine(root,"LocalHardware","LocalWorker.exe");args=Quote(Path.Combine(profileDirectory,"settings.json"))+" "+Quote(statusFile)+" "+Quote(stopFile)+(live?" --control":"");}
            worker=new Process();worker.StartInfo=new ProcessStartInfo(executable,args){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=root};
            lock(gate)output.Clear();worker.OutputDataReceived+=(s,e)=>CaptureLine(e.Data);worker.ErrorDataReceived+=(s,e)=>CaptureLine(e.Data);
            trends.NewSession();powerTrends.NewSession();worker.Start();worker.BeginOutputReadLine();worker.BeginErrorReadLine();started=DateTime.Now;stopping=false;restorationFailed=false;lastStatus="";
            monitor.Enabled=control.Enabled=smart.Enabled=save.Enabled=provider.Enabled=gpuScope.Enabled=sourceConfirmed.Enabled=bundledIpmi.Enabled=nativeProfile.Enabled=nativeMinimum.Enabled=nativeMinimumEnabled.Enabled=false;stop.Enabled=true;
            foreach(var t in new[]{hostBox,userBox,passBox,ipmiBox,gpuBox})t.Enabled=false;
            gpus.Rows.Clear();foreach(var label in values)label.Text="--";fans.Rows.Clear();
            state.Text=live?"STARTING COOLING":"STARTING READ-ONLY MONITOR";detail.Text="Checking server identity and telemetry before any takeover.";
            Log(live?"Cooling worker started. Safety checks precede manual mode.":"Read-only monitor started. No fan writes.");
        }catch(Exception ex){reconnect.Cancel();if(worker!=null){worker.Dispose();worker=null;}Log(ex.Message);if(!automaticRetry)MessageBox.Show(this,ex.Message,"Cannot start");}
    }
    void CaptureLine(string line){if(line==null)return;lock(gate){output.AppendLine(line);if(output.Length>120000)output.Remove(0,40000);}try{lock(gate)File.AppendAllText(logFile,line+Environment.NewLine);}catch{}}
    public string BeginSafeShutdown(){
        CancelReconnect(false);
        if(!IsRunning&&(restorationFailed||File.Exists(Path.Combine(profileDirectory,"Cooling-Recovery.json"))))throw new Exception("Cooling restoration needs attention. Restart this profile monitor to retry native recovery before exiting.");
        if(!IsRunning&&!observing){string feed=FeedDiscovery.Find(root,profileDirectory,hostBox.Text);if(feed!=null)ObserveExisting(feed);}
        if(!IsRunning&&!observing)return null;
        var data=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(statusFile));
        if(ProfileStore.Normalize(Convert.ToString(data["IdracHost"]))!=ProfileStore.Normalize(hostBox.Text))throw new Exception("Server feed target mismatch");
        DateTime feedTime;if(!IsRunning&&(!DateTime.TryParse(Convert.ToString(data["Time"]),null,System.Globalization.DateTimeStyles.RoundtripKind,out feedTime)||(DateTime.UtcNow-feedTime.ToUniversalTime()).TotalSeconds>45||(DateTime.UtcNow-feedTime.ToUniversalTime()).TotalSeconds< -5))throw new Exception("Live feed is stale; shutdown cannot be confirmed safely");
        string target=IsRunning?stopFile:Path.ChangeExtension(statusFile,".stop");
        if(!String.Equals(Path.GetDirectoryName(Path.GetFullPath(target)),Path.GetDirectoryName(Path.GetFullPath(statusFile)),StringComparison.OrdinalIgnoreCase)||Path.GetExtension(statusFile)!=".json")throw new Exception("Invalid controller stop path");
        File.WriteAllText(target,"stop");return statusFile;
    }
    void RequestStop(){CancelReconnect(true);if(worker==null&&!observing){stop.Enabled=false;state.Text="STOPPED BY USER";detail.Text="Automatic reconnect cancelled.";}if(observing){observing=false;stop.Text="Stop / Dell auto";stop.Enabled=false;monitor.Enabled=control.Enabled=save.Enabled=smart.Enabled=provider.Enabled=gpuScope.Enabled=sourceConfirmed.Enabled=bundledIpmi.Enabled=nativeProfile.Enabled=nativeMinimum.Enabled=nativeMinimumEnabled.Enabled=true;foreach(var field in new[]{hostBox,userBox,passBox,ipmiBox,gpuBox})field.Enabled=true;state.Text="VIEW STOPPED";detail.Text="External controller continues independently.";Log("Stopped viewing. External cooling was not changed.");ApplyProviderUi();return;}if(worker==null||worker.HasExited)return;try{File.WriteAllText(stopFile,"stop");stopping=true;stop.Enabled=false;state.Text="STOPPING";detail.Text="Waiting for the current request, then restoring Dell control if needed.";Log("Graceful stop requested; worker is not forcibly terminated.");}catch(Exception ex){Log("Stop request failed: "+ex.Message);}}
    static double? Number(Dictionary<string,object> d,string key){if(d==null||!d.ContainsKey(key)||d[key]==null)return null;try{double n=Convert.ToDouble(d[key],System.Globalization.CultureInfo.InvariantCulture);return Double.IsNaN(n)||Double.IsInfinity(n)?(double?)null:n;}catch{return null;}}
    string HistoryFile(string address){using(var hash=SHA256.Create()){string key=BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(ProfileStore.Normalize(address)))).Replace("-","").Substring(0,16);return Path.Combine(profileDirectory,"temperature-"+key+".jsonl");}}
    static Dictionary<string,object> Obj(object x){return x as Dictionary<string,object>;}
    static string Val(Dictionary<string,object> d,string key,string suffix){return d!=null&&d.ContainsKey(key)&&d[key]!=null?Convert.ToString(d[key])+suffix:"--";}
    void RefreshState(){
        trends.Tick();powerTrends.Tick();
        curveEditor.SetRunning(IsRunning,observing);
        if(reconnect.Due.HasValue&&worker==null){
            stop.Enabled=true;state.Text="RECONNECT WAIT";state.ForeColor=Color.Orange;
            detail.Text="Retry "+reconnect.Attempts+" in "+Math.Max(0,(int)(reconnect.Due.Value-DateTime.UtcNow).TotalSeconds)+" s. "+reconnectCause+" Fresh telemetry required; Stop cancels retries.";
            if(DateTime.UtcNow>=reconnect.Due.Value)StartWorker(reconnect.Live,true);
        }
        if(worker==null&&!observing)return;
        try{
            if(File.Exists(statusFile)){
                string raw;using(var fs=new FileStream(statusFile,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var reader=new StreamReader(fs))raw=reader.ReadToEnd();
                var d=json.Deserialize<Dictionary<string,object>>(raw);
                if(observing&&(!d.ContainsKey("IdracHost")||ProfileStore.Normalize(Convert.ToString(d["IdracHost"]))!=ProfileStore.Normalize(hostBox.Text)))throw new Exception("Status feed target changed; readings rejected");
                DateTime time=DateTime.Parse((string)d["Time"],null,System.Globalization.DateTimeStyles.RoundtripKind);
                double seconds=Math.Max(0,(DateTime.Now-time).TotalSeconds);age.Text=(observing?"VIEW ONLY  |  ":"")+"Last update "+((int)seconds)+" s ago  |  "+(Convert.ToBoolean(d["Live"])?"LIVE CONTROL":"READ ONLY")+"  |  "+(Convert.ToBoolean(d["Smart"])?"Adaptive curves":d.ContainsKey("FanCurveMode")?Convert.ToString(d["FanCurveMode"])+" mode":IsNative?"Native cooling":"Original curves");
                if(raw!=lastStatus){lastStatus=raw;string mode=(string)d["State"];if(reconnect.Wanted&&d.ContainsKey("UptimeSeconds")&&Convert.ToDouble(d["UptimeSeconds"])>=60&&(mode=="NORMAL"||mode=="GPU LOAD"||mode=="COOLDOWN"||mode=="MONITORING"))reconnect.Attempts=0;if(mode=="RESTORE FAILED")restorationFailed=true;if(!stopping){state.Text=(observing?"VIEW / ":"")+mode;detail.Text=(observing?"External controller: ":"")+(string)d["Message"];}state.ForeColor=mode.Contains("FAULT")||mode.Contains("FAILED")?Color.Salmon:Color.Turquoise;
                    UpdateReadings(d);
                }
                if(seconds>45&&(observing||(worker!=null&&!worker.HasExited))&&!stopping){state.Text="WAITING / READINGS STALE";state.ForeColor=Color.Orange;}
            }else age.Text="Starting: "+((int)(DateTime.Now-started).TotalSeconds)+" s elapsed";
        }catch(Exception ex){age.Text="Waiting for complete status: "+ex.Message;}
        if(worker!=null&&worker.HasExited){
            worker.WaitForExit();int code=worker.ExitCode;Log("Worker exited ("+code+"). "+detail.Text);
            Dictionary<string,object> exitStatus=null;try{exitStatus=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(statusFile));}catch{}
            if(exitStatus!=null&&exitStatus.ContainsKey("ExitReason")){string reason=Convert.ToString(exitStatus["ExitReason"]);string failure=exitStatus.ContainsKey("FailureMessage")?Convert.ToString(exitStatus["FailureMessage"]):"";Log("Exit reason: "+reason+". "+failure);reconnectCause=reason+": "+failure;detail.Text="Exit: "+reason+". "+failure;}
            bool retry=!stopping&&!closing&&!IsNative&&reconnect.Schedule(exitStatus,DateTime.UtcNow);
            if(!retry)reconnect.Cancel();
            if(stopping){stopping=false;try{var final=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(statusFile));state.Text=(string)final["State"];detail.Text=(string)final["Message"];}catch{state.Text="STOPPED - CHECK ACTIVITY";}}
            if(code!=0){state.Text="STOPPED - CHECK ACTIVITY";state.ForeColor=Color.Salmon;}
            worker.Dispose();worker=null;monitor.Enabled=control.Enabled=smart.Enabled=save.Enabled=provider.Enabled=gpuScope.Enabled=sourceConfirmed.Enabled=bundledIpmi.Enabled=nativeProfile.Enabled=nativeMinimum.Enabled=nativeMinimumEnabled.Enabled=true;stop.Enabled=false;
            foreach(var t in new[]{hostBox,userBox,passBox,ipmiBox,gpuBox})t.Enabled=true;
            ApplyProviderUi();if(closing){if(state.Text.Contains("FAILED")){closing=false;MessageBox.Show(this,detail.Text,"Cooling restoration needs attention");}else Close();}
            if(retry){stop.Enabled=true;state.Text="RECONNECT WAIT";Log("Automatic reconnect scheduled; attempt "+reconnect.Attempts+". Stop cancels it.");}
        }
    }
    void OnClosing(object sender,FormClosingEventArgs e){if(worker!=null&&!worker.HasExited){e.Cancel=true;closing=true;RequestStop();}}
    protected override void Dispose(bool disposing){if(disposing){timer.Stop();timer.Dispose();}base.Dispose(disposing);}
}

// Standard WinForms disabled buttons ignore ForeColor in some Windows themes.
// Paint every state explicitly so labels remain readable on this dark surface.
public class ReadableButton : Button {
    public ReadableButton(){SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);UseVisualStyleBackColor=false;Cursor=Cursors.Hand;}
    protected override void OnEnabledChanged(EventArgs e){base.OnEnabledChanged(e);Invalidate();}
    protected override void OnPaint(PaintEventArgs e){
        Color fill=Enabled?Color.FromArgb(40,79,108):Color.FromArgb(38,45,55);
        Color text=Enabled?Color.White:Color.FromArgb(181,190,203);
        e.Graphics.Clear(fill);using(var pen=new Pen(Enabled?Color.FromArgb(102,163,204):Color.FromArgb(94,106,122)))e.Graphics.DrawRectangle(pen,0,0,Width-1,Height-1);
        TextRenderer.DrawText(e.Graphics,Text,Font,ClientRectangle,text,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
        if(Focused&&Enabled)ControlPaint.DrawFocusRectangle(e.Graphics,Rectangle.Inflate(ClientRectangle,-4,-4),text,fill);
    }
}
public class ReadableCheckBox : CheckBox {
    public ReadableCheckBox(){SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
    protected override void OnEnabledChanged(EventArgs e){base.OnEnabledChanged(e);Invalidate();}
    protected override void OnCheckedChanged(EventArgs e){base.OnCheckedChanged(e);Invalidate();}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.Clear(Parent==null?BackColor:Parent.BackColor);
        Color text=Enabled?Color.FromArgb(226,234,243):Color.FromArgb(181,190,203);
        int y=(Height-14)/2;using(var brush=new SolidBrush(Color.FromArgb(38,45,55)))e.Graphics.FillRectangle(brush,0,y,14,14);
        using(var pen=new Pen(text)){e.Graphics.DrawRectangle(pen,0,y,14,14);if(Checked){e.Graphics.DrawLine(pen,3,y+7,6,y+10);e.Graphics.DrawLine(pen,6,y+10,11,y+3);}}
        TextRenderer.DrawText(e.Graphics,Text,Font,new Rectangle(21,0,Math.Max(0,Width-21),Height),text,TextFormatFlags.Left|TextFormatFlags.VerticalCenter);
        if(Focused&&Enabled)ControlPaint.DrawFocusRectangle(e.Graphics,Rectangle.Inflate(ClientRectangle,-1,-1),text,BackColor);
    }
}
