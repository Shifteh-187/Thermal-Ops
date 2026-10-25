using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public class TemperatureSample {
    public long UtcTicks; public double?[] Values; public bool Break;
}
public class TemperatureHistory {
    public readonly List<TemperatureSample> Samples=new List<TemperatureSample>();
    readonly string file;readonly bool readOnly;readonly double maximum,minimum;readonly JavaScriptSerializer json=new JavaScriptSerializer();
    bool pendingBreak=true;public string StorageWarning="";int writes=0;
    public TemperatureHistory(string path,bool preview,double maximum=150,double minimum=-20){this.maximum=maximum;this.minimum=minimum;file=path;readOnly=preview;if(String.IsNullOrEmpty(file)||!File.Exists(file))return;
        try{foreach(string line in File.ReadLines(file)){try{var s=json.Deserialize<TemperatureSample>(line);if(Valid(s,maximum,minimum)&&s.UtcTicks>=DateTime.UtcNow.AddHours(-24).Ticks&&s.UtcTicks<=DateTime.UtcNow.AddSeconds(5).Ticks&&(Samples.Count==0||s.UtcTicks>Samples[Samples.Count-1].UtcTicks))Samples.Add(s);}catch{}}Trim(DateTime.UtcNow);}catch{StorageWarning="History file unavailable; collecting in memory";}}
    static bool Valid(TemperatureSample s,double maximum,double minimum){if(s==null||s.Values==null||s.Values.Length!=5||s.UtcTicks<DateTime.MinValue.Ticks||s.UtcTicks>DateTime.MaxValue.Ticks)return false;foreach(var v in s.Values)if(v.HasValue&&(Double.IsNaN(v.Value)||Double.IsInfinity(v.Value)||v.Value<minimum||v.Value>maximum))return false;return true;}
    public void NewSession(){pendingBreak=true;}
    public bool Add(DateTime time,double?[] values){
        var sample=new TemperatureSample{UtcTicks=time.ToUniversalTime().Ticks,Values=(double?[])values.Clone(),Break=pendingBreak};
        if(!Valid(sample,maximum,minimum)||sample.UtcTicks>DateTime.UtcNow.AddSeconds(5).Ticks||sample.UtcTicks<DateTime.UtcNow.AddHours(-24).Ticks)return false;
        if(Samples.Count>0&&sample.UtcTicks<=Samples[Samples.Count-1].UtcTicks)return false;
        bool any=false;foreach(var v in values)if(v.HasValue)any=true;if(!any)return false;
        Samples.Add(sample);pendingBreak=false;Trim(DateTime.UtcNow);
        if(!readOnly&&!String.IsNullOrEmpty(file))try{File.AppendAllText(file,json.Serialize(sample)+Environment.NewLine);if(++writes%100==0)Compact();}catch{StorageWarning="History could not be saved; graph remains live";}
        return true;
    }
    public void Trim(DateTime now){int remove=0;long cutoff=now.ToUniversalTime().AddHours(-24).Ticks;while(remove<Samples.Count&&Samples[remove].UtcTicks<cutoff)remove++;remove=Math.Max(remove,Samples.Count-50000);if(remove>0)Samples.RemoveRange(0,remove);}
    public void Compact(){if(readOnly||String.IsNullOrEmpty(file))return;try{string temp=file+".tmp";using(var w=new StreamWriter(temp,false,Encoding.UTF8))foreach(var s in Samples)w.WriteLine(json.Serialize(s));if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);}catch{StorageWarning="History compaction failed; graph remains live";}}
    public List<TemperatureSample> Window(DateTime end,TimeSpan period){long high=end.ToUniversalTime().Ticks;long low=high-period.Ticks;return Samples.FindAll(s=>s.UtcTicks>=low&&s.UtcTicks<=high);}
    public static bool Connect(TemperatureSample before,TemperatureSample after,int series){return before!=null&&!after.Break&&after.UtcTicks-before.UtcTicks<=TimeSpan.FromSeconds(45).Ticks&&before.Values[series].HasValue&&after.Values[series].HasValue;}
    public static void SelfTest(){
        var h=new TemperatureHistory(null,true);DateTime now=DateTime.UtcNow;var v=new double?[]{60,40,30,24,null};
        if(!h.Add(now.AddSeconds(-100),v)||h.Add(now.AddSeconds(-100),v))throw new Exception("Duplicate sample handling failed");
        h.Add(now.AddSeconds(-80),new double?[]{61,41,31,24,null});h.Add(now.AddSeconds(-10),v);
        if(h.Window(now,TimeSpan.FromMinutes(1)).Count!=1)throw new Exception("Selectable time window failed");
        if(!Connect(h.Samples[0],h.Samples[1],0)||Connect(h.Samples[1],h.Samples[2],0))throw new Exception("Gap handling failed");
        if(Connect(h.Samples[0],h.Samples[1],4))throw new Exception("Missing sensor joined");
        h.NewSession();h.Add(now,v);if(Connect(h.Samples[2],h.Samples[3],0))throw new Exception("Session boundary joined");
        if(h.Add(now.AddSeconds(-5),v)||h.Add(now.AddSeconds(20),v)||h.Add(now.AddSeconds(1),new double?[]{Double.NaN,40,30,24,null}))throw new Exception("Invalid sample accepted");
        string file=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"trend-fixture-"+Guid.NewGuid().ToString("N")+".jsonl");
        try{var disk=new TemperatureHistory(file,false);disk.Add(now.AddSeconds(-30),v);disk.Add(now.AddSeconds(-10),v);File.AppendAllText(file,"broken record\n");var reload=new TemperatureHistory(file,true);if(reload.Samples.Count!=2||reload.Samples[0].Values[4].HasValue)throw new Exception("Persisted history/missing-data recovery failed");}finally{if(File.Exists(file))File.Delete(file);}
        h.Trim(now.AddHours(25));if(h.Samples.Count!=0)throw new Exception("Retention failed");
    }
}

public class TemperaturePlot : Control {
    public string Unit="C",AxisTitle="TEMP / C";public double AxisStep=20,MinimumScale=100;public string[] Names={"GPU","CPU","EXH","IN","SYS"};
    public TemperatureHistory History;public TimeSpan Period=TimeSpan.FromMinutes(5);public bool[] VisibleSeries={true,true,true,true,true};
    public static readonly Color[] Colors={Color.FromArgb(82,255,159),Color.FromArgb(38,215,255),Color.FromArgb(255,185,76),Color.FromArgb(167,132,255),Color.FromArgb(255,100,151)};
    readonly ToolTip tip=new ToolTip();Point cursor=new Point(-1,-1);
    public TemperaturePlot(){DoubleBuffered=true;SetStyle(ControlStyles.ResizeRedraw,true);BackColor=Color.FromArgb(6,14,17);Font=new Font("Consolas",9);MouseMove+=(s,e)=>{cursor=e.Location;Invalidate();};MouseLeave+=(s,e)=>{cursor=new Point(-1,-1);tip.Hide(this);Invalidate();};}
    protected override void Dispose(bool disposing){if(disposing)tip.Dispose();base.Dispose(disposing);}
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.Clear(BackColor);
        Rectangle plot=new Rectangle(47,28,Math.Max(1,Width-64),Math.Max(1,Height-61));if(Width<150||Height<100)return;
        DateTime now=DateTime.UtcNow;var points=History==null?new List<TemperatureSample>():History.Window(now,Period);
        double min=0,max=MinimumScale;foreach(var sample in points)for(int n=0;n<5;n++)if(VisibleSeries[n]&&sample.Values[n].HasValue){min=Math.Min(min,Math.Floor(sample.Values[n].Value/AxisStep)*AxisStep);max=Math.Max(max,Math.Ceiling(sample.Values[n].Value/AxisStep)*AxisStep);}
        using(var grid=new Pen(Color.FromArgb(25,70,64)))using(var faint=new Pen(Color.FromArgb(11,29,30)))using(var text=new SolidBrush(Color.FromArgb(119,174,160))){
            for(int y=plot.Top;y<plot.Bottom;y+=4)g.DrawLine(faint,plot.Left,y,plot.Right,y);
            int ticks=Math.Max(2,Math.Min(5,plot.Width/130));for(int i=0;i<=ticks;i++){int x=plot.Left+plot.Width*i/ticks;g.DrawLine(grid,x,plot.Top,x,plot.Bottom);string label=now.Subtract(TimeSpan.FromTicks(Period.Ticks*(ticks-i)/ticks)).ToLocalTime().ToString(Period.TotalHours>=6?"dd/MM HH:mm":Period.TotalMinutes<=5?"HH:mm:ss":"HH:mm");float width=g.MeasureString(label,Font).Width;float tx=Math.Min(Width-width-3,Math.Max(2,x-width/2));g.DrawString(label,Font,text,tx,plot.Bottom+7);}
            for(int i=0;i<=5;i++){int y=plot.Top+plot.Height*i/5;g.DrawLine(grid,plot.Left,y,plot.Right,y);g.DrawString((max-i*(max-min)/5).ToString("0"),Font,text,7,y-7);}
            g.DrawString(AxisTitle,Font,text,4,4);
            string age="WAITING FOR TELEMETRY";if(History!=null&&History.Samples.Count>0){double secs=Math.Max(0,(now-new DateTime(History.Samples[History.Samples.Count-1].UtcTicks,DateTimeKind.Utc)).TotalSeconds);age=(secs>45?"STALE / ":"LIVE / ")+((int)secs)+"s SINCE SAMPLE";}
            g.DrawString(age,Font,text,plot.Left+90,4);
        }
        // Plotting is clipped, missing sensors/session changes/long gaps are never joined.
        var oldClip=g.Clip;g.SetClip(plot);
        for(int series=0;series<5;series++){if(!VisibleSeries[series])continue;var segment=new List<PointF>();TemperatureSample previous=null;
            foreach(var sample in points){if(!TemperatureHistory.Connect(previous,sample,series)){DrawSegment(g,segment,Colors[series]);segment.Clear();}
                if(sample.Values[series].HasValue){float x=plot.Right-(float)((now.Ticks-sample.UtcTicks)/(double)Period.Ticks)*plot.Width;float y=plot.Bottom-(float)((sample.Values[series].Value-min)/(max-min))*plot.Height;segment.Add(new PointF(x,y));}previous=sample;}
            DrawSegment(g,segment,Colors[series]);}
        g.Clip=oldClip;oldClip.Dispose();
        using(var edge=new Pen(Color.FromArgb(43,109,85)))g.DrawRectangle(edge,plot);
        if(points.Count==0)TextRenderer.DrawText(g,"AWAITING SAMPLES IN THIS WINDOW",Font,plot,Color.FromArgb(108,185,147),TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
        if(plot.Contains(cursor)&&points.Count>0){long desired=now.Ticks-Period.Ticks+(long)((cursor.X-plot.Left)/(double)plot.Width*Period.Ticks);TemperatureSample best=null;long delta=Int64.MaxValue;foreach(var p in points){long d=Math.Abs(p.UtcTicks-desired);if(d<delta){delta=d;best=p;}}
            using(var cross=new Pen(Color.FromArgb(75,178,140))){cross.DashStyle=DashStyle.Dot;g.DrawLine(cross,cursor.X,plot.Top,cursor.X,plot.Bottom);}
            if(best!=null){var label=new StringBuilder(new DateTime(best.UtcTicks,DateTimeKind.Utc).ToLocalTime().ToString("HH:mm:ss"));for(int n=0;n<5;n++)if(VisibleSeries[n])label.Append("   "+Names[n]+" "+Format(best.Values[n]));g.DrawString(label.ToString(),Font,Brushes.White,plot.Left,plot.Top+4);}}

    }
    string Format(double? value){return value.HasValue?value.Value.ToString("0.0",CultureInfo.InvariantCulture)+" "+Unit:"--";}
    static void DrawSegment(Graphics g,List<PointF> segment,Color color){if(segment.Count==0)return;if(segment.Count==1){using(var b=new SolidBrush(color))g.FillEllipse(b,segment[0].X-2,segment[0].Y-2,4,4);return;}var points=segment.ToArray();using(var glow=new Pen(Color.FromArgb(35,color),5))g.DrawLines(glow,points);using(var line=new Pen(color,1.6f))g.DrawLines(line,points);}
}

public class TemperatureTrends : UserControl {
    public TemperatureHistory History {get;private set;}readonly TemperaturePlot plot=new TemperaturePlot();Label note=new Label();readonly bool preview,power;string currentFile;
    public TemperatureTrends(string file,bool preview,bool power=false,bool fleet=false){DoubleBuffered=true;this.power=power;this.preview=preview;currentFile=file;History=new TemperatureHistory(file,preview,power?100000:150,power?0:-20);plot.History=History;Dock=DockStyle.Fill;BackColor=Color.FromArgb(6,14,17);
        if(power){plot.Unit="W";plot.AxisTitle="POWER / W";plot.AxisStep=100;plot.MinimumScale=500;plot.Names=new[]{"SERVER","GPU SUM","","",""};plot.VisibleSeries[2]=plot.VisibleSeries[3]=plot.VisibleSeries[4]=false;}
        if(fleet){plot.Names[0]="CLUSTER TOTAL";plot.VisibleSeries[1]=false;}
        var layout=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,RowCount=3,ColumnCount=1,Padding=new Padding(8)};layout.RowStyles.Add(new RowStyle(SizeType.Absolute,62));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,22));Controls.Add(layout);
        var toolbar=new BufferedFlowLayoutPanel{Dock=DockStyle.Fill,WrapContents=true};toolbar.Controls.Add(new Label{Text=fleet?"[ TOTAL CLUSTER POWER ]":power?"[ POWER TRACE ]":"[ THERMAL TRACE ]",AutoSize=true,ForeColor=Color.FromArgb(82,255,159),Font=new Font("Consolas",11,FontStyle.Bold),Padding=new Padding(0,5,8,0)});
        var period=new ReadableButton{Text="5 min  v",Width=100,Height=27,Font=new Font("Consolas",10)};var menu=new ContextMenuStrip{BackColor=Color.FromArgb(12,28,26),ForeColor=Color.FromArgb(82,255,159)};
        string[] labels={"1 min","5 min","15 min","30 min","1 hour","6 hours","24 hours"};double[] minutes={1,5,15,30,60,360,1440};
        for(int n=0;n<labels.Length;n++){int selected=n;var item=menu.Items.Add(labels[n]);item.Click+=(sender,args)=>{plot.Period=TimeSpan.FromMinutes(minutes[selected]);period.Text=labels[selected]+"  v";plot.Invalidate();};}
        period.Click+=(sender,args)=>menu.Show(period,new Point(0,period.Height));period.Disposed+=(sender,args)=>menu.Dispose();toolbar.Controls.Add(period);

        string[] names=fleet?new[]{"Total input (all reporting)"}:power?new[]{"Server input","GPU sum (subset)"}:new[]{"GPU max","CPU max","Exhaust","Inlet","System"};for(int i=0;i<names.Length;i++){int index=i;var box=new CheckBox{Text=names[i],Checked=true,AutoSize=true,ForeColor=TemperaturePlot.Colors[i],BackColor=BackColor,Font=new Font("Consolas",9),Margin=new Padding(10,7,0,0)};box.CheckedChanged+=(s,e)=>{plot.VisibleSeries[index]=box.Checked;plot.Invalidate();};toolbar.Controls.Add(box);}
        layout.Controls.Add(toolbar,0,0);plot.Dock=DockStyle.Fill;layout.Controls.Add(plot,0,1);note.Dock=DockStyle.Fill;note.ForeColor=Color.FromArgb(119,174,160);note.Font=new Font("Consolas",8);note.Text=power?"SERVER INPUT ALREADY INCLUDES GPU POWER / DO NOT ADD TRACES":"ACTUAL SAMPLE TIMES / GAPS >45s STAY OPEN / HOVER TO INSPECT";layout.Controls.Add(note,0,2);
        if(fleet)note.Text="COMPLETE COVERAGE ONLY / MISSING OR STALE SERVERS LEAVE GAPS";
    }
    public void Feed(DateTime time,double?[] values){if(!History.Add(time,values))return;if(History.StorageWarning.Length>0)note.Text=History.StorageWarning;plot.Invalidate();}
    public void Tick(){if(Visible)plot.Invalidate(false);}
    public void NewSession(){History.NewSession();}
    public void SetTarget(string file){if(currentFile==file)return;History.Compact();currentFile=file;History=new TemperatureHistory(file,preview,power?100000:150,power?0:-20);plot.History=History;plot.Invalidate();}
    protected override void Dispose(bool disposing){if(disposing)History.Compact();base.Dispose(disposing);}
}
