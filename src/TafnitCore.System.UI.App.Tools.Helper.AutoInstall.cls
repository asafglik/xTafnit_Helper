/// Projection: אחרי קומפילציה של TafnitCore.System.UI.App.Tools.Helper.Install מפעיל ברקע את ההתקנה המלאה.
/// לא מפעיל אם התקנה כבר רצה (ההתקנה עצמה מקמפלת את החבילה).
/// לביטול ההפעלה האוטומטית: s ^TafnitHelper("AutoInstall")=0
Class TafnitCore.System.UI.App.Tools.Helper.AutoInstall Extends %Projection.AbstractProjection
{

ClassMethod CreateProjection(cls As %String, ByRef params) As %Status
{
    if '$GET(^TafnitHelper("AutoInstall"),1) quit $$$OK
    if ##class(TafnitCore.System.UI.App.Tools.Helper.Install).IsRunning() quit $$$OK
    job ##class(TafnitCore.System.UI.App.Tools.Helper.Install).Background()
    quit $$$OK
}

}
