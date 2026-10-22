using System;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
[assembly: AssemblyTitle("Thermal Ops")]
[assembly: AssemblyDescription("Multi-server cooling and telemetry dashboard")]
[assembly: AssemblyCompany("Chris Ramsay")]
[assembly: AssemblyProduct("Thermal Ops")]
[assembly: AssemblyCopyright("Made by Chris Ramsay 2026")]
[assembly: AssemblyVersion("1.4.0.0")]
[assembly: AssemblyFileVersion("1.4.0.0")]
public static class ThermalBrand {
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    public static void SetIdentity(){try{SetCurrentProcessExplicitAppUserModelID("ChrisRamsay.ThermalOps");}catch{}}
    public static Icon CreateIcon(){using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("ThermalOps.ico"))using(var icon=new Icon(stream,32,32))return (Icon)icon.Clone();}
}
