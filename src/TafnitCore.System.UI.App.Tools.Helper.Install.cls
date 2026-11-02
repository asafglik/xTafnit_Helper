/// התקנה אוטומטית של עזרה מרחוק xTafnit.
/// כשהחבילה נטענת ומקומפלת (למשל $SYSTEM.OBJ.LoadDir של תיקיית src), ה-Projection AutoInstall
/// מפעיל ברקע את install^core.TafnitHelperUtils בלי פרמטרים: IIS, Web Applications, קומפילציה,
/// קבצי הווב (מתוך WebFiles), WebSocket וחיבור. את המסכים שבהם יוצג הכפתור מגדירים בנפרד:
///   s ^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",{host},"helper",{class})=1
/// הלוג נשמר ב-^TafnitHelper("InstallLog",n) ונרשם שורה ב-messages.log.
Class TafnitCore.System.UI.App.Tools.Helper.Install [ Abstract, DependsOn = TafnitCore.System.UI.App.Tools.Helper.AutoInstall ]
{

Projection AutoInstall As TafnitCore.System.UI.App.Tools.Helper.AutoInstall;

/// ההתקנה ברקע (JOB). מחכה שכל רכיבי החבילה יקומפלו ואז מריץ את ההתקנה המלאה.
ClassMethod Background()
{
    // החבילה נטענת כולה ורק אז מקומפלת - מחכים עד שהרכיבים זמינים (עד 2 דקות)
    hang 3
    for i=1:1:120 {
        quit:..Ready()
        hang 1
    }
    if '..Ready() {
        do ..Record("[x] Package components are not compiled - install skipped. Run: do install^core.TafnitHelperUtils()")
        quit
    }
    set tLog=$$runLog^core.TafnitHelperUtils()
    do ..Record(tLog)
}

/// כל הרכיבים מקומפלים: הרוטינה, מחלקות החבילה, וכפתור הצף ב-commonXTafPage
ClassMethod Ready() As %Boolean
{
    if $TEXT(^core.TafnitHelperUtils)="" quit 0
    set tOK=1
    for tCls="Session","Relay","API","HelperPage","WebFiles" {
        if '##class(%Dictionary.CompiledClass).%ExistsId("TafnitCore.System.UI.App.Tools.Helper."_tCls) { set tOK=0 quit }
    }
    if 'tOK quit 0
    quit ##class(%Dictionary.CompiledMethod).%ExistsId("TafnitCore.System.UI.App.commonXTafPage||AddRemoteHelpButton")
}

/// שומר את הלוג ומודיע ב-messages.log
ClassMethod Record(pText As %String)
{
    set n=$INCREMENT(^TafnitHelper("InstallLog"))
    set ^TafnitHelper("InstallLog",n)=$ZDATETIME($HOROLOG,3)_$CHAR(13,10)_pText
    set tOK=($EXTRACT(pText,*-8,*)="[v] Done.")
    try {
        do ##class(%SYS.System).WriteToConsoleLog("xTafnit Helper install "_$SELECT(tOK:"completed",1:"finished with problems")_" - see ^TafnitHelper(""InstallLog"","_n_") in "_$NAMESPACE,0,$SELECT(tOK:0,1:1))
    } catch {}
}

/// האם התקנה רצה כרגע (מונע הפעלה כפולה כשההתקנה עצמה מקמפלת את החבילה)
ClassMethod IsRunning() As %Boolean
{
    set tJob=$GET(^IRIS.Temp.TafnitHelper("installing"))
    quit (tJob'="")&&$DATA(^$JOB(tJob))
}

}
