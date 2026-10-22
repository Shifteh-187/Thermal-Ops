using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;
public class LocalSetupDialog : Form {
    class Item {public string Id,Name;public override string ToString(){return Name;}}
    ListBox channels=new ListBox{SelectionMode=SelectionMode.MultiExtended};ComboBox temperatures=new ComboBox();NumericUpDown limit=new NumericUpDown{Minimum=40,Maximum=110,Value=70};CheckBox confirmed=new ReadableCheckBox();TextBox name=new TextBox{Text="Gaming PC / fan controller"};Label notice=new Label();Button scan=new ReadableButton(),ok=new ReadableButton();string root;
    public string ProfileName{get{return name.Text.Trim();}}public string[] Channels{get{var ids=new List<string>();foreach(Item item in channels.SelectedItems)ids.Add(item.Id);return ids.ToArray();}}public string Temperature{get{return ((Item)temperatures.SelectedItem).Id;}}public int Limit{get{return (int)limit.Value;}}
    public LocalSetupDialog(string path){root=path;Text="Local PC / fan controller setup";Icon=ThermalBrand.CreateIcon();Size=new Size(820,650);StartPosition=FormStartPosition.CenterParent;BackColor=Color.FromArgb(18,23,31);ForeColor=Color.White;Font=new Font("Segoe UI",10);
        var layout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(18),ColumnCount=2,RowCount=8};layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,175));layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));Controls.Add(layout);foreach(int height in new[]{48,44,110,44,44,46,86,44})layout.RowStyles.Add(new RowStyle(SizeType.Absolute,height));
        var driver=new ReadableButton{Text="Install PC driver",Width=240,Height=35};driver.Click+=(s,e)=>{try{Process.Start(new ProcessStartInfo(Path.Combine(root,"LocalHardware","PawnIO_setup.exe")){UseShellExecute=true});}catch(Exception ex){MessageBox.Show(this,ex.Message);}};
        scan.Text="Scan local hardware";scan.Width=230;scan.Height=35;scan.Click+=async(s,e)=>await Scan();layout.Controls.Add(driver,0,0);layout.Controls.Add(scan,1,0);
        string[] labels={"Profile name","Fan channel (not pump)","Temperature source","Full speed at (C)"};Control[] fields={name,channels,temperatures,limit};temperatures.DropDownStyle=ComboBoxStyle.DropDownList;
        for(int i=0;i<4;i++){layout.Controls.Add(new Label{Text=labels[i],AutoSize=true},0,i+1);fields[i].Dock=DockStyle.Fill;layout.Controls.Add(fields[i],1,i+1);}
        confirmed.Text="I confirm these fans, the sensor and temperature limit are correct.";confirmed.AutoSize=true;confirmed.MaximumSize=new Size(560,70);layout.Controls.Add(confirmed,1,5);
        notice.Text="Scan first. Only exposed controls can be selected. Supported motherboard, GPU and USB channels depend on the installed hardware and driver. Other fan software must not control the same channel.";notice.AutoSize=true;notice.MaximumSize=new Size(570,100);layout.Controls.Add(notice,1,6);
        ok.Text="Add local profile";ok.Width=230;ok.Height=35;ok.Click+=(s,e)=>{if(channels.SelectedItems.Count==0||temperatures.SelectedItem==null||!confirmed.Checked||String.IsNullOrWhiteSpace(name.Text)){MessageBox.Show(this,"Choose the fan channel and temperature sensor, then confirm the mapping.");return;}DialogResult=DialogResult.OK;Close();};layout.Controls.Add(ok,1,7);
    }
    async Task Scan(){scan.Enabled=ok.Enabled=false;notice.Text="Reading local hardware; no fan commands requested...";string file=Path.Combine(Path.GetTempPath(),"ThermalOps-scan-"+Guid.NewGuid().ToString("N")+".json");try{
        string result=await Task.Run(()=>{using(var p=new Process()){p.StartInfo=new ProcessStartInfo(Path.Combine(root,"LocalHardware","LocalWorker.exe"),"--scan \""+file+"\""){UseShellExecute=false,CreateNoWindow=true};p.Start();if(!p.WaitForExit(45000)){p.Kill();throw new Exception("Hardware scan timed out");}if(!File.Exists(file))throw new Exception("Hardware scan failed; check driver installation and permissions");return File.ReadAllText(file);}});
        var data=ProfileStore.Json.Deserialize<Dictionary<string,object>>(result);channels.Items.Clear();temperatures.Items.Clear();Fill(channels,data["Controls"]);Fill(temperatures,data["Temperatures"]);temperatures.Items.Insert(0,new Item{Id="@cpu-gpu-max",Name="Highest available CPU / GPU temperature"});notice.Text=channels.Items.Count+" fan channels and "+temperatures.Items.Count+" temperature sensors found. Ctrl-click to select multiple fan channels. Choose the physical mapping. If none appear, check driver/administrator requirements. No fan writes were requested.";
    }catch(Exception ex){notice.Text=ex.Message;}finally{scan.Enabled=ok.Enabled=true;try{File.Delete(file);}catch{}}}
    static void Fill(ComboBox box,object entries){var list=entries as IEnumerable;if(list!=null)foreach(var item in list){var d=item as Dictionary<string,object>;if(d!=null)box.Items.Add(new Item{Id=Convert.ToString(d["Id"]),Name=Convert.ToString(d["Name"])});}}
    static void Fill(ListBox box,object entries){var list=entries as IEnumerable;if(list!=null)foreach(var item in list){var d=item as Dictionary<string,object>;if(d!=null)box.Items.Add(new Item{Id=Convert.ToString(d["Id"]),Name=Convert.ToString(d["Name"])});}}
}
