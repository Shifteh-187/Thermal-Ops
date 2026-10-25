using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

public sealed class FanCurvePoint {public double Temperature{get;set;}public double Percent{get;set;}}
public sealed class SensorFanCurve {
    public string Source{get;set;}public string Label{get;set;}public bool Enabled{get;set;}
    public List<FanCurvePoint> Points{get;set;}
    public override string ToString(){return Label;}
}
public static class FanCurveModel {
    public static List<FanCurvePoint> Defaults(){return new List<FanCurvePoint>{new FanCurvePoint{Temperature=20,Percent=15},new FanCurvePoint{Temperature=40,Percent=20},new FanCurvePoint{Temperature=55,Percent=35},new FanCurvePoint{Temperature=70,Percent=60},new FanCurvePoint{Temperature=80,Percent=85},new FanCurvePoint{Temperature=85,Percent=100}};}
    public static void Validate(List<FanCurvePoint> points){
        if(points==null||points.Count<2||points.Count>12)throw new Exception("Use 2-12 points per curve.");
        double last=-1,duty=0;foreach(var p in points){if(Double.IsNaN(p.Temperature)||Double.IsInfinity(p.Temperature)||Double.IsNaN(p.Percent)||Double.IsInfinity(p.Percent)||p.Temperature<0||p.Temperature>100||p.Percent<10||p.Percent>100||p.Temperature<=last||p.Percent<duty)throw new Exception("Temperatures must increase from 0-100 C; fan speed must stay level or increase from 10-100%.");last=p.Temperature;duty=p.Percent;}
    }
    public static double Evaluate(List<FanCurvePoint> points,double temp){Validate(points);if(temp<=points[0].Temperature)return points[0].Percent;for(int i=1;i<points.Count;i++)if(temp<=points[i].Temperature)return points[i-1].Percent+(temp-points[i-1].Temperature)/(points[i].Temperature-points[i-1].Temperature)*(points[i].Percent-points[i-1].Percent);return points[points.Count-1].Percent;}
    public static void SelfTest(){
        var p=Defaults();if(Evaluate(p,10)!=15||Evaluate(p,90)!=100||Evaluate(p,47.5)!=27.5)throw new Exception("Interpolation/bounds failed");
        foreach(var bad in new[]{new List<FanCurvePoint>{new FanCurvePoint{Temperature=40,Percent=50},new FanCurvePoint{Temperature=40,Percent=60}},new List<FanCurvePoint>{new FanCurvePoint{Temperature=20,Percent=50},new FanCurvePoint{Temperature=40,Percent=40}},new List<FanCurvePoint>{new FanCurvePoint{Temperature=20,Percent=Double.NaN},new FanCurvePoint{Temperature=40,Percent=100}}}){bool rejected=false;try{Validate(bad);}catch{rejected=true;}if(!rejected)throw new Exception("Invalid points accepted");}
    }
}
public sealed class CurveCanvas : Control {
    public List<FanCurvePoint> Points=FanCurveModel.Defaults();public event Action Changed;int dragging=-1;
    public CurveCanvas(){DoubleBuffered=true;BackColor=Color.FromArgb(5,15,17);ForeColor=Color.Aquamarine;MinimumSize=new Size(300,200);}
    Rectangle Plot{get{return new Rectangle(52,22,Math.Max(1,Width-80),Math.Max(1,Height-65));}}
    PointF At(FanCurvePoint p){var r=Plot;return new PointF(r.Left+(float)p.Temperature*r.Width/100,r.Bottom-(float)p.Percent*r.Height/100);}
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;var r=Plot;using(var grid=new Pen(Color.FromArgb(20,65,61)))using(var ink=new SolidBrush(Color.Aquamarine))using(var line=new Pen(Color.FromArgb(65,255,170),2)){
        for(int n=0;n<=100;n+=20){float x=r.Left+n*r.Width/100f,y=r.Bottom-n*r.Height/100f;g.DrawLine(grid,x,r.Top,x,r.Bottom);g.DrawLine(grid,r.Left,y,r.Right,y);g.DrawString(n.ToString(),Font,ink,8,y-7);g.DrawString(n.ToString(),Font,ink,x-9,r.Bottom+5);}
        g.DrawString("FAN %",Font,ink,5,2);g.DrawString("TEMPERATURE / C",Font,ink,r.Left+25,Height-20);
        if(Points.Count>0){var p=Points.Select(At).ToArray();if(p.Length>1)g.DrawLines(line,p);foreach(var dot in p)g.FillEllipse(ink,dot.X-5,dot.Y-5,10,10);}
    }}
    int Hit(Point p){for(int i=0;i<Points.Count;i++){var q=At(Points[i]);if(Math.Abs(p.X-q.X)<10&&Math.Abs(p.Y-q.Y)<10)return i;}return -1;}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(!Enabled||!Plot.Contains(e.Location))return;int hit=Hit(e.Location);
        if(e.Button==MouseButtons.Right){if(hit>=0&&Points.Count>2){Points.RemoveAt(hit);Notify();}return;}
        if(e.Button!=MouseButtons.Left)return;
        if(hit<0&&Points.Count<12){var r=Plot;double temp=Math.Round((e.X-r.Left)*100.0/r.Width);if(Points.Any(p=>Math.Abs(p.Temperature-temp)<1))return;double percent=Math.Max(10,Math.Min(100,Math.Round((r.Bottom-e.Y)*100.0/r.Height)));var lower=Points.LastOrDefault(p=>p.Temperature<temp);var upper=Points.FirstOrDefault(p=>p.Temperature>temp);percent=Math.Max(lower==null?10:lower.Percent,Math.Min(upper==null?100:upper.Percent,percent));var point=new FanCurvePoint{Temperature=temp,Percent=percent};Points.Add(point);Points.Sort((a,b)=>a.Temperature.CompareTo(b.Temperature));hit=Points.IndexOf(point);Notify();}
        dragging=hit;Capture=hit>=0;
    }
    protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(dragging<0||!Enabled)return;var r=Plot;var p=Points[dragging];p.Temperature=Math.Max(dragging==0?0:Points[dragging-1].Temperature+1,Math.Min(dragging==Points.Count-1?100:Points[dragging+1].Temperature-1,Math.Round((e.X-r.Left)*100.0/r.Width)));p.Percent=Math.Max(dragging==0?10:Points[dragging-1].Percent,Math.Min(dragging==Points.Count-1?100:Points[dragging+1].Percent,Math.Round((r.Bottom-e.Y)*100.0/r.Height)));Invalidate();}
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(dragging>=0){dragging=-1;Capture=false;Notify();}}
    void Notify(){Invalidate();if(Changed!=null)Changed();}
}
public sealed class FanCurveEditor : UserControl {
    readonly ReadableSelector mode=new ReadableSelector(),source=new ReadableSelector();readonly CheckBox use=new ReadableCheckBox();readonly NumericUpDown manual=new NumericUpDown{Minimum=10,Maximum=100,Value=50};
    readonly DataGridView points=new BufferedDataGridView(),fanList=new BufferedDataGridView();readonly CurveCanvas graph=new CurveCanvas();readonly Label notice=new Label(),sample=new Label();
    readonly Button save=new ReadableButton(),restore=new ReadableButton(),reset=new ReadableButton();readonly List<SensorFanCurve> curves=new List<SensorFanCurve>();bool updating,native,unsupported;int lastLock=-1;string inventory="";public event Action SaveRequested,RestoreRequested;
    public FanCurveEditor(){
        Dock=DockStyle.Fill;BackColor=Color.FromArgb(18,23,31);ForeColor=Color.White;Font=new Font("Segoe UI",9);
        var layout=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=5,Padding=new Padding(10)};layout.RowStyles.Add(new RowStyle(SizeType.Absolute,76));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,48));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,170));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,48));Controls.Add(layout);
        notice.Dock=DockStyle.Fill;notice.ForeColor=Color.Aquamarine;layout.Controls.Add(notice,0,0);
        var actions=new BufferedFlowLayoutPanel{Dock=DockStyle.Fill};mode.BackColor=Color.FromArgb(29,36,47);mode.ForeColor=Color.White;manual.BackColor=mode.BackColor;manual.ForeColor=Color.White;mode.Width=245;mode.Items.AddRange(new object[]{"Automatic - original curves","Automatic - adaptive curves","Automatic - custom graph","Manual % - safety protected"});mode.SelectedIndex=0;actions.Controls.Add(mode);actions.Controls.Add(new Label{Text="Manual %",AutoSize=true,Margin=new Padding(10,5,0,0)});manual.Width=65;actions.Controls.Add(manual);layout.Controls.Add(actions,0,1);
        var split=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2};split.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,230));split.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));layout.Controls.Add(split,0,2);
        var editor=new BufferedTableLayoutPanel{Dock=DockStyle.Fill,RowCount=4};editor.RowStyles.Add(new RowStyle(SizeType.Absolute,34));editor.RowStyles.Add(new RowStyle(SizeType.Absolute,30));editor.RowStyles.Add(new RowStyle(SizeType.Percent,100));editor.RowStyles.Add(new RowStyle(SizeType.Absolute,30));source.BackColor=Color.FromArgb(29,36,47);source.ForeColor=Color.White;source.Dock=DockStyle.Fill;editor.Controls.Add(source,0,0);use.Text="Use this sensor curve";use.AutoSize=true;editor.Controls.Add(use,0,1);
        Grid(points);points.ReadOnly=false;points.Columns.Add("Temperature","Temp C");points.Columns.Add("Percent","Fan %");points.AllowUserToAddRows=false;editor.Controls.Add(points,0,2);sample.Dock=DockStyle.Fill;editor.Controls.Add(sample,0,3);split.Controls.Add(editor,0,0);graph.Dock=DockStyle.Fill;graph.Margin=new Padding(10,0,0,0);split.Controls.Add(graph,1,0);
        Grid(fanList);fanList.Columns.Add("Fan","Detected fan");fanList.Columns.Add("Rpm","Reading");fanList.Columns.Add("Control","Control output");layout.Controls.Add(fanList,0,3);
        var buttons=new BufferedFlowLayoutPanel{Dock=DockStyle.Fill};save.Text="Save for next start";save.Width=170;save.Height=32;save.Click+=(s,e)=>{if(SaveRequested!=null)SaveRequested();};restore.Text="Restore hardware auto";restore.Width=190;restore.Height=32;restore.Click+=(s,e)=>{if(RestoreRequested!=null)RestoreRequested();};reset.Text="Reset selected curve";reset.Width=170;reset.Height=32;reset.Click+=(s,e)=>{if(Current!=null){Current.Points=FanCurveModel.Defaults();ShowCurve();}};buttons.Controls.Add(save);buttons.Controls.Add(restore);buttons.Controls.Add(reset);layout.Controls.Add(buttons,0,4);
        source.SelectedIndexChanged+=(s,e)=>ShowCurve();use.CheckedChanged+=(s,e)=>{if(!updating&&Current!=null)Current.Enabled=use.Checked;};mode.SelectedIndexChanged+=(s,e)=>UpdateMode();graph.Changed+=RefreshPoints;
        points.CellEndEdit+=(s,e)=>{if(updating||Current==null)return;try{var edited=new List<FanCurvePoint>();foreach(DataGridViewRow row in points.Rows)edited.Add(new FanCurvePoint{Temperature=Convert.ToDouble(row.Cells[0].Value),Percent=Convert.ToDouble(row.Cells[1].Value)});FanCurveModel.Validate(edited);Current.Points=edited;graph.Points=edited;graph.Invalidate();sample.Text="Points updated";}catch(Exception ex){MessageBox.Show(this,ex.Message,"Invalid curve points");ShowCurve();}};
        points.DataError+=(s,e)=>{e.ThrowException=false;};UpdateMode();
    }
    static void Grid(DataGridView grid){grid.Dock=DockStyle.Fill;grid.ReadOnly=true;grid.AllowUserToAddRows=false;grid.AllowUserToDeleteRows=false;grid.RowHeadersVisible=false;grid.AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill;grid.BackgroundColor=Color.FromArgb(29,36,47);grid.DefaultCellStyle.BackColor=grid.BackgroundColor;grid.DefaultCellStyle.ForeColor=Color.White;grid.EnableHeadersVisualStyles=false;grid.ColumnHeadersDefaultCellStyle.BackColor=Color.FromArgb(37,47,61);grid.ColumnHeadersDefaultCellStyle.ForeColor=Color.White;grid.ColumnAdded+=(s,e)=>e.Column.SortMode=DataGridViewColumnSortMode.NotSortable;}
    SensorFanCurve Current{get{return source.SelectedItem as SensorFanCurve;}}
    void RefreshPoints(){updating=true;points.Rows.Clear();if(Current!=null)foreach(var p in Current.Points)points.Rows.Add(p.Temperature,p.Percent);updating=false;}
    void ShowCurve(){updating=true;if(Current!=null){use.Checked=Current.Enabled;graph.Points=Current.Points;}updating=false;RefreshPoints();graph.Invalidate();}
    void UpdateMode(){bool custom=mode.SelectedIndex==2&&!native&&!unsupported;source.Enabled=use.Enabled=points.Enabled=graph.Enabled=custom;manual.Enabled=mode.SelectedIndex==3&&!native&&!unsupported;}
    public void LoadConfig(Dictionary<string,object> settings,bool isNative){
        native=isNative;curves.Clear();string selected=settings.ContainsKey("FanCurveMode")?Convert.ToString(settings["FanCurveMode"]):settings.ContainsKey("Smart")&&Convert.ToBoolean(settings["Smart"])?"Smart":"Original";mode.SelectedIndex=Array.IndexOf(new[]{"Original","Smart","Custom","Manual"},selected);if(mode.SelectedIndex<0)mode.SelectedIndex=0;
        if(settings.ContainsKey("ManualFanPercent"))manual.Value=Math.Max(10,Math.Min(100,Convert.ToDecimal(settings["ManualFanPercent"])));
        if(settings.ContainsKey("FanCurves")){var json=new System.Web.Script.Serialization.JavaScriptSerializer();curves.AddRange(json.Deserialize<List<SensorFanCurve>>(json.Serialize(settings["FanCurves"])));}
        foreach(var curve in curves){FanCurveModel.Validate(curve.Points);if(String.IsNullOrWhiteSpace(curve.Label))curve.Label=curve.Source;}
        RefillSources();UpdateMode();lastLock=-1;SetRunning(false,false);
    }
    void RefillSources(){string previous=Current==null?null:Current.Source;source.Items.Clear();foreach(var curve in curves)source.Items.Add(curve);int index=curves.FindIndex(c=>c.Source==previous);if(curves.Count>0)source.SelectedIndex=Math.Max(0,index);}
    public void SetRunning(bool running,bool external){int key=(running?1:0)+(external?2:0)+(native?4:0)+(unsupported?8:0);if(key==lastLock)return;lastLock=key;save.Enabled=mode.Enabled=reset.Enabled=!running&&!external&&!native&&!unsupported;restore.Text=external?"Stop viewing":"Restore hardware auto";UpdateMode();if(running||external){source.Enabled=true;use.Enabled=points.Enabled=graph.Enabled=manual.Enabled=false;}notice.Text=unsupported?"This detected model/firmware is monitoring-only. Individual fan/curve control is not verified.":native?"Detected fan/sensor inventory is shown here. This adapter uses native/local controls configured on Connection; custom R730 graph output is unavailable.":"R730 adapter output: ALL chassis fans together. Each RPM is monitored independently.\r\nCustom/manual requests retain the original CPU/GPU/exhaust/system safety floors and emergency limits. Highest sensor demand wins.\r\nClick to add points, drag to move, right-click to remove; edit numbers for precision. "+(running||external?"Stop the worker before saving changes.":"Save, then Start cooling to apply.");}
    public bool CaptureSettings(Dictionary<string,object> settings){
        if(native||unsupported)return false;points.EndEdit();string selected=new[]{"Original","Smart","Custom","Manual"}[mode.SelectedIndex];var enabled=curves.Where(c=>c.Enabled).ToList();
        if(selected=="Custom"&&(enabled.Count==0||enabled.Count>32))throw new Exception("Start Monitor only to discover sensors, then enable 1-32 curves.");foreach(var curve in enabled)FanCurveModel.Validate(curve.Points);
        settings["FanCurveMode"]=selected;settings["ManualFanPercent"]=(int)manual.Value;settings["FanCurves"]=curves;settings["Smart"]=selected=="Smart";return selected=="Smart";
    }
    public void Feed(Dictionary<string,object> snapshot){
        var identity=snapshot.ContainsKey("TargetIdentity")?snapshot["TargetIdentity"] as Dictionary<string,object>:null;unsupported=identity!=null&&identity.ContainsKey("ManualControlAllowed")&&Object.Equals(identity["ManualControlAllowed"],false);
        var ipmi=snapshot.ContainsKey("Ipmi")?snapshot["Ipmi"] as Dictionary<string,object>:null;var gpu=snapshot.ContainsKey("Gpu")?snapshot["Gpu"] as Dictionary<string,object>:null;if(ipmi==null)return;
        fanList.Rows.Clear();var fans=ipmi.ContainsKey("Fans")?ipmi["Fans"] as IEnumerable:null;if(fans!=null)foreach(var item in fans){var row=item as Dictionary<string,object>;if(row!=null)fanList.Rows.Add(Get(row,"Name"),Convert.ToString(Get(row,"Value"))+" "+(Get(row,"Units")??"RPM"),native?"Adapter managed":"Shared chassis group");}
        var detected=new List<string>();bool added=false;Action<string,string,object> add=(id,label,value)=>{if(value==null)return;detected.Add(id);if(!curves.Any(c=>c.Source==id)){curves.Add(new SensorFanCurve{Source=id,Label=label,Enabled=false,Points=FanCurveModel.Defaults()});added=true;}};
        add("CpuMax","CPU maximum",Get(ipmi,"CpuMax"));add("GpuMax","GPU maximum",Get(gpu,"Temp"));add("Exhaust","Exhaust",Get(ipmi,"Exhaust"));add("Inlet","Inlet",Get(ipmi,"Inlet"));add("SystemMax","System maximum",Get(ipmi,"SystemMax"));
        var temps=Get(ipmi,"Temps") as IEnumerable;var counts=new Dictionary<string,int>();if(temps!=null)foreach(var item in temps){var row=item as Dictionary<string,object>;if(row==null)continue;string name=Convert.ToString(Get(row,"Name"));int n=counts.ContainsKey(name)?counts[name]:0;counts[name]=n+1;add("Temp:"+name+":"+n,name+" #"+(n+1),Get(row,"Value"));}
        if(added||inventory!=String.Join("|",detected)){inventory=String.Join("|",detected);RefillSources();}
        if(Current!=null){bool available=detected.Contains(Current.Source);sample.Text=available?mode.SelectedIndex==2?"Custom graph preview":"Draft graph (inactive in this mode)":"Sensor unavailable in this sample";sample.ForeColor=available?Color.Aquamarine:Color.Orange;}
    }
    static object Get(Dictionary<string,object> d,string key){return d!=null&&d.ContainsKey(key)?d[key]:null;}
    public static void SelfTest(){
        FanCurveModel.SelfTest();using(var editor=new FanCurveEditor()){
            var config=new Dictionary<string,object>{{"Smart",true}};editor.LoadConfig(config,false);if(editor.mode.SelectedIndex!=1)throw new Exception("Legacy smart mode lost");
            var snapshot=new Dictionary<string,object>{{"Ipmi",new Dictionary<string,object>{{"CpuMax",50},{"Exhaust",35},{"Inlet",23},{"Temps",new object[]{new Dictionary<string,object>{{"Name","Temp"},{"Value",49}},new Dictionary<string,object>{{"Name","Temp"},{"Value",50}}}},{"Fans",new object[]{new Dictionary<string,object>{{"Name","Fan1"},{"Value",8400}},new Dictionary<string,object>{{"Name","Fan2"},{"Value",8400}}}}}}};
            editor.Feed(snapshot);if(editor.fanList.Rows.Count!=2||editor.source.Items.Count!=5||!Convert.ToString(editor.fanList.Rows[0].Cells[2].Value).Contains("Shared"))throw new Exception("Detected fan/sensor population failed");
            editor.mode.SelectedIndex=2;editor.source.SelectedIndex=0;editor.use.Checked=true;editor.CaptureSettings(config);if(Convert.ToString(config["FanCurveMode"])!="Custom")throw new Exception("Custom mode lost");
            var json=new System.Web.Script.Serialization.JavaScriptSerializer();var reloaded=json.Deserialize<Dictionary<string,object>>(json.Serialize(config));editor.LoadConfig(reloaded,false);if(editor.mode.SelectedIndex!=2||!editor.curves[0].Enabled)throw new Exception("Curve settings round trip failed");
            editor.SetRunning(true,false);if(editor.save.Enabled||editor.graph.Enabled||editor.mode.Enabled)throw new Exception("Live curve editing allowed");editor.SetRunning(false,false);if(!editor.save.Enabled)throw new Exception("Stopped editor locked");
            editor.LoadConfig(config,true);if(editor.save.Enabled||editor.mode.Enabled)throw new Exception("Unsupported adapter allowed custom output");
        }
    }
}
