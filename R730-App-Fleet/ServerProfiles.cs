using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public static class ProfileStore {
    public static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    public static string Normalize(string address){return address.Trim().TrimEnd('.').ToLowerInvariant();}
    public static string Protect(string value){return Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(value),null,DataProtectionScope.CurrentUser));}
    public static void Validate(string name,string address){if(String.IsNullOrWhiteSpace(name)||name.Length>80)throw new Exception("Enter a server name (up to 80 characters).");if(Uri.CheckHostName(Normalize(address))==UriHostNameType.Unknown)throw new Exception("Enter a valid iDRAC hostname or IP address.");}
    public static Dictionary<string,object> Read(string directory){return Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(directory,"settings.json")));}
    public static string Add(string profiles,string seed,string name,string address,string user,string password,string managementProvider="Dell"){
        Validate(name,address);if(String.IsNullOrWhiteSpace(user)||String.IsNullOrEmpty(password))throw new Exception("Enter this server's username and password.");
        Directory.CreateDirectory(profiles);
        foreach(string existing in Directory.GetDirectories(profiles)){if(File.Exists(Path.Combine(existing,"settings.json"))&&Normalize(Convert.ToString(Read(existing)["IdracHost"]))==Normalize(address))throw new Exception("A profile already uses that iDRAC address.");}
        var template=Read(seed);var config=new Dictionary<string,object>{{"UseBundledIpmi",File.Exists(BundledTools.IpmiPath(seed))},{"ManagementProvider",managementProvider},{"ProfileName",name.Trim()},{"IdracHost",Normalize(address)},{"IdracUser",user.Trim()},{"IdracPassProtected",Protect(password)},{"IpmiExe",File.Exists(BundledTools.IpmiPath(seed))?"Bundled":template["IpmiExe"]},{"NvidiaSmi",template["NvidiaSmi"]},{"GpuProvider","Auto"},{"GpuMode","Unconfigured"},{"GpuSourceConfirmed",false}};
        if(!File.Exists(Convert.ToString(config["IpmiExe"])))foreach(string existing in Directory.GetDirectories(profiles)){try{var saved=Read(existing);if(saved.ContainsKey("IpmiExe")&&File.Exists(Convert.ToString(saved["IpmiExe"]))){config["IpmiExe"]=saved["IpmiExe"];break;}}catch{}}
        string directory=Path.Combine(profiles,Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory,"settings.json"),Json.Serialize(config));return directory;
    }
    public static void Migrate(string root,string profiles){
        Directory.CreateDirectory(profiles);if(Directory.GetDirectories(profiles).Length>0)return;
        var config=Read(root);if(!config.ContainsKey("ProfileName"))config["ProfileName"]="Current R730";if(!config.ContainsKey("GpuMode"))config["GpuMode"]="Local";if(!config.ContainsKey("GpuSourceConfirmed"))config["GpuSourceConfirmed"]=true;
        string directory=Path.Combine(profiles,Guid.NewGuid().ToString("N"));Directory.CreateDirectory(directory);File.WriteAllText(Path.Combine(directory,"settings.json"),Json.Serialize(config));
    }
    public static List<string> ImportLegacy(string source,string destination){
        var candidates=new List<string>();string collection=Directory.Exists(Path.Combine(source,"Profiles"))?Path.Combine(source,"Profiles"):source;
        foreach(string directory in Directory.GetDirectories(collection))if(File.Exists(Path.Combine(directory,"settings.json")))candidates.Add(directory);
        if(candidates.Count==0&&File.Exists(Path.Combine(source,"settings.json")))candidates.Add(source);
        var imported=new List<string>();Directory.CreateDirectory(destination);
        foreach(string directory in candidates){
            var config=Read(directory);string management=config.ContainsKey("ManagementProvider")?Convert.ToString(config["ManagementProvider"]):"Dell";
            string address=config.ContainsKey("IdracHost")?Convert.ToString(config["IdracHost"]):"";
            if(management!="Local"&&(!config.ContainsKey("IdracPassProtected")||String.IsNullOrEmpty(Convert.ToString(config["IdracPassProtected"]))))continue;
            Validate(config.ContainsKey("ProfileName")?Convert.ToString(config["ProfileName"]):"Imported server",address);
            if(management!="Local")try{ProtectedData.Unprotect(Convert.FromBase64String(Convert.ToString(config["IdracPassProtected"])),null,DataProtectionScope.CurrentUser);}catch{throw new Exception("The old profile password cannot be decrypted for this Windows user.");}
            string target=null;foreach(string existing in Directory.GetDirectories(destination)){if(!File.Exists(Path.Combine(existing,"settings.json")))continue;var saved=Read(existing);if(Normalize(Convert.ToString(saved["IdracHost"]))!=Normalize(address))continue;string existingType=saved.ContainsKey("ManagementProvider")?Convert.ToString(saved["ManagementProvider"]):"Dell";if(existingType!=management)throw new Exception("The saved endpoint uses a different management interface; check its profile first.");target=existing;break;}
            if(target==null)target=Path.Combine(destination,Guid.NewGuid().ToString("N"));
            if(String.Equals(Path.GetFullPath(target),Path.GetFullPath(directory),StringComparison.OrdinalIgnoreCase))continue;
            config["ManagementProvider"]=management;config["ExternalFeedDirectory"]=Path.Combine(directory,"Runs");
            if(!config.ContainsKey("ProfileName"))config["ProfileName"]="Imported server";
            if(!config.ContainsKey("GpuMode"))config["GpuMode"]="Unconfigured";
            if(!config.ContainsKey("GpuSourceConfirmed"))config["GpuSourceConfirmed"]=false;
            Directory.CreateDirectory(target);string file=Path.Combine(target,"settings.json");if(File.Exists(file))File.Copy(file,Path.Combine(target,"settings.before-import-"+DateTime.UtcNow.ToString("yyyyMMddHHmmssfff")+"-"+Guid.NewGuid().ToString("N")+".json"));
            File.WriteAllText(file,Json.Serialize(config));imported.Add(target);
        }
        return imported;
    }
    public static void SelfTest(string root){
        string test=Path.Combine(root,"ProfileTests-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(test);
        var a=Add(test,root,"Server A","192.0.2.10","alice","fixture-A");var b=Add(test,root,"Server B","192.0.2.11","bob","fixture-B");
        var one=Read(a);var two=Read(b);if(a==b||Convert.ToString(one["IdracUser"])!="alice"||Convert.ToString(two["IdracUser"])!="bob")throw new Exception("Profile isolation failed");
        Func<object,string> decode=x=>Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(Convert.ToString(x)),null,DataProtectionScope.CurrentUser));
        if(decode(one["IdracPassProtected"])!="fixture-A"||decode(two["IdracPassProtected"])!="fixture-B")throw new Exception("Credential isolation failed");
        bool duplicate=false;try{Add(test,root,"Duplicate","192.0.2.10.","x","x");}catch{duplicate=true;}if(!duplicate)throw new Exception("Duplicate target accepted");
        if(Convert.ToString(one["GpuMode"])!="Unconfigured")throw new Exception("New remote profile incorrectly uses local GPU");
        string importedRoot=Path.Combine(test,"Imported");Directory.CreateDirectory(importedRoot);string current=Add(importedRoot,root,"Re-entered A","192.0.2.10","alice","wrong-fixture");one["GpuMode"]="Local";one["GpuSourceConfirmed"]=true;one["IpmiExe"]="E:\\Fixture\\ipmitool.exe";File.WriteAllText(Path.Combine(a,"settings.json"),Json.Serialize(one));var migrated=ImportLegacy(a,importedRoot);var repaired=Read(current);if(migrated.Count!=1||Directory.GetDirectories(importedRoot).Length!=1||Convert.ToString(repaired["GpuMode"])!="Local"||!Convert.ToBoolean(repaired["GpuSourceConfirmed"])||Convert.ToString(repaired["IpmiExe"])!="E:\\Fixture\\ipmitool.exe"||decode(repaired["IdracPassProtected"])!="fixture-A")throw new Exception("Legacy settings merge failed");if(Directory.GetFiles(current,"settings.before-import-*.json").Length!=1)throw new Exception("Import backup missing");foreach(string file in Directory.GetFiles(current))File.Delete(file);Directory.Delete(current);Directory.Delete(importedRoot);
        // Remove only exact fixture files and empty directories created above.
        foreach(var d in new[]{a,b}){File.Delete(Path.Combine(d,"settings.json"));Directory.Delete(d);}Directory.Delete(test);
    }
}

public class ServerManager : Form {
    readonly string root=AppDomain.CurrentDomain.BaseDirectory;
    string profiles;TabControl tabs=new BufferedTabControl();List<FanApp> servers=new List<FanApp>();
    FleetOverview fleet=new FleetOverview();
    Timer timer=new Timer();Label status=new Label();bool shuttingDown=false,exitRequested=false;NotifyIcon tray;ContextMenuStrip trayMenu;
    public ServerManager(){
        Text="Thermal Ops"+(AppUpdates.BetaBuild?" BETA":"")+" - Made by Chris Ramsay 2026";Icon=ThermalBrand.CreateIcon();Size=new Size(Math.Min(1280,Screen.PrimaryScreen.WorkingArea.Width-40),Math.Min(1060,Screen.PrimaryScreen.WorkingArea.Height-40));MinimumSize=new Size(1100,920);StartPosition=FormStartPosition.CenterScreen;
        BackColor=Color.FromArgb(18,23,31);ForeColor=Color.White;Font=new Font("Segoe UI",10);
        profiles=Path.Combine(root,"Profiles");ProfileStore.Migrate(root,profiles);
        var layout=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=3,Padding=new Padding(10)};
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute,82));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,27));Controls.Add(layout);
        var toolbar=new BufferedFlowLayoutPanel{Dock=DockStyle.Fill};var add=new ReadableButton{Text="Add server",Width=150,Height=34};var remove=new ReadableButton{Text="Remove selected",Width=165,Height=34};var stop=new ReadableButton{Text="Stop all / restore auto",Width=190,Height=34};var local=new ReadableButton{Text="Local PC / controllers",Width=205,Height=34};local.Click+=(s,e)=>AddLocalProfile();toolbar.Controls.Add(add);toolbar.Controls.Add(remove);toolbar.Controls.Add(stop);toolbar.Controls.Add(local);var import=new ReadableButton{Text="Import old settings",Width=170,Height=34};import.Click+=(s,e)=>ImportProfiles();toolbar.Controls.Add(import);
        var updates=new ReadableButton{Text="Check for updates",Width=165,Height=34};updates.Click+=(s,e)=>CheckForUpdates(true);toolbar.Controls.Add(updates);layout.Controls.Add(toolbar,0,0);
        tabs.Dock=DockStyle.Fill;var all=new TabPage("Cluster"){BackColor=BackColor};all.Controls.Add(fleet);tabs.TabPages.Add(all);fleet.ServerSelected+=(index)=>{tabs.SelectedIndex=index+1;};layout.Controls.Add(tabs,0,1);status.Dock=DockStyle.Fill;status.ForeColor=Color.LightGray;layout.Controls.Add(status,0,2);
        foreach(string directory in Directory.GetDirectories(profiles)){try{if(File.Exists(Path.Combine(directory,"settings.json")))AddTab(directory);}catch(Exception ex){MessageBox.Show(this,"Could not load profile: "+ex.Message);}}
        add.Click+=(s,e)=>ShowAddServer();
        remove.Click+=(s,e)=>{int index=tabs.SelectedIndex-1;if(index<0)return;var server=servers[index];if(server.IsRunning){MessageBox.Show(this,"Stop this server's worker before removing its profile.");return;}if(MessageBox.Show(this,"Remove this saved profile?","Remove server",MessageBoxButtons.YesNo)!=DialogResult.Yes)return;string file=Path.Combine(server.ProfileDirectory,"settings.json");File.Delete(file);tabs.TabPages.RemoveAt(index+1);servers.RemoveAt(index);server.Dispose();};
        stop.Click+=(s,e)=>{foreach(var server in servers)server.StopCooling();};
        timer.Interval=1000;timer.Tick+=(s,e)=>{
            int active=0,views=0;for(int i=0;i<servers.Count;i++){if(servers[i].IsRunning)active++;if(servers[i].IsObserving)views++;tabs.TabPages[i+1].Text=servers[i].ProfileName+" - "+servers[i].CurrentState;}
            RefreshFleet();
            status.Text=servers.Count+" saved servers | "+active+" workers active | "+views+" read-only views | External controllers continue independently";
            if(shuttingDown&&active==0){foreach(var server in servers)if(server.RestorationFailed){shuttingDown=false;exitRequested=false;ShowDashboard();MessageBox.Show(this,"A server reported restoration failure. Check its Activity and restore Dell cooling manually.");return;}Close();}
        };timer.Start();RefreshFleet();
        if(!FanApp.PreviewMode){
            trayMenu=new ContextMenuStrip();var heading=new ToolStripMenuItem("Thermal Ops"){Enabled=false};trayMenu.Items.Add(heading);trayMenu.Items.Add(new ToolStripMenuItem("Made by Chris Ramsay 2026"){Enabled=false});trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add("Dashboard",null,(s,e)=>ShowDashboard());trayMenu.Items.Add("Add server",null,(s,e)=>{ShowDashboard();ShowAddServer();});trayMenu.Items.Add("Local PC / controllers",null,(s,e)=>{ShowDashboard();AddLocalProfile();});trayMenu.Items.Add(new ToolStripSeparator());trayMenu.Items.Add("Exit / restore defaults",null,(s,e)=>BeginExit());
            trayMenu.Items.Insert(trayMenu.Items.Count-2,new ToolStripMenuItem("Check for updates",null,(s,e)=>CheckForUpdates(true)));
            var autoUpdates=new ToolStripMenuItem("Check for updates at startup"){CheckOnClick=true,Checked=AppUpdates.CheckOnStartup};autoUpdates.CheckedChanged+=(s,e)=>AppUpdates.CheckOnStartup=autoUpdates.Checked;trayMenu.Items.Insert(trayMenu.Items.Count-2,autoUpdates);
            var betaUpdates=new ToolStripMenuItem("Include BETA updates"){CheckOnClick=true,Checked=AppUpdates.IncludeBeta};betaUpdates.CheckedChanged+=(s,e)=>AppUpdates.IncludeBeta=betaUpdates.Checked;trayMenu.Items.Insert(trayMenu.Items.Count-2,betaUpdates);
            tray=new NotifyIcon{Text="Thermal Ops",Icon=ThermalBrand.CreateIcon(),ContextMenuStrip=trayMenu,Visible=true};tray.DoubleClick+=(s,e)=>ShowDashboard();
        }
        Shown+=(s,e)=>{if(!FanApp.PreviewMode && AppUpdates.CheckOnStartup && (Environment.GetCommandLineArgs().Length==1 || Array.IndexOf(Environment.GetCommandLineArgs(),"--startup")>=0))CheckForUpdates(false);};
        FormClosed+=(s,e)=>{timer.Stop();timer.Dispose();if(tray!=null){tray.Visible=false;tray.Dispose();}if(trayMenu!=null)trayMenu.Dispose();};
        FormClosing+=(s,e)=>{if(e.CloseReason==CloseReason.UserClosing&&!exitRequested&&!FanApp.PreviewMode){e.Cancel=true;Hide();ShowInTaskbar=false;return;}foreach(var server in servers)if(server.IsRunning){e.Cancel=true;shuttingDown=true;foreach(var child in servers)child.StopCooling();break;}};
    }
    public static void TraySelfTest(){using(var f=new ServerManager()){f.Show();Application.DoEvents();if(f.tray==null||!f.tray.Visible||f.trayMenu.Items[0].Text!="Thermal Ops")throw new Exception("Tray menu missing");f.Close();Application.DoEvents();if(f.IsDisposed||f.Visible||f.ShowInTaskbar)throw new Exception("Close did not hide to tray");f.ShowDashboard();if(!f.Visible||!f.ShowInTaskbar||f.tabs.SelectedIndex!=0)throw new Exception("Dashboard restore failed");f.exitRequested=true;f.Close();if(!f.IsDisposed)throw new Exception("Explicit exit failed");}}
    bool checkingUpdate;
    async void CheckForUpdates(bool manual){
        if(checkingUpdate||exitRequested)return;checkingUpdate=true;
        try{
            string kind=AppUpdates.InstallerKind();
            var update=await System.Threading.Tasks.Task.Run(()=>AppUpdates.Check(kind));
            if(IsDisposed||exitRequested)return;
            if(update==null){if(manual)MessageBox.Show(this,"You are up to date ("+AppUpdates.Current.ToString(3)+").","Thermal Ops updates");return;}
            ShowDashboard();
            if(kind==null){if(MessageBox.Show(this,"Version "+update.Version.ToString(3)+" is available. This is a portable or unrecognised installation. Open the download page?","Thermal Ops updates",MessageBoxButtons.YesNo)==DialogResult.Yes)System.Diagnostics.Process.Start(AppUpdates.Releases);return;}
            if(MessageBox.Show(this,"Thermal Ops "+update.Version.ToString(3)+(update.IsBeta?" BETA":"")+" is available. Installed: "+AppUpdates.Current.ToString(3)+".\n\nDownload the "+kind.ToUpperInvariant()+" update? Cooling continues during download. You will then confirm safe shutdown before setup opens.\n\nRelease notes: "+AppUpdates.Releases,"Update available",MessageBoxButtons.YesNo)!=DialogResult.Yes)return;
            manual=true;
            status.Text="Downloading and verifying Thermal Ops update...";
            string installer=await System.Threading.Tasks.Task.Run(()=>AppUpdates.Download(update));
            if(IsDisposed||exitRequested)return;
            if(MessageBox.Show(this,"The installer is downloaded and verified. Stop controllers, restore default cooling and upgrade now?\n\nIf you cancel setup, reopen Thermal Ops to resume your saved cooling profiles.","Ready to upgrade",MessageBoxButtons.YesNo)!=DialogResult.Yes)return;
            using(var dialog=new CoolingShutdownDialog(servers)){
                if(dialog.ShowDialog(this)!=DialogResult.OK)return;
                AppUpdates.StartInstallerAfterExit(installer,update.Hash);exitRequested=true;Close();
            }
        }catch(Exception ex){if(manual&&!IsDisposed)MessageBox.Show(this,"Could not complete the update: "+ex.Message+"\nYou can retry from Check for updates.","Thermal Ops updates");}
        finally{checkingUpdate=false;}
    }
    void BeginExit(){ShowDashboard();using(var dialog=new CoolingShutdownDialog(servers)){if(dialog.ShowDialog(this)==DialogResult.OK){exitRequested=true;Close();}}}
    public void HideToTray(){Hide();ShowInTaskbar=false;}
    void ShowDashboard(){ShowInTaskbar=true;Show();if(WindowState==FormWindowState.Minimized)WindowState=FormWindowState.Normal;tabs.SelectedIndex=0;Activate();BringToFront();}
    void ImportProfiles(){foreach(var server in servers)if(server.IsRunning||server.IsObserving){MessageBox.Show(this,"Stop this window's workers/views before importing their settings. An external controller can remain running.");return;}using(var picker=new FolderBrowserDialog{Description="Select the old Thermal Ops app folder (containing Profiles or settings.json)"}){if(picker.ShowDialog(this)!=DialogResult.OK)return;try{var files=ProfileStore.ImportLegacy(picker.SelectedPath,profiles);if(files.Count==0){MessageBox.Show(this,"No configured profiles were found. Select the old app folder, rather than the installer folder.");return;}for(int i=servers.Count-1;i>=0;i--){tabs.TabPages.RemoveAt(i+1);servers[i].Dispose();}servers.Clear();foreach(string directory in Directory.GetDirectories(profiles))if(File.Exists(Path.Combine(directory,"settings.json")))AddTab(directory);RefreshFleet();MessageBox.Show(this,files.Count+" profile(s) imported, including tool paths and confirmed GPU source. Choose Start cooling when ready.","Settings imported");}catch(Exception ex){MessageBox.Show(this,ex.Message,"Import failed");}}}
    void AddLocalProfile(){using(var dialog=new LocalSetupDialog(root)){if(dialog.ShowDialog(this)!=DialogResult.OK)return;try{foreach(var server in servers){var existing=ProfileStore.Read(server.ProfileDirectory);if(existing.ContainsKey("ManagementProvider")&&Convert.ToString(existing["ManagementProvider"])=="Local")throw new Exception("This version supports one local-controller profile per computer. This profile can map multiple fan channels; stop/remove it to change the mapping.");}string directory=Path.Combine(profiles,Guid.NewGuid().ToString("N"));var config=ProfileStore.Read(root);config["ProfileName"]=dialog.ProfileName;config["IdracHost"]="local-"+Environment.MachineName.ToLowerInvariant();config["IdracUser"]="";config["IdracPassProtected"]="";config["ManagementProvider"]="Local";config["LocalChannels"]=dialog.Channels;config["LocalTemperature"]=dialog.Temperature;config["LocalLimit"]=dialog.Limit;config["LocalConfirmed"]=true;config["ControlOnStartup"]=false;config["GpuMode"]="Unconfigured";config["GpuSourceConfirmed"]=false;Directory.CreateDirectory(directory);File.WriteAllText(Path.Combine(directory,"settings.json"),ProfileStore.Json.Serialize(config));AddTab(directory);tabs.SelectedIndex=tabs.TabCount-1;}catch(Exception ex){MessageBox.Show(this,ex.Message,"Local setup");}}}
    void ShowAddServer(){using(var dialog=new AddServerDialog()){if(dialog.ShowDialog(this)==DialogResult.OK){try{AddTab(ProfileStore.Add(profiles,root,dialog.ServerName,dialog.Address,dialog.Username,dialog.Password,dialog.ManagementProvider));tabs.SelectedIndex=tabs.TabCount-1;}catch(Exception ex){MessageBox.Show(this,ex.Message,"Cannot add server");}}}}
    Dictionary<string,object> Cached(FanApp server){
        if(server.Snapshot!=null)return server.Snapshot;
        try{var config=ProfileStore.Read(server.ProfileDirectory);string folder=config.ContainsKey("ExternalFeedDirectory")?Convert.ToString(config["ExternalFeedDirectory"]):Path.Combine(server.ProfileDirectory,"Runs");if(!Directory.Exists(folder))return null;var files=new List<FileInfo>();foreach(string path in Directory.GetFiles(folder,"*.json"))files.Add(new FileInfo(path));files.Sort((a,b)=>b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc));if(files.Count>0)return ProfileStore.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(files[0].FullName));}catch{}return null;
    }
    void RefreshFleet(){var readings=new List<FleetReading>();foreach(var server in servers){try{var config=ProfileStore.Read(server.ProfileDirectory);var snapshot=Cached(server);var reading=FleetReading.Evaluate(server.ProfileName,Convert.ToString(config["IdracHost"]),snapshot,DateTime.UtcNow);if(snapshot==null&&(!config.ContainsKey("ManagementProvider")||Convert.ToString(config["ManagementProvider"])=="Dell")&&(!config.ContainsKey("GpuMode")||Convert.ToString(config["GpuMode"])=="Unconfigured")){reading.Health="CONFIGURE";reading.State="SETUP REQUIRED";reading.Message="Configure and confirm the server GPU source";}readings.Add(reading);}catch{readings.Add(new FleetReading{Name=server.ProfileName,Address="--",Health="UNKNOWN",State="PROFILE ERROR"});}}fleet.RefreshReadings(readings);}
    void AddTab(string directory){var child=new FanApp(directory){TopLevel=false,FormBorderStyle=FormBorderStyle.None,Dock=DockStyle.Fill};var page=new TabPage(child.ProfileName);page.Controls.Add(child);tabs.TabPages.Add(page);servers.Add(child);child.Show();}
    public void ObserveExisting(string path){var data=ProfileStore.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(path));string address=Convert.ToString(data["IdracHost"]);foreach(var server in servers){var config=ProfileStore.Read(server.ProfileDirectory);if(ProfileStore.Normalize(Convert.ToString(config["IdracHost"]))==ProfileStore.Normalize(address)){server.ObserveExisting(path);return;}}throw new Exception("No saved server matches this status feed");}
    public static bool CanAutoStart(Dictionary<string,object> config){string management=config.ContainsKey("ManagementProvider")?Convert.ToString(config["ManagementProvider"]):"Dell";if(management=="DellRedfish"||management=="HPE"||management=="Supermicro"||management=="Redfish"||management=="Local")return true;return management=="Dell"&&config.ContainsKey("GpuMode")&&(Convert.ToString(config["GpuMode"])=="Local"||Convert.ToString(config["GpuMode"])=="ServerOnly")&&config.ContainsKey("GpuSourceConfirmed")&&Convert.ToBoolean(config["GpuSourceConfirmed"]);}
    public void StartConfiguredServers(){foreach(var server in servers)try{var config=ProfileStore.Read(server.ProfileDirectory);if(!CanAutoStart(config))continue;string feed=FeedDiscovery.Find(root,server.ProfileDirectory,Convert.ToString(config["IdracHost"]));if(feed!=null){server.ObserveExisting(feed);continue;}server.StartCooling();}catch(Exception ex){status.Text="Automatic startup needs attention: "+ex.Message;}}
    public void StartProfile(string id){for(int i=0;i<servers.Count;i++)if(Path.GetFileName(servers[i].ProfileDirectory)==id){tabs.SelectedIndex=i+1;servers[i].StartCooling();return;}MessageBox.Show(this,"Saved server profile was not found; no cooling worker started.");}
    public void PreviewSnapshot(string path){if(servers.Count>0)servers[0].PreviewSnapshot(path);RefreshFleet();}
    public void ShowFirstServer(){if(servers.Count>0)tabs.SelectedIndex=1;}
}

public class AddServerDialog : Form {
    ComboBox management=new ComboBox();TextBox name=new TextBox(),address=new TextBox(),user=new TextBox(),password=new TextBox();
    public string ManagementProvider{get{return management.SelectedIndex==1?"HPE":management.SelectedIndex==2?"Supermicro":management.SelectedIndex==3?"Redfish":management.SelectedIndex==4?"DellRedfish":"Dell";}}
    public string ServerName{get{return name.Text;}}public string Address{get{return address.Text;}}public string Username{get{return user.Text;}}public string Password{get{return password.Text;}}
    public AddServerDialog(){
        Icon=ThermalBrand.CreateIcon();Text="Add server";Size=new Size(560,420);StartPosition=FormStartPosition.CenterParent;FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=MinimizeBox=false;Font=new Font("Segoe UI",10);
        var layout=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,Padding=new Padding(18)};layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,145));layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));Controls.Add(layout);
        string[] labels={"Server name","Management address","Username","Password"};TextBox[] boxes={name,address,user,password};user.Text="root";password.UseSystemPasswordChar=true;
        for(int i=0;i<4;i++){layout.RowStyles.Add(new RowStyle(SizeType.Absolute,43));layout.Controls.Add(new Label{Text=labels[i],AutoSize=true},0,i);boxes[i].Dock=DockStyle.Fill;layout.Controls.Add(boxes[i],1,i);}
        layout.Controls.Add(new Label{Text="Credentials are saved only in this server's profile. Dell: confirm GPU source before cooling. Other BMCs: discovered native cooling capabilities. For gaming PCs use Local PC / controllers.",AutoSize=true,MaximumSize=new Size(320,70)},1,4);
        var ok=new Button{Text="Add server",DialogResult=DialogResult.OK,AutoSize=true};layout.Controls.Add(new Label{Text="Server interface",AutoSize=true},0,5);management.DropDownStyle=ComboBoxStyle.DropDownList;management.Items.AddRange(new object[]{"Dell iDRAC (IPMI / detected support)","HPE iLO (native cooling)","Supermicro BMC (native modes)","Other BMC (Redfish detection)","Dell iDRAC (Redfish fan minimum)"});management.SelectedIndex=0;management.Width=320;layout.Controls.Add(management,1,5);layout.Controls.Add(ok,1,6);AcceptButton=ok;
    }
}
