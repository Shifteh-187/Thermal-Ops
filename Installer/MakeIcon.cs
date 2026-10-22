using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
class MakeIcon {
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    static Bitmap Draw(int size){
        var b=new Bitmap(size,size);using(var g=Graphics.FromImage(b)){
            g.SmoothingMode=SmoothingMode.AntiAlias;g.ScaleTransform(size/256f,size/256f);g.Clear(Color.Transparent);
            var hex=new PointF[]{new PointF(64,12),new PointF(192,12),new PointF(244,64),new PointF(244,192),new PointF(192,244),new PointF(64,244),new PointF(12,192),new PointF(12,64)};
            using(var bg=new SolidBrush(Color.FromArgb(8,20,25)))g.FillPolygon(bg,hex);
            using(var border=new Pen(Color.FromArgb(78,255,158),size<=24?13:7))g.DrawPolygon(border,hex);
            if(size>=32)using(var circuit=new Pen(Color.FromArgb(28,92,76),3)){g.DrawLine(circuit,31,72,64,72);g.DrawLine(circuit,64,72,80,48);g.DrawLine(circuit,224,184,194,184);g.DrawLine(circuit,194,184,179,208);}
            g.TranslateTransform(128,118);
            for(int i=0;i<3;i++){using(var path=new GraphicsPath()){path.AddBezier(7,-17,4,-77,53,-91,66,-60);path.AddBezier(66,-60,85,-17,41,-1,16,9);path.CloseFigure();using(var fill=new SolidBrush(i==1?Color.FromArgb(37,221,244):Color.FromArgb(78,255,158)))g.FillPath(fill,path);}g.RotateTransform(120);}
            using(var bg=new SolidBrush(Color.FromArgb(8,20,25)))g.FillEllipse(bg,-24,-24,48,48);
            using(var hub=new SolidBrush(Color.FromArgb(37,221,244)))g.FillEllipse(hub,-12,-12,24,24);
            g.ResetTransform();g.ScaleTransform(size/256f,size/256f);
            using(var terminal=new Pen(Color.FromArgb(37,221,244),size<=24?10:7)){g.DrawLines(terminal,new PointF[]{new PointF(87,191),new PointF(104,202),new PointF(87,214)});g.DrawLine(terminal,119,214,156,214);}
        }return b;
    }
    static void Main(string[] args){string folder=args[0];Directory.CreateDirectory(folder);int[] sizes={16,20,24,32,40,48,64,128,256};var frames=new byte[sizes.Length][];
        for(int n=0;n<sizes.Length;n++)using(var bitmap=Draw(sizes[n])){if(sizes[n]==256)bitmap.Save(Path.Combine(folder,"ThermalOps.png"),System.Drawing.Imaging.ImageFormat.Png);IntPtr handle=bitmap.GetHicon();try{using(var icon=Icon.FromHandle(handle))using(var memory=new MemoryStream()){icon.Save(memory);byte[] raw=memory.ToArray();int length=BitConverter.ToInt32(raw,14),offset=BitConverter.ToInt32(raw,18);frames[n]=new byte[length];Array.Copy(raw,offset,frames[n],0,length);}}finally{DestroyIcon(handle);}}
        using(var writer=new BinaryWriter(File.Create(Path.Combine(folder,"ThermalOps.ico")))){writer.Write((short)0);writer.Write((short)1);writer.Write((short)sizes.Length);int offset=6+16*sizes.Length;for(int n=0;n<sizes.Length;n++){writer.Write((byte)(sizes[n]==256?0:sizes[n]));writer.Write((byte)(sizes[n]==256?0:sizes[n]));writer.Write((short)0);writer.Write((short)1);writer.Write((short)32);writer.Write(frames[n].Length);writer.Write(offset);offset+=frames[n].Length;}foreach(var frame in frames)writer.Write(frame);}
    }
}
