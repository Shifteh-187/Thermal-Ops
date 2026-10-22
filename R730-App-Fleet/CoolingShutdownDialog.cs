using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

public class CoolingShutdownDialog : Form {
    class Target {public FanApp Server;public string Path,Error;}
    List<Target> targets=new List<Target>();Timer timer=new Timer();TextBox progress=new TextBox();Button finish=new ReadableButton();DateTime requested=DateTime.UtcNow;bool complete=false;
    public static bool Accepted(Dictionary<string,object> data,DateTime since){
        DateTime time;if(data==null||!data.ContainsKey("Time")||!DateTime.TryParse(Convert.ToString(data["Time"]),null,System.Globalization.DateTimeStyles.RoundtripKind,out time)||time.ToUniversalTime()<since.AddSeconds(-1))return false;
        return Convert.ToString(data["State"])=="Stopped"&&(Convert.ToString(data["Message"])=="Dell automatic control command accepted"||Convert.ToString(data["Message"])=="Read-only monitor stopped"||Convert.ToString(data["Message"])=="Original native cooling settings verified"||Convert.ToString(data["Message"])=="Hardware default restore command accepted");
    }
    public CoolingShutdownDialog(List<FanApp> servers){
        Icon=ThermalBrand.CreateIcon();Text="Thermal Ops - safe shutdown";Size=new Size(700,400);StartPosition=FormStartPosition.CenterParent;BackColor=Color.FromArgb(18,23,31);ForeColor=Color.White;Font=new Font("Segoe UI",10);MinimizeBox=MaximizeBox=false;
        var title=new Label{Text="Stopping controllers and restoring default cooling",Dock=DockStyle.Top,Height=48,Padding=new Padding(14),AutoSize=false};Controls.Add(title);
        var buttons=new FlowLayoutPanel{Dock=DockStyle.Bottom,Height=55,Padding=new Padding(10)};finish.Text="Exit Thermal Ops";finish.Width=190;finish.Enabled=false;finish.Click+=(s,e)=>{DialogResult=DialogResult.OK;Close();};var back=new ReadableButton{Text="Keep dashboard open",Width=210};back.Click+=(s,e)=>{DialogResult=DialogResult.Cancel;Close();};buttons.Controls.Add(finish);buttons.Controls.Add(back);Controls.Add(buttons);
        progress.Multiline=true;progress.ReadOnly=true;progress.Dock=DockStyle.Fill;progress.BackColor=BackColor;progress.ForeColor=Color.FromArgb(130,255,180);progress.ScrollBars=ScrollBars.Vertical;Controls.Add(progress);progress.BringToFront();
        Shown+=(s,e)=>{foreach(var server in servers){var target=new Target{Server=server};targets.Add(target);try{target.Path=server.BeginSafeShutdown();}catch(Exception ex){target.Error=ex.Message;}}UpdateProgress();timer.Start();};
        timer.Interval=500;timer.Tick+=(s,e)=>UpdateProgress();FormClosed+=(s,e)=>{timer.Stop();timer.Dispose();};
    }
    void UpdateProgress(){
        var lines=new List<string>();complete=true;foreach(var target in targets){string message;
            if(target.Error!=null){message="NEEDS ATTENTION: "+target.Error;complete=false;}
            else if(target.Path==null)message="No active controller found; hardware mode not checked.";
            else try{var data=ProfileStore.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(target.Path));if(Accepted(data,requested)&&!target.Server.IsRunning){message=Convert.ToString(data["Message"])=="Read-only monitor stopped"?"Monitor stopped; fan control was unchanged.":Convert.ToString(data["Message"])=="Original native cooling settings verified"?"Original native cooling settings restored and read back.":Convert.ToString(data["Message"])=="Hardware default restore command accepted"?"Local hardware driver accepted default fan control.":"Dell automatic control command accepted by iDRAC.";}
                else{complete=false;message=Convert.ToString(data["State"])=="RESTORE FAILED"?"RESTORE FAILED - keep dashboard open and check hardware management.":(DateTime.UtcNow-requested).TotalSeconds>180?"Still unconfirmed - check controller activity and hardware management.":"Waiting for controller to stop and restore default control...";}}
            catch{complete=false;message="Waiting for final controller status...";}
            lines.Add(target.Server.ProfileName+": "+message);
        }
        lines.Add("");lines.Add(complete?"Shutdown checks complete. You can now exit.":"The app will stay open until shutdown is confirmed. No controller is forcibly terminated.");lines.Add("Dell: command acceptance. Redfish: setting read-back. Local PC: driver acceptance.");progress.Text=String.Join(Environment.NewLine+Environment.NewLine,lines.ToArray());finish.Enabled=complete;
    }
}
