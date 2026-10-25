using System;
using System.Collections.Generic;
public sealed class ReconnectPolicy {
    public bool Wanted,Live;public DateTime? Due;public int Attempts;
    public void Start(bool live){Wanted=true;Live=live;Due=null;Attempts=0;}
    public void Cancel(){Wanted=false;Due=null;Attempts=0;}
    public bool Schedule(Dictionary<string,object> status,DateTime now){
        if(!Wanted||status==null||!status.ContainsKey("RetryAllowed")||!Object.Equals(status["RetryAllowed"],true)||status.ContainsKey("StopRequested")&&Object.Equals(status["StopRequested"],true)){Cancel();return false;}
        string reason=status.ContainsKey("ExitReason")?Convert.ToString(status["ExitReason"]):"";
        if(reason!="TelemetryUnavailable"&&reason!="ConnectionOrCommandFailure"){Cancel();return false;}
        Attempts++;Due=now.AddSeconds(Math.Min(300,10*Math.Pow(2,Math.Min(Attempts-1,5))));return true;
    }
    public static void SelfTest(){
        var policy=new ReconnectPolicy();var now=DateTime.UtcNow;
        var transient=new Dictionary<string,object>{{"RetryAllowed",true},{"ExitReason","TelemetryUnavailable"},{"StopRequested",false}};
        if(policy.Schedule(transient,now))throw new Exception("Restarted without user intent");
        policy.Start(true);if(!policy.Schedule(transient,now)||policy.Due!=now.AddSeconds(10)||!policy.Live)throw new Exception("Initial retry failed");
        if(!policy.Schedule(transient,now)||policy.Due!=now.AddSeconds(20))throw new Exception("Retry backoff failed");
        for(int i=0;i<20;i++)policy.Schedule(transient,now);if(policy.Due!=now.AddSeconds(300))throw new Exception("Retry delay uncapped");
        policy.Cancel();if(policy.Due.HasValue||policy.Schedule(transient,now))throw new Exception("Stop failed to cancel retry");
        foreach(string reason in new[]{"UserStop","Completed","HardwareSafetyFault","ConfigurationOrUnexpectedFault","Unknown"}){policy.Start(true);var fault=new Dictionary<string,object>{{"RetryAllowed",true},{"ExitReason",reason}};if(policy.Schedule(fault,now))throw new Exception("Unsafe restart: "+reason);}
        policy.Start(true);transient["StopRequested"]=true;if(policy.Schedule(transient,now))throw new Exception("External/user stop restarted");
        policy.Start(false);if(policy.Schedule(null,now))throw new Exception("Unknown crash restarted");
    }
}
