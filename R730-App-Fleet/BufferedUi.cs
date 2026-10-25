using System.Windows.Forms;
public sealed class BufferedTableLayoutPanel : TableLayoutPanel {public BufferedTableLayoutPanel(){DoubleBuffered=true;SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}}
public sealed class BufferedFlowLayoutPanel : FlowLayoutPanel {public BufferedFlowLayoutPanel(){DoubleBuffered=true;}}
public sealed class BufferedPanel : Panel {public BufferedPanel(){DoubleBuffered=true;}}
public sealed class BufferedTabControl : TabControl {
    public BufferedTabControl(){DoubleBuffered=true;}
    // Native tab frames and their child windows paint together, avoiding a white intermediate frame.
    protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x02000000;return p;}}
}
public sealed class BufferedDataGridView : DataGridView {public BufferedDataGridView(){DoubleBuffered=true;}}
public sealed class ReadableComboBox : ComboBox {
    public ReadableComboBox(){DrawMode=DrawMode.OwnerDrawFixed;DropDownStyle=ComboBoxStyle.DropDownList;ItemHeight=22;BackColor=System.Drawing.Color.FromArgb(29,36,47);ForeColor=System.Drawing.Color.White;}
    protected override void OnDrawItem(DrawItemEventArgs e){using(var fill=new System.Drawing.SolidBrush(BackColor))e.Graphics.FillRectangle(fill,e.Bounds);string text=e.Index>=0&&e.Index<Items.Count?GetItemText(Items[e.Index]):Text;using(var ink=new System.Drawing.SolidBrush(Enabled?ForeColor:System.Drawing.Color.Silver))e.Graphics.DrawString(text,Font,ink,e.Bounds.X+3,e.Bounds.Y+2);e.DrawFocusRectangle();}
}
public sealed class ReadableSelector : Control {
    public readonly System.Collections.Generic.List<object> Items=new System.Collections.Generic.List<object>();int selected=-1;
    public event System.EventHandler SelectedIndexChanged;
    public int SelectedIndex{get{return selected;}set{selected=value>=0&&value<Items.Count?value:-1;Text=SelectedItem==null?"Monitor to discover sensors":SelectedItem.ToString();Invalidate();if(SelectedIndexChanged!=null)SelectedIndexChanged(this,System.EventArgs.Empty);}}
    public object SelectedItem{get{return selected>=0&&selected<Items.Count?Items[selected]:null;}}
    public ReadableSelector(){DoubleBuffered=true;Height=28;TabStop=true;SetStyle(ControlStyles.Selectable,true);BackColor=System.Drawing.Color.FromArgb(29,36,47);ForeColor=System.Drawing.Color.White;AccessibleRole=AccessibleRole.ComboBox;Cursor=Cursors.Hand;}
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);using(var fill=new System.Drawing.SolidBrush(BackColor))e.Graphics.FillRectangle(fill,ClientRectangle);using(var border=new System.Drawing.Pen(System.Drawing.Color.SlateGray))e.Graphics.DrawRectangle(border,0,0,Width-1,Height-1);using(var ink=new System.Drawing.SolidBrush(Enabled?ForeColor:System.Drawing.Color.Silver)){string text=SelectedItem==null?"Monitor to discover sensors":SelectedItem.ToString();var rect=new System.Drawing.RectangleF(6,4,System.Math.Max(1,Width-28),Height-5);using(var format=new System.Drawing.StringFormat{Trimming=System.Drawing.StringTrimming.EllipsisCharacter,FormatFlags=System.Drawing.StringFormatFlags.NoWrap})e.Graphics.DrawString(text,Font,ink,rect,format);e.Graphics.DrawString("v",Font,ink,Width-19,4);}if(Focused)ControlPaint.DrawFocusRectangle(e.Graphics,ClientRectangle);}
    void OpenMenu(){if(!Enabled||Items.Count==0)return;var menu=new ContextMenuStrip{BackColor=BackColor,ForeColor=ForeColor};for(int i=0;i<Items.Count;i++){int choice=i;var item=new ToolStripMenuItem(Items[i].ToString()){Checked=i==selected};item.Click+=(s,e)=>SelectedIndex=choice;menu.Items.Add(item);}menu.Closed+=(s,e)=>menu.Dispose();menu.Show(this,new System.Drawing.Point(0,Height));}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(e.Button==MouseButtons.Left){Focus();OpenMenu();}}
    protected override bool IsInputKey(Keys keyData){return keyData==Keys.Up||keyData==Keys.Down||keyData==Keys.Space||keyData==Keys.Enter||base.IsInputKey(keyData);}
    protected override void OnKeyDown(KeyEventArgs e){base.OnKeyDown(e);if(e.KeyCode==Keys.Down)SelectedIndex=System.Math.Min(Items.Count-1,selected+1);else if(e.KeyCode==Keys.Up)SelectedIndex=System.Math.Max(0,selected-1);else if(e.KeyCode==Keys.Space||e.KeyCode==Keys.Enter)OpenMenu();}
}
