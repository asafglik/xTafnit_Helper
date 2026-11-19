/// REST API לעזרה מרחוק.
/// Web Application (למשל /xtafnit-rh): Dispatch Class = TafnitCore.System.UI.App.Tools.Helper.API
/// Allowed Authentication: Unauthenticated בלבד (ברירת המחדל של ההתקנה).
///   - Unauthenticated: כדי שהמשתמש במסך ה-login יוכל לבקש קוד
///   - Password (HTTP Basic בבקשת join) - רק אם הופעל במפורש: s ^TafnitHelper("BasicAuth")=1 והתקנה מחדש.
///     כבוי כברירת מחדל: אף מסך לא משתמש בו, והוא פותח נקודת ניחוש סיסמאות של IRIS.
/// Matching Roles: xTafnitRemoteHelp - קריאה בלבד ל-DB של הקוד (הסשנים ב-IRISTEMP)
Class TafnitCore.System.UI.App.Tools.Helper.API Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter UseSession = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/create" Method="POST" Call="Create"/>
  <Route Url="/join"   Method="POST" Call="Join"/>
  <Route Url="/close"  Method="POST" Call="Close"/>
</Routes>
}

/// הגנת CSRF: header מותאם שדפדפן לא שולח cross-site בלי preflight
ClassMethod OnPreHTTP() As %Boolean
{
    if $GET(%request.CgiEnvs("HTTP_X_RH"))'="1" {
        set %response.Status=..#HTTP403FORBIDDEN
        quit 0
    }
    quit 1
}

/// בקשת קוד (גם ממסך ה-login, ללא התחברות)
ClassMethod Create() As %Status
{
    set tOut={"ok":0}
    set tSC=##class(TafnitCore.System.UI.App.Tools.Helper.Session).Create(.tCode,.tToken,.tScope)
    if $$$ISOK(tSC) {
        set tOut.ok=1
        set tOut.code=tCode
        set tOut.token=tToken
        set tOut.scope=tScope
        set tOut.ttl=##class(TafnitCore.System.UI.App.Tools.Helper.Session).Param("CODETTL")
    } elseif $SYSTEM.Status.GetErrorText(tSC)["https required" {
        set %response.Status=..#HTTP403FORBIDDEN
        set tOut.msg="עזרה מרחוק זמינה רק בחיבור מאובטח (HTTPS)"
    } else {
        set %response.Status="429 Too Many Requests"
        set tOut.msg="לא ניתן ליצור קוד כרגע, נסה שוב בעוד כמה דקות"
    }
    write tOut.%ToJSON()
    quit $$$OK
}

/// הצטרפות עוזר: עם HTTP Basic (משאב xTafnit_RemoteSupport), או בלי הזדהות - קוד בלבד (helper.html)
ClassMethod Join() As %Status
{
    set tOut={"ok":0}
    try {
        set tIn=##class(%DynamicAbstractObject).%FromJSON(%request.Content)
        if $USERNAME="UnknownUser" {
            set tSC=##class(TafnitCore.System.UI.App.Tools.Helper.Session).JoinAnonymous(tIn.code,.tToken)
        } else {
            set tSC=##class(TafnitCore.System.UI.App.Tools.Helper.Session).Join(tIn.code,.tToken)
        }
        if $$$ISOK(tSC) {
            set tOut.ok=1
            set tOut.token=tToken
        } else {
            set %response.Status=..#HTTP403FORBIDDEN
            set tOut.msg="קוד שגוי, שפג תוקפו, או שאין הרשאה"
        }
    } catch ex {
        set %response.Status=..#HTTP400BADREQUEST
        set tOut.msg="בקשה לא תקינה"
    }
    write tOut.%ToJSON()
    quit $$$OK
}

/// סיום (כל צד עם הטוקן שלו)
ClassMethod Close() As %Status
{
    set tOut={"ok":0}
    try {
        set tIn=##class(%DynamicAbstractObject).%FromJSON(%request.Content)
        set tSC=##class(TafnitCore.System.UI.App.Tools.Helper.Session).CloseByCode(tIn.code,"token",tIn.token)
        if $$$ISOK(tSC) set tOut.ok=1
    } catch ex {
        set tOut.msg="בקשה לא תקינה"
    }
    write tOut.%ToJSON()
    quit $$$OK
}

}
