/// WebSocket relay בין המשתמש לעוזר.
/// אימות לפי code + טוקן, כך שאין תלות ב-CSP session או בהתחברות -
/// עובד ממסך ה-login וממשיך גם אחרי שהמשתמש נכנס למערכת.
/// הקוד והטוקן מגיעים בהודעה הראשונה על הסוקט {"k":"auth","code":..,"t":..} ולא ב-URL,
/// כדי שלא יירשמו בלוגים של IIS / ה-Web Gateway.
/// הסכמה לצפייה/שליטה נאכפת כאן בשרת.
Class TafnitCore.System.UI.App.Tools.Helper.Relay Extends %CSP.WebSocket
{

/// כמה שניות לחכות להודעת האימות לפני ניתוק
Parameter AUTHTIMEOUT = 5;

/// כמה חיבורים יכולים לחכות לאימות בו-זמנית. כל חיבור כזה תופס תהליך ורישיון של IRIS,
/// ולכן מעבר לזה חיבור חדש נסגר מיד (הדפדפן מנסה שוב אחרי 2 שניות).
Parameter MAXPENDING = 30;

/// תקרת הודעות שמחכות בתור של הצד השני (צד שלא קורא) - מעבר לזה הודעות נזרקות
Parameter MAXQUEUE = 2000;

/// תקרת נפח (תווים) שחיבור אחד יכול לשלוח בחלון של 10 שניות - מעבר לזה הודעות נזרקות
Parameter MAXBYTES = 50000000;

Property Code As %String;

Property Role As %String;

/// הכתובת (SERVER_NAME) של הסשן - זו שבה נוצר הקוד, לא כותרת Host של החיבור הזה
Property Host As %String;

/// REMOTE_ADDR ו-X-Forwarded-For של החיבור, נשמרים ב-OnPreServer (שם %request זמין).
/// כתובת הלקוח מחושבת מהם רק אחרי האימות, לפי TRUSTPROXY של הכתובת של הסשן.
Property Remote As %String(MAXLEN = 64);

Property Forwarded As %String(MAXLEN = 2000);

/// האם החיבור הגיע ב-HTTPS (wss), ו-X-Forwarded-Proto - נשמרים ב-OnPreServer
Property Secure As %Boolean [ InitialExpression = 0 ];

Property Proto As %String(MAXLEN = 64);

/// מונה הנפח של החלון הנוכחי (MAXBYTES)
Property WinStart As %Numeric [ InitialExpression = 0 ];

Property WinBytes As %Numeric [ InitialExpression = 0 ];

Method OnPreServer() As %Status
{
    set ..Secure=''%request.Secure
    set ..Proto=$EXTRACT($GET(%request.CgiEnvs("HTTP_X_FORWARDED_PROTO")),*-63,*)
    set ..Remote=$EXTRACT($GET(%request.CgiEnvs("REMOTE_ADDR")),1,64)
    set ..Forwarded=$EXTRACT($GET(%request.CgiEnvs("HTTP_X_FORWARDED_FOR")),*-1999,*)
    quit $$$OK
}

/// בודק את הודעת האימות; מחזיר את התפקיד (user/helper) או "" אם נדחה
Method Authenticate(pData As %String) As %String
{
    set tIn=""
    try { set tIn={}.%FromJSON(pData) } catch {}
    if '$ISOBJECT(tIn) quit ""
    if tIn.k'="auth" quit ""
    set tObj=##class(TafnitCore.System.UI.App.Tools.Helper.Session).OpenByCode(tIn.code)
    if '$ISOBJECT(tObj) quit ""

    set tRole=tObj.RoleOf(tIn.t)
    if tRole="" quit ""
    if tObj.Host="" quit ""
    if ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Param("REQUIREHTTPS",tObj.Host),'##class(TafnitCore.System.UI.App.Tools.Helper.Session).ResolveSecure(..Secure,..Proto,tObj.Host) quit ""

    if tRole="helper" {
        if tObj.Status'="Active" quit ""
        set tIP=##class(TafnitCore.System.UI.App.Tools.Helper.Session).ResolveIP(..Remote,..Forwarded,tObj.Host)
        if '##class(TafnitCore.System.UI.App.Tools.Helper.Session).IPAllowed(tIP,tObj.Host) quit ""
    }
    set ..Code=tObj.Code
    set ..Host=tObj.Host
    quit tRole
}

Method Server() As %Status
{
    // הגבלת חיבורים שמחכים לאימות (רשומה לכל תהליך; רשומה ישנה מ-30 שניות נחשבת מתה)
    set tNow=##class(TafnitCore.System.UI.App.Tools.Helper.Session).NowSec(), tPend=0, j=""
    for {
        set j=$ORDER(^IRIS.Temp.xTafnitRH("pend",j),1,t) quit:j=""
        if (tNow-t)<30 { set tPend=tPend+1 } else { kill ^IRIS.Temp.xTafnitRH("pend",j) }
    }
    if tPend>=..#MAXPENDING quit $$$OK
    set ^IRIS.Temp.xTafnitRH("pend",$JOB)=tNow

    // אימות: ההודעה הראשונה חייבת להיות auth תקין
    set tLen=4000, tSC=$$$OK
    set tData=..Read(.tLen,.tSC,..#AUTHTIMEOUT)
    kill ^IRIS.Temp.xTafnitRH("pend",$JOB)
    set ..Role=$SELECT($$$ISERR(tSC):"",1:..Authenticate(tData))
    if ..Role="" {
        do ..Write({"k":"m","t":"denied"}.%ToJSON())
        quit $$$OK
    }

    set tMe=..Role
    set ^IRIS.Temp.xTafnitRH("conn",..Code,tMe)=1
    
    if tMe="helper" {
        do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Enqueue(..Code,"user",{"k":"m","t":"need-snap"}.%ToJSON())
    } else {
        do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Enqueue(..Code,"helper",{"k":"m","t":"user-online"}.%ToJSON())
    }
    
    set tQuit=0
    while 'tQuit {
        // 1) ריקון התור אל הסוקט
        set k=""
        for {
            set k=$ORDER(^IRIS.Temp.xTafnitRH("q",..Code,tMe,k),1,tMsg)
            quit:k=""
            kill ^IRIS.Temp.xTafnitRH("q",..Code,tMe,k)
            set tSC=..Write(tMsg)
            if $$$ISERR(tSC) { set tQuit=1 quit }
        }
        if tQuit quit
        
        // 2) סגירה / תפוגה
        if $GET(^IRIS.Temp.xTafnitRH("closed",..Code)) quit
        if ##class(TafnitCore.System.UI.App.Tools.Helper.Session).NowSec()>$GET(^IRIS.Temp.xTafnitRH("s",..Code)) {
            do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).CloseByCode(..Code,"system")
            quit
        }
        
        // 3) קריאה (timeout קצר = polling של התור; אם ערך שבור לא נתמך אצלך - שנה ל-1)
        set tLen=32000
        set tSC=$$$OK
        set tData=..Read(.tLen,.tSC,0.2)
        if $$$ISERR(tSC) {
            if $$$GETERRORCODE(tSC)'=$$$CSPWebSocketTimeout { quit }
        } else {
            do ..Dispatch(tData)
        }
    }
    quit $$$OK
}

Method Dispatch(pData As %String)
{
    // תקרת נפח לחיבור
    set tNow=##class(TafnitCore.System.UI.App.Tools.Helper.Session).NowSec()
    if (tNow-..WinStart)>=10 set ..WinStart=tNow, ..WinBytes=0
    set ..WinBytes=..WinBytes+$LENGTH(pData)
    if ..WinBytes>..#MAXBYTES quit

    // frames של תמונת מסך - רק מהמשתמש ורק אחרי הסכמה לצפייה
    if $EXTRACT(pData,1,8)="{""k"":""c""" {
        if ..Role'="user" quit
        if '$GET(^IRIS.Temp.xTafnitRH("view",..Code)) quit
        do ..Forward(pData)
        quit
    }
    
    try { set tMsg={}.%FromJSON(pData) } catch { quit }
    set tType=tMsg.t
    
    if ..Role="user" {
        if tType="grant" {
            set tCtl=$SELECT(tMsg.control:1,1:0)
            set ^IRIS.Temp.xTafnitRH("view",..Code)=1
            set ^IRIS.Temp.xTafnitRH("ctl",..Code)=tCtl
            do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).SetControl(..Code,tCtl)
            do ..Forward({"k":"m","t":"grant","control":(tCtl)}.%ToJSON())
        } elseif tType="login-done" {
            do ..OnUserLogin()
        }
    } else {
        if tType'="evt" quit
        if '$GET(^IRIS.Temp.xTafnitRH("ctl",..Code)) quit
        do ..Forward(pData)
    }
}

/// המשתמש עבר ממסך ה-login למערכת. ההודעה מגיעה רק מצד המשתמש,
/// והיא יכולה רק לצמצם את הגישה של העוזר - לכן אין צורך לאמת אותה מול ה-login עצמו.
Method OnUserLogin()
{
    set tObj=##class(TafnitCore.System.UI.App.Tools.Helper.Session).OpenByCode(..Code)
    if '$ISOBJECT(tObj) quit
    set tPolicy=##class(TafnitCore.System.UI.App.Tools.Helper.Session).Param("LOGINPOLICY",..Host)
    
    if tObj.Scope="login" {
        set tObj.Scope="app"
        do tObj.%Save()
        do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Audit("UserLogin","code="_..Code_" policy="_tPolicy_" helper="_tObj.HelperName)
        
        if tPolicy="end" {
            do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).CloseByCode(..Code,"system")
            quit
        }
        if tPolicy="reconsent" {
            set ^IRIS.Temp.xTafnitRH("view",..Code)=0
            set ^IRIS.Temp.xTafnitRH("ctl",..Code)=0
            do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).SetControl(..Code,0)
            do ..Forward({"k":"m","t":"paused"}.%ToJSON())
        }
    }
    
    if $GET(^IRIS.Temp.xTafnitRH("view",..Code)) {
        // continue (או אושר כבר מחדש) - ממשיכים עם ההרשאות הקיימות
        do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Enqueue(..Code,"user",{"k":"m","t":"resume-ok","control":($GET(^IRIS.Temp.xTafnitRH("ctl",..Code))+0)}.%ToJSON())
    } elseif tObj.Status="Active" {
        do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Enqueue(..Code,"user",{"k":"m","t":"reconsent","helper":(tObj.HelperName)}.%ToJSON())
    }
}

Method Forward(pData As %String)
{
    set tPeer=$CASE(..Role,"user":"helper",:"user")
    if '$GET(^IRIS.Temp.xTafnitRH("conn",..Code,tPeer)) quit
    // הצד השני לא קורא - לא ממלאים את IRISTEMP
    set tFirst=$ORDER(^IRIS.Temp.xTafnitRH("q",..Code,tPeer,""))
    if tFirst'="",($GET(^IRIS.Temp.xTafnitRH("seq",..Code))-tFirst)>..#MAXQUEUE quit
    do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Enqueue(..Code,tPeer,pData)
}

Method OnPostServer() As %Status
{
    kill ^IRIS.Temp.xTafnitRH("pend",$JOB)
    // חיבור שלא עבר אימות - אין מה לנקות
    if (..Code="")||(..Role="") quit $$$OK
    kill ^IRIS.Temp.xTafnitRH("conn",..Code,..Role)
    
    // המשתמש עשוי לעבור דף (למשל מ-Login למסך הראשי) - ה-agent יתחבר מחדש, לכן לא סוגרים
    if ..Role="user" {
        do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Enqueue(..Code,"helper",{"k":"m","t":"user-offline"}.%ToJSON())
    } else {
        do ##class(TafnitCore.System.UI.App.Tools.Helper.Session).Enqueue(..Code,"user",{"k":"m","t":"helper-left"}.%ToJSON())
    }
    
    if $GET(^IRIS.Temp.xTafnitRH("closed",..Code)),'$DATA(^IRIS.Temp.xTafnitRH("conn",..Code)) {
        kill ^IRIS.Temp.xTafnitRH("q",..Code),^IRIS.Temp.xTafnitRH("s",..Code)
        kill ^IRIS.Temp.xTafnitRH("view",..Code),^IRIS.Temp.xTafnitRH("ctl",..Code),^IRIS.Temp.xTafnitRH("seq",..Code)
    }
    quit $$$OK
}

}
