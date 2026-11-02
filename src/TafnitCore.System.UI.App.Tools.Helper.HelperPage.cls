/// מסך העוזר לעזרה מרחוק, כמסך xTafnit.
/// העוזר כבר מחובר ל-xTafnit, ולכן מזין רק את הקוד שקיבל מהמשתמש (בלי שם משתמש וסיסמה).
/// הזיהוי בשרת לפי Environment.Security.UserCode - ראה TafnitCore.System.UI.App.Tools.Helper.Session.JoinAs.
/// פתיחה: xpage.csp?eTafnitClass=TafnitCore.System.UI.App.Tools.Helper.HelperPage (אחרי כניסה למערכת), או מהתפריט.
Class TafnitCore.System.UI.App.Tools.Helper.HelperPage Extends TafnitCore.System.UI.App.commonXTafPage
{

XData eTafnitWebApplication [ XMLNamespace = "http://www.tafnitERP.co.il/xTafnit/V1.1" ]
{
<page Title="עזרה מרחוק - עוזר" >
	<body>
	<row>
	<col BootstrapClass="flex flex-wrap items-end gap-3">
	<textbox Name="tbRhCode" Caption="קוד מהמשתמש" MaxSize="6" Size="6" Direction="LTR" AutoFocus="true" />
	<button Name="btnRhJoin" Caption="התחבר" iconClass="fas fa-plug" onClick="JoinOnClick" />
	</col>
	</row>
	<row>
	<col>
	<freeHandHTML Name="fhRhScreen" NoCaption="true" />
	</col>
	</row>
	</body>
</page>
}

Method onPrepage() As %Status
{
	d ##super()

	// סטטוס, כפתור סיום ואזור התצוגה - HTML רגיל שמנוהל ע"י xtafnit-rh.js
	s html = ##class(%GlobalCharacterStream).%New()
	d html.Write("<div class='flex items-center gap-3 my-2'>")
	d html.Write("<span id='xrhHelperStatus'>הקלד את הקוד בן 6 הספרות שמופיע אצל המשתמש</span>")
	d html.Write("<button type='button' id='xrhHelperStop' class='k-button x-button x-button-secondary' data-rh-ignore='1' style='display:none'>סיים</button>")
	d html.Write("</div>")
	d html.Write("<div id='xrhHelperScreen' style='height:75vh;border:1px solid #d1d5db;border-radius:8px;overflow:hidden'></div>")
	s ..GetControl("fhRhScreen").htmlContent = html

	q $$$OK
}

Method JoinOnClick(e As TafnitCore.System.UI.components.Events.onClickEventArgs = "")
{
	s code = $ZSTRIP(..GetControl("tbRhCode").Value, "*W")
	i code'?6N
	{
		d ..MessageBox(0, "עזרה מרחוק", "יש להקליד 6 ספרות")
		q $$$OK
	}
	// UserCode = שם הכניסה (Username הוא שם התצוגה). המסך עצמו נפתח רק אחרי כניסה למערכת (Environment.Open).
	s helper = ..Environment.Security.UserCode
	i helper = ""
	{
		d ..MessageBox(0, "עזרה מרחוק", "יש להיכנס למערכת (LoggedIn="_..Environment.Security.LoggedIn_", Username="_..Environment.Security.Username_")")
		q $$$OK
	}

	s status = ##class(TafnitCore.System.UI.App.Tools.Helper.Session).JoinAs(code, helper, .token)
	i $$$ISERR(status)
	{
		d ..MessageBox(0, "עזרה מרחוק", "קוד שגוי, שפג תוקפו, או שאין הרשאה")
		q $$$OK
	}

	d ..Environment.ClientCommands.Add(..AttachScript(code, token))
	q $$$OK
}

/// מחבר את המסך לסשן עם הטוקן שהתקבל בשרת (טוען את xtafnit-rh.js אם צריך)
Method AttachScript(code As %String, token As %String) As %String
{
	q "(function (c, t) {"
	 _"  var go = function () {"
	 _"    var host = document.getElementById('xrhHelperScreen'), st = document.getElementById('xrhHelperStatus'), stop = document.getElementById('xrhHelperStop');"
	 _"    var show = function (s, m) { st.textContent = m || ''; st.style.color = (s === 'error') ? '#dc2626' : ((s === 'live' || s === 'control' || s === 'view') ? '#16a34a' : ''); if (s === 'closed') stop.style.display = 'none'; };"
	 _"    stop.onclick = function () { XRH.helper.stop(); stop.style.display = 'none'; host.innerHTML = ''; show('', 'הסשן הסתיים'); };"
	 _"    stop.style.display = '';"
	 _"    XRH.helper.attach(c, t, host, show);"
	 _"  };"
	 _"  if (window.XRH) go(); else loadScript('scripts/xtafnit-rh.js', go);"
	 _"})('"_code_"', '"_token_"');"
}

}
