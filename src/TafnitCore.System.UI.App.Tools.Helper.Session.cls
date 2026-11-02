/// ניהול סשנים של עזרה מרחוק ב-xTafnit.
/// הזיהוי בין הצדדים נעשה בטוקן סודי (לא ב-CSP session), כך שזה עובד גם ממסך login
/// (משתמש אנונימי), גם לעוזר חיצוני, וגם כשהמשתמש מתחבר באמצע הסשן.
/// כל הגישה לטבלה ב-embedded SQL / objects, כך ש-UnknownUser לא צריך הרשאות SQL.
///
/// כל Parameter כאן הוא ברירת מחדל. אפשר לדרוס אותו לכל כתובת (SERVER_NAME) בלי קומפילציה:
///   s ^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",{host},"helper",{PARAMETER})={value}
/// למשל ("BaseURLs","erp.example.co.il","helper","HELPERIPS")="10.0.5."  - ראה Param()
Class TafnitCore.System.UI.App.Tools.Helper.Session Extends %Persistent
{

/// 0 = כיבוי הצטרפות עם קוד בלבד (helper.html). HelperPage ו-HTTP Basic ממשיכים לעבוד
Parameter ANONYMOUSHELPER = 1;

/// תוקף הקוד עד שעוזר מצטרף (שניות)
Parameter CODETTL = 600;

/// משך מקסימלי של סשן פעיל (שניות)
Parameter MAXSESSION = 3600;

/// ניסיונות הצטרפות שגויים עד חסימה
Parameter MAXFAILS = 5;

/// משך החסימה (שניות)
Parameter LOCKSECS = 900;

/// כמה קודים אפשר ליצור מאותו IP בחלון של 10 דקות (הגנה על מסך ה-login האנונימי)
Parameter MAXCREATES = 5;

/// כתובות/קידומות IP מותרות לעוזר, מופרדות בפסיק. ריק = ללא הגבלה.
/// דוגמה: "203.0.113.,198.51.100.25" (קידומת חייבת להסתיים בנקודה)
Parameter HELPERIPS;

/// 1 אם השרת מאחורי reverse proxy שמוסיף X-Forwarded-For אמין
Parameter TRUSTPROXY = 0;

/// מה קורה כשמשתמש שביקש עזרה ממסך ה-login מתחבר למערכת:
///   reconsent - העוזר מאבד גישה (צפייה ושליטה) עד שהמשתמש מאשר שוב  [ברירת מחדל]
///   end       - הסשן מסתיים אוטומטית
///   continue  - הסשן ממשיך כרגיל
Parameter LOGINPOLICY = "reconsent";

Property Code As %String(MAXLEN = 6) [ Required ];

/// login = נוצר ממסך הכניסה (משתמש אנונימי), app = מתוך המערכת
Property Scope As %String(VALUELIST = ",login,app") [ InitialExpression = "app" ];

Property UserName As %String(MAXLEN = 128);

Property UserIP As %String(MAXLEN = 64);

Property UserTokenHash As %String(MAXLEN = 100);

Property HelperName As %String(MAXLEN = 128);

Property HelperIP As %String(MAXLEN = 64);

Property HelperTokenHash As %String(MAXLEN = 100);

Property Status As %String(VALUELIST = ",Pending,Active,Closed,Expired") [ InitialExpression = "Pending" ];

Property ControlGranted As %Boolean [ InitialExpression = 0 ];

Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP,3,1,3)} ];

Property ClosedAt As %TimeStamp;

Property ExpiresSec As %Numeric(SCALE = 3);

Index CodeIdx On (Code, Status);

Index UserIdx On (UserName, Status);

/* ───────────── כלים ───────────── */

/// הכתובת שבה גולשים (SERVER_NAME) - המפתח של הפרמטרים ב-xTafnitParams("BaseURLs")
ClassMethod Host() As %String
{
    if '$ISOBJECT($GET(%request)) quit ""
    quit $GET(%request.CgiEnvs("SERVER_NAME"))
}

/// ערך פרמטר לכתובת: ^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",host,"helper",name),
/// ואם לא מוגדר - ה-Parameter של המחלקה באותו שם
ClassMethod Param(pName As %String, pHost As %String = "") As %String
{
    set tDefault=$PARAMETER(..%ClassName(1),pName)
    if pHost="" set pHost=..Host()
    if pHost="" quit tDefault
    quit $GET(^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",pHost,"helper",pName),tDefault)
}

ClassMethod NowSec() As %Numeric
{
    set t=$ZTIMESTAMP
    quit ($PIECE(t,",",1)*86400)+$PIECE(t,",",2)
}

/// טוקן אקראי (base64url, 32 תווים)
ClassMethod NewToken() As %String
{
    quit $TRANSLATE($SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(24)),"+/=","-_")
}

/// נשמר רק hash של הטוקן
ClassMethod Hash(pToken As %String) As %String
{
    quit $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHAHash(256,pToken))
}

ClassMethod ClientIP() As %String
{
    if '$ISOBJECT($GET(%request)) quit ""
    set tIP=$GET(%request.CgiEnvs("REMOTE_ADDR"))
    if ..Param("TRUSTPROXY") {
        set tFwd=$ZSTRIP($PIECE($GET(%request.CgiEnvs("HTTP_X_FORWARDED_FOR")),",",1),"<>W")
        if tFwd'="" set tIP=tFwd
    }
    quit tIP
}

ClassMethod IPAllowed(pIP As %String, pHost As %String = "") As %Boolean
{
    set tList=..Param("HELPERIPS",pHost)
    if tList="" quit 1
    set tOK=0
    for i=1:1:$LENGTH(tList,",") {
        set p=$ZSTRIP($PIECE(tList,",",i),"<>W")
        if (p'="")&&($EXTRACT(pIP,1,$LENGTH(p))=p) { set tOK=1 quit }
    }
    quit tOK
}

/// פתיחת סשן לפי קוד (Pending/Active, או Active בלבד)
ClassMethod OpenByCode(pCode As %String, pActiveOnly As %Boolean = 0) As TafnitCore.System.UI.App.Tools.Helper.Session
{
    set tCode=$TRANSLATE($GET(pCode)," ")
    if tCode'?6N quit ""
    set tID=""
    if pActiveOnly {
        &sql(SELECT ID INTO :tID FROM TafnitCore_System_UI_App_Tools_Helper.Session WHERE Code=:tCode AND Status='Active')
    } else {
        &sql(SELECT ID INTO :tID FROM TafnitCore_System_UI_App_Tools_Helper.Session WHERE Code=:tCode AND Status IN ('Pending','Active'))
    }
    quit $SELECT(SQLCODE=0:..%OpenId(tID),1:"")
}

/// איזה צד מחזיק בטוקן: user | helper | ""
Method RoleOf(pToken As %String) As %String
{
    if $GET(pToken)="" quit ""
    set h=..Hash(pToken)
    if h=..UserTokenHash quit "user"
    if (..HelperTokenHash'="")&&(h=..HelperTokenHash) quit "helper"
    quit ""
}

ClassMethod ActiveCodeExists(pCode As %String) As %Boolean
{
    set n=0
    &sql(SELECT COUNT(*) INTO :n FROM TafnitCore_System_UI_App_Tools_Helper.Session WHERE Code=:pCode AND Status IN ('Pending','Active'))
    quit (SQLCODE=0)&&(n>0)
}

/// הגבלת יצירת קודים לפי IP
ClassMethod CreateAllowed(pIP As %String) As %Boolean
{
    set tNow=..NowSec()
    set d=$GET(^IRIS.Temp.xTafnitRH("cr",pIP))
    if (d="")||($LIST(d,1)<tNow) {
        set ^IRIS.Temp.xTafnitRH("cr",pIP)=$LISTBUILD(tNow+600,1)
        quit 1
    }
    if $LIST(d,2)>=..Param("MAXCREATES") quit 0
    set $LIST(^IRIS.Temp.xTafnitRH("cr",pIP),2)=$LIST(d,2)+1
    quit 1
}

/* ───────────── פעולות ───────────── */

/// יצירת קוד. עובד גם למשתמש אנונימי (מסך login).
ClassMethod Create(Output pCode As %String, Output pToken As %String, Output pScope As %String) As %Status
{
    set (pCode,pToken,pScope)=""
    try {
        set tUser=$USERNAME
        set tIP=..ClientIP()
        set tScope=$SELECT(tUser="UnknownUser":"login",1:"app")
        
        if '..CreateAllowed(tIP) {
            do ..Audit("CreateThrottled","ip="_tIP)
            throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError,"too many requests"))
        }
        
        // משתמש מחובר: סשן פעיל אחד בלבד. (לא עבור UnknownUser - אחרת אנונימי אחד יסגור לכולם)
        if tScope="app" {
            set c=""
            &sql(DECLARE RHC1 CURSOR FOR SELECT Code INTO :c FROM TafnitCore_System_UI_App_Tools_Helper.Session WHERE UserName=:tUser AND Status IN ('Pending','Active'))
            &sql(OPEN RHC1)
            for { &sql(FETCH RHC1) quit:SQLCODE  set tOld(c)="" }
            &sql(CLOSE RHC1)
            set c="" for { set c=$ORDER(tOld(c)) quit:c=""  do ..CloseByCode(c,"system") }
        }
        
        // קוד ייחודי בן 6 ספרות
        set tCode=""
        for i=1:1:20 {
            set n=$ZABS($ZLASCII($SYSTEM.Encryption.GenCryptRand(4)))#1000000
            set c=$TRANSLATE($JUSTIFY(n,6)," ","0")
            if '..ActiveCodeExists(c) { set tCode=c quit }
        }
        if tCode="" throw ##class(%Exception.StatusException).CreateFromStatus($$$ERROR($$$GeneralError,"Could not allocate code"))
        
        set tToken=..NewToken()
        set tObj=..%New()
        set tObj.Code=tCode
        set tObj.Scope=tScope
        set tObj.UserName=tUser
        set tObj.UserIP=tIP
        set tObj.UserTokenHash=..Hash(tToken)
        set tObj.ExpiresSec=..NowSec()+..Param("CODETTL")
        $$$ThrowOnError(tObj.%Save())
        
        kill ^IRIS.Temp.xTafnitRH("q",tCode),^IRIS.Temp.xTafnitRH("conn",tCode),^IRIS.Temp.xTafnitRH("closed",tCode)
        kill ^IRIS.Temp.xTafnitRH("view",tCode),^IRIS.Temp.xTafnitRH("ctl",tCode),^IRIS.Temp.xTafnitRH("seq",tCode)
        set ^IRIS.Temp.xTafnitRH("s",tCode)=tObj.ExpiresSec
        
        set pCode=tCode, pToken=tToken, pScope=tScope
        do ..Audit("Create","scope="_tScope_" user="_tUser_" ip="_tIP)
        set tSC=$$$OK
    } catch ex {
        set tSC=ex.AsStatus()
    }
    quit tSC
}

/// הצטרפות עוזר. דורש משתמש מאומת עם xTafnit_RemoteSupport:USE ו-IP מורשה.
ClassMethod Join(pCode As %String, Output pToken As %String) As %Status
{
    set pToken=""
    if ($USERNAME="UnknownUser")||'$SYSTEM.Security.Check("xTafnit_RemoteSupport","USE") {
        do ..Audit("JoinDenied","helper="_$USERNAME_" ip="_..ClientIP())
        quit $$$ERROR($$$GeneralError,"denied")
    }
    quit ..DoJoin(pCode,$USERNAME,.pToken)
}

/// הצטרפות עוזר שמחובר ל-xTafnit (מסך TafnitCore.System.UI.App.Tools.Helper.HelperPage) - קוד בלבד.
/// pHelperName מגיע מהסשן של xTafnit (Environment.Security.UserCode), לא מהלקוח.
/// אם מוגדר xTafnitParams("BaseURLs",host,"helper","HELPERS") - רק המשתמשים שמופיעים בו
/// (שם כניסה באותיות גדולות: ("HELPERS","USERCODE")=1) רשאים.
ClassMethod JoinAs(pCode As %String, pHelperName As %String, Output pToken As %String) As %Status
{
    set pToken=""
    if $GET(pHelperName)="" quit $$$ERROR($$$GeneralError,"denied")
    set tHost=..Host()
    if tHost'="",$DATA(^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",tHost,"helper","HELPERS")),'$DATA(^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",tHost,"helper","HELPERS",$ZCONVERT(pHelperName,"U"))) {
        do ..Audit("JoinDenied","helper="_pHelperName_" ip="_..ClientIP())
        quit $$$ERROR($$$GeneralError,"denied")
    }
    quit ..DoJoin(pCode,pHelperName,.pToken)
}

/// הצטרפות עוזר עם קוד בלבד, בלי הזדהות (helper.html).
/// ההגנות: אישור המשתמש, תוקף הקוד, חסימה לפי IP אחרי MAXFAILS ניסיונות, ו-HELPERIPS.
/// לכיבוי לכתובת: s ^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",host,"helper","ANONYMOUSHELPER")=0
ClassMethod JoinAnonymous(pCode As %String, Output pToken As %String) As %Status
{
    set pToken=""
    if '..Param("ANONYMOUSHELPER") {
        do ..Audit("JoinDenied","helper=anonymous ip="_..ClientIP())
        quit $$$ERROR($$$GeneralError,"denied")
    }
    quit ..DoJoin(pCode,"anonymous@"_..ClientIP(),.pToken)
}

ClassMethod DoJoin(pCode As %String, pHelperName As %String, Output pToken As %String) As %Status [ Private ]
{
    set tSC=$$$OK, pToken=""
    try {
        set tIP=..ClientIP()
        set tKey=pHelperName_"|"_tIP
        if ..IsLocked(tKey) { set tSC=$$$ERROR($$$GeneralError,"locked") quit }

        if '..IPAllowed(tIP) {
            do ..Audit("JoinDeniedIP","helper="_pHelperName_" ip="_tIP)
            set tSC=$$$ERROR($$$GeneralError,"ip denied") quit
        }

        set tObj=..OpenByCode(pCode)
        if '$ISOBJECT(tObj)||(tObj.Status'="Pending") {
            do ..RegisterFail(tKey)
            do ..Audit("JoinFail","helper="_pHelperName_" ip="_tIP)
            set tSC=$$$ERROR($$$GeneralError,"invalid code") quit
        }
        if tObj.UserName=pHelperName { set tSC=$$$ERROR($$$GeneralError,"self") quit }
        if ..NowSec()>tObj.ExpiresSec {
            set tObj.Status="Expired" do tObj.%Save()
            do ..RegisterFail(tKey)
            set tSC=$$$ERROR($$$GeneralError,"expired") quit
        }
        
        set tToken=..NewToken()
        set tObj.Status="Active"
        set tObj.HelperName=pHelperName
        set tObj.HelperIP=tIP
        set tObj.HelperTokenHash=..Hash(tToken)
        set tObj.ExpiresSec=..NowSec()+..Param("MAXSESSION")
        $$$ThrowOnError(tObj.%Save())

        set ^IRIS.Temp.xTafnitRH("s",tObj.Code)=tObj.ExpiresSec
        kill ^IRIS.Temp.xTafnitRH("fail",tKey)

        do ..Enqueue(tObj.Code,"user",{"k":"m","t":"joined","helper":(pHelperName)}.%ToJSON())
        do ..Audit("Join","scope="_tObj.Scope_" user="_tObj.UserName_" helper="_pHelperName_" ip="_tIP)
        set pToken=tToken
    } catch ex {
        set tSC=ex.AsStatus()
    }
    quit tSC
}

ClassMethod SetControl(pCode As %String, pFlag As %Boolean) As %Status
{
    set tObj=..OpenByCode(pCode,1)
    if '$ISOBJECT(tObj) quit $$$OK
    set tObj.ControlGranted=''pFlag
    do ..Audit("Control",$SELECT(pFlag:"granted",1:"revoked")_" code="_pCode)
    quit tObj.%Save()
}

/// סגירה. pBy="system" ללא בדיקה; אחרת נדרש טוקן של אחד הצדדים.
ClassMethod CloseByCode(pCode As %String, pBy As %String = "system", pToken As %String = "") As %Status
{
    set tObj=..OpenByCode(pCode)
    if '$ISOBJECT(tObj) quit $$$OK
    
    if pBy'="system" {
        set pBy=tObj.RoleOf(pToken)
        if pBy="" quit $$$ERROR($$$GeneralError,"denied")
    }
    
    set tObj.Status="Closed"
    set tObj.ClosedAt=$ZDATETIME($ZTIMESTAMP,3,1,3)
    set tSC=tObj.%Save()
    
    set ^IRIS.Temp.xTafnitRH("closed",tObj.Code)=1
    set tBye={"k":"m","t":"bye","by":(pBy)}.%ToJSON()
    do ..Enqueue(tObj.Code,"user",tBye)
    do ..Enqueue(tObj.Code,"helper",tBye)
    do ..Audit("Close","by="_pBy_" user="_tObj.UserName_" helper="_tObj.HelperName)
    quit tSC
}

ClassMethod Enqueue(pCode As %String, pRole As %String, pMsg As %String)
{
    set n=$INCREMENT(^IRIS.Temp.xTafnitRH("seq",pCode))
    set ^IRIS.Temp.xTafnitRH("q",pCode,pRole,n)=pMsg
}

ClassMethod IsLocked(pKey As %String) As %Boolean
{
    set d=$GET(^IRIS.Temp.xTafnitRH("lock",pKey))
    quit (d'="")&&(d>..NowSec())
}

ClassMethod RegisterFail(pKey As %String)
{
    set n=$INCREMENT(^IRIS.Temp.xTafnitRH("fail",pKey))
    if n>=..Param("MAXFAILS") {
        set ^IRIS.Temp.xTafnitRH("lock",pKey)=..NowSec()+..Param("LOCKSECS")
        kill ^IRIS.Temp.xTafnitRH("fail",pKey)
    }
}

/// אודיט IRIS - יש להפעיל את אירועי xTafnit/RemoteHelp/* ב-Management Portal
ClassMethod Audit(pName As %String, pDetail As %String = "")
{
    try { do $SYSTEM.Security.Audit("xTafnit","RemoteHelp",pName,pDetail,"xTafnit remote help: "_pName) } catch {}
}

/// הנתונים נשמרים ב-IRISTEMP (^IRIS.Temp.*): הסשנים זמניים, ו-IRISTEMP פתוח לכתיבה ציבורית -
/// כך שאפליקציית ה-REST (משתמש אנונימי) צריכה רק הרשאת קריאה ל-DB של הקוד, בלי RW על נתוני xTafnit.
/// הסשנים נמחקים בהפעלה מחדש של IRIS.
Storage Default
{
<DataLocation>^IRIS.Temp.xTafnitRH.SessionD</DataLocation>
<IdLocation>^IRIS.Temp.xTafnitRH.SessionD</IdLocation>
<IndexLocation>^IRIS.Temp.xTafnitRH.SessionI</IndexLocation>
<StreamLocation>^IRIS.Temp.xTafnitRH.SessionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
