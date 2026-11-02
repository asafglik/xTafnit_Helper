# xTafnit_Helper – עזרה מרחוק ל-xTafnit

המשתמש לוחץ על כפתור צף ומקבל קוד בן 6 ספרות. איש התמיכה מזין את הקוד, ואחרי אישור המשתמש רואה את המסך שלו ויכול לשלוט בו. עובד ב-HTTP וב-HTTPS.

## התקנה

בטרמינל של IRIS, ב-namespace של xTafnit, עם משתמש בעל `%Admin_Secure` ו-`%System_CallOut`:

```
zn "MATRIXSYS"
do $system.OBJ.LoadDir("C:\gitRepository\xTafnit_Helper\src","ck",,1)
```

בסוף הקומפילציה ההתקנה המלאה רצה **ברקע** בלי פרמטרים (`TafnitCore.System.UI.App.Tools.Helper.Install`):
IIS (handlers, ‏CSPms, ‏WebSocket Protocol), ‏Web Application ‏`/xtafnit-rh`, קומפילציה, קבצי הווב, ובדיקת חיבור.

- הלוג: `zw ^TafnitHelper("InstallLog")`, ושורה ב-`messages.log`.
- הרצה ידנית: `do install^core.TafnitHelperUtils()`
- ביטול ההפעלה האוטומטית: `set ^TafnitHelper("AutoInstall")=0`

## הפעלת הכפתור למסכים

הכפתור מוצג רק במסכים ובכתובות שהוגדרו (`{host}` = ‏`SERVER_NAME`, אותה שורה ל-HTTP ול-HTTPS):

```
set ^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs","erp.example.co.il","helper","TafnitCore.System.UI.App.Login")=1
```

## פרמטרים לכל כתובת

כל הפרמטרים נמצאים תחת `^["TAFNIT_PARAMETERS"]xTafnitParams("BaseURLs",{host},"helper",{PARAMETER})`. בלי הגדרה – ברירת המחדל של `Session`.

| פרמטר | ברירת מחדל | משמעות |
| --- | --- | --- |
| `HELPERIPS` | ריק = כל IP | כתובות/קידומות IP מורשות לעוזר, מופרדות בפסיק (`10.0.5.`) |
| `ANONYMOUSHELPER` | 1 | 0 = כיבוי הצטרפות עם קוד בלבד (`helper.html`) |
| `HELPERS`,{USERCODE} | לא מוגדר = כל משתמש מחובר | רשימת עוזרים מורשים ב-`HelperPage` |
| `TRUSTPROXY` | 0 | 1 = כתובת הלקוח מ-`X-Forwarded-For` (רק מאחורי proxy אמין) |
| `CODETTL` | 600 | תוקף הקוד בשניות |
| `MAXSESSION` | 3600 | משך סשן פעיל בשניות |
| `MAXFAILS` / `LOCKSECS` | 5 / 900 | ניסיונות שגויים עד חסימה / משך החסימה |
| `MAXCREATES` | 5 | קודים מאותו IP ב-10 דקות |
| `LOGINPOLICY` | `reconsent` | אחרי כניסה למערכת: `reconsent` / `end` / `continue` |

## מבנה

| נתיב | תוכן |
| --- | --- |
| `src/` | המחלקות `TafnitCore.System.UI.App.Tools.Helper.*`, הרוטינה `core.TafnitHelperUtils`, ו-`commonXTafPage` (מחלקת ליבה – הכפתור הצף) |
| `web/` | `xtafnit-rh.js`, ‏`helper.html` (UTF-8 עם BOM) |
| `tools/build-webfiles.ps1` | מייצר את `src/...WebFiles.cls` מתוך `web/` – להריץ אחרי כל שינוי ב-`web/` |

## מסכים

- **משתמש:** הכפתור הצף בכל מסך שיורש מ-`commonXTafPage` ומופעל בפרמטרים.
- **עוזר מחובר:** `xpage.csp?eTafnitClass=TafnitCore.System.UI.App.Tools.Helper.HelperPage` – קוד בלבד.
- **עוזר עצמאי:** `/xtafnit/helper.html` – קוד בלבד.
