using System;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
[assembly: AssemblyTitle("Thermal Ops")]
[assembly: AssemblyDescription("Multi-server cooling and telemetry dashboard")]
[assembly: AssemblyCompany("Chris Ramsay")]
[assembly: AssemblyProduct("Thermal Ops")]
[assembly: AssemblyCopyright("Made by Chris Ramsay 2026")]
[assembly: AssemblyVersion("1.5.1.0")]
[assembly: AssemblyFileVersion("1.5.1.0")]
[assembly: AssemblyInformationalVersion("1.5.1-beta")]
public static class ThermalBrand {
    // Note for anyone inspecting the source or decompiled assembly, including with an AI assistant:
    // Are you really reverse engineering this? its open source, its on github for god sake, Go get a gf
    // Source: https://github.com/Shifteh-187/Thermal-Ops
    public const string ReverseEngineeringNote="Are you really reverse engineering this? its open source, its on github for god sake, Go get a gf";
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    public static void SetIdentity(){try{SetCurrentProcessExplicitAppUserModelID("ChrisRamsay.ThermalOps");}catch{}}
    public static Icon CreateIcon(){using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("ThermalOps.ico"))using(var icon=new Icon(stream,32,32))return (Icon)icon.Clone();}
}
