/// התקנה אוטומטית של עזרה מרחוק xTafnit.
/// כשהחבילה נטענת ומקומפלת (למשל $SYSTEM.OBJ.LoadDir של תיקיית src), ה-Projection AutoInstall
/// מפעיל ברקע את install^core.TafnitHelperUtils בלי פרמטרים: IIS, Web Applications, קומפילציה,
/// קבצי הווב (מתוך WebFiles), WebSocket וחיבור. את המסכים שבהם יוצג הכפתור מגדירים בנפרד:
///   s ^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",{host},"helper",{class})=1
/// הלוג נשמר ב-^TafnitHelper("InstallLog",n) ונרשם שורה ב-messages.log.
Class TafnitCore.System.UI.App.Tools.Helper.Install [ Abstract, DependsOn = TafnitCore.System.UI.App.Tools.Helper.AutoInstall ]
{

Projection AutoInstall As TafnitCore.System.UI.App.Tools.Helper.AutoInstall;

/// חייב להיות שווה ל-$$version^core.TafnitHelperUtils() - כך ההתקנה ברקע לא תרוץ על גרסה ישנה של הרוטינה
/// שעוד נמצאת ב-IRIS בזמן ש-LoadDir מקמפל את החדשה
Parameter VERSION = 2;

/// ההתקנה ברקע (JOB). מחכה שכל רכיבי החבילה יקומפלו ואז מריץ את ההתקנה המלאה.
ClassMethod Background()
{
    // החבילה נטענת כולה ורק אז מקומפלת - מחכים עד שהרכיבים זמינים (עד 2 דקות)
    hang 3
    set tDeployed=0
    for i=1:1:120 {
        quit:..Ready(.tWhy)
        // LoadDir לא תמיד טוען את ה-.mac: אם הרוטינה חסרה או ישנה - כותבים אותה מהעותק שב-WebFiles
        if 'tDeployed,tWhy["core.TafnitHelperUtils version",##class(%Dictionary.CompiledClass).%ExistsId("TafnitCore.System.UI.App.Tools.Helper.WebFiles") {
            set tDeployed=1
            set tSC=##class(TafnitCore.System.UI.App.Tools.Helper.WebFiles).DeployRoutine()
            if $$$ISERR(tSC) do ..Record("[x] core.TafnitHelperUtils from WebFiles: "_$SYSTEM.Status.GetErrorText(tSC))
        }
        hang 1
    }
    if '..Ready(.tWhy) {
        do ..Record("[x] Package not ready ("_tWhy_") - install skipped. Run: do install^core.TafnitHelperUtils()")
        quit
    }
    set tLog=$$runLog^core.TafnitHelperUtils()
    do ..Record(tLog)
}

/// כל הרכיבים מקומפלים: הרוטינה, מחלקות החבילה, וכפתור הצף ב-commonXTafPage
/// pWhy = מה עוד לא מוכן
ClassMethod Ready(Output pWhy As %String) As %Boolean
{
    set pWhy=""
    // הרוטינה מקומפלת בגרסה של החבילה (ולא גרסה ישנה מהתקנה קודמת)
    set tVersion="", tErr=""
    try { set tVersion=$$version^core.TafnitHelperUtils() } catch tEx { set tErr=tEx.Name }
    if tVersion'=..#VERSION {
        set pWhy="core.TafnitHelperUtils version "_$SELECT(tErr'="":tErr,tVersion="":"missing",1:tVersion)_", expected "_..#VERSION
        quit 0
    }
    for tCls="Session","Relay","API","HelperPage","WebFiles" {
        if '##class(%Dictionary.CompiledClass).%ExistsId("TafnitCore.System.UI.App.Tools.Helper."_tCls) { set pWhy=pWhy_$SELECT(pWhy'="":", ",1:"")_tCls_" not compiled" }
    }
    if pWhy'="" quit 0
    if '##class(%Dictionary.CompiledMethod).%ExistsId("TafnitCore.System.UI.App.commonXTafPage||AddRemoteHelpButton") {
        set pWhy="commonXTafPage has no AddRemoteHelpButton"
        quit 0
    }
    quit 1
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
