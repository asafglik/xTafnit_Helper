/* xtafnit-rh.js — עזרה מרחוק ל-xTafnit
 *
 * צד משתמש:  XRH.user.start()            → מציג קוד 6 ספרות, מחכה לעוזר, מבקש אישור
 * צד עוזר:   XRH.helper.start(code, el)  → מצטרף, מציג את המסך של המשתמש ושולח קלט
 *
 * הטכניקה: שיקוף DOM (תמונת מצב דחוסה בכל שינוי) + שידור חוזר של אירועי עכבר/מקלדת.
 * אפשר להגדיר נתיבים עם window.XRH_CONFIG לפני הטעינה.
 */
(function (w) {
  'use strict';

  const CFG = Object.assign({
    api: '/xtafnit-rh',                                  // Web App של ה-REST
    ws: '/xtafnit/TafnitCore.System.UI.App.Tools.Helper.Relay.cls',         // Web App של ה-WebSocket
    snapDelay: 350,                                      // debounce לתמונת מצב (ms)
    chunk: 16000,                                        // גודל frame (תווי base64)
    frameDepth: 3,                                       // כמה רמות של iframe (מאותו origin) משוקפות - למשל pdfViewer
    canvasQuality: 0.7,                                  // איכות JPEG של canvas משוקף (עמודי PDF)
    // כפתור "עזרה מרחוק" - נתפס בדפדפן, ללא תלות בפריימוורק (Name="btnRemoteHelp" במסך ה-Login)
    startSelector: '[id*="btnRemoteHelp"],[name*="btnRemoteHelp"],[data-xrh-start]'
  }, w.XRH_CONFIG || {});

  /* ───────────── כלים משותפים ───────────── */

  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const post = (path, body, extra) => fetch(CFG.api + path, {
    method: 'POST', credentials: 'same-origin',
    headers: Object.assign({ 'Content-Type': 'application/json', 'X-RH': '1' }, extra || {}),
    body: JSON.stringify(body || {})
  }).then(r => r.json().catch(() => ({})).then(j => Object.assign({ http: r.status }, j)));

  // הקוד והטוקן לא נכנסים לכתובת (שנרשמת בלוגים של IIS) - הם נשלחים בהודעה הראשונה על הסוקט
  const wsUrl = () => (location.protocol === 'https:' ? 'wss:' : 'ws:') + '//' + location.host + CFG.ws;
  const wsAuth = (ws, code, token) => ws.send(JSON.stringify({ k: 'auth', code: code, t: token }));

  function b64(u8) { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); }
  const BLANK = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

  /** חיפוש אלמנט לפי data-rhid במסמך ובכל ה-iframes מאותו origin שבתוכו */
  function findById(doc, id, depth) {
    const e = doc.querySelector('[data-rhid="' + id + '"]'); if (e) return e;
    if (depth >= CFG.frameDepth) return null;
    for (const f of doc.querySelectorAll('iframe,frame')) {
      let d = null; try { d = f.contentDocument; } catch (_) { }
      const r = d && d.documentElement ? findById(d, id, depth + 1) : null; if (r) return r;
    }
    return null;
  }

  function unb64(b) { const s = atob(b), u = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i); return u; }
  async function pipe(u8, stream) { const wr = stream.writable.getWriter(); wr.write(u8); wr.close(); return new Uint8Array(await new Response(stream.readable).arrayBuffer()); }

  async function pack(obj) {
    let u = new TextEncoder().encode(JSON.stringify(obj)), z = 0;
    if (w.CompressionStream) { u = await pipe(u, new CompressionStream('gzip')); z = 1; }
    return { z, b: b64(u) };
  }
  async function unpack(z, b) {
    let u = unb64(b);
    if (z) u = await pipe(u, new DecompressionStream('gzip'));
    return JSON.parse(new TextDecoder().decode(u));
  }

  /** שולח הודעה גדולה כסדרת frames: {"k":"c",id,i,n,z,d}  (ה-"k":"c" חייב להיות ראשון - השרת מזהה לפי זה) */
  async function sendBig(ws, state, obj) {
    const { z, b } = await pack(obj), id = ++state.mid, n = Math.max(1, Math.ceil(b.length / CFG.chunk));
    for (let i = 0; i < n; i++) ws.send(JSON.stringify({ k: 'c', id, i, n, z, d: b.substr(i * CFG.chunk, CFG.chunk) }));
  }

  /** הרכבת frames חזרה להודעה */
  function assembler(onMsg) {
    const buf = {};
    return async f => {
      const e = buf[f.id] || (buf[f.id] = { n: f.n, p: [], c: 0, z: f.z });
      if (e.p[f.i] === undefined) { e.p[f.i] = f.d; e.c++; }
      for (const k in buf) if (+k < f.id - 3) delete buf[k];
      if (e.c === e.n) { delete buf[f.id]; onMsg(await unpack(e.z, e.p.join(''))); }
    };
  }

  function injectCss() {
    if (document.getElementById('xrh-css')) return;
    const s = document.createElement('style'); s.id = 'xrh-css'; s.setAttribute('data-rh-ignore', '');
    s.textContent = `
.xrh-bar{position:fixed;left:16px;bottom:16px;z-index:2147483646;direction:rtl;font:14px/1.4 system-ui,Arial,sans-serif;background:#1f2937;color:#fff;border-radius:12px;padding:12px 16px;box-shadow:0 8px 30px rgba(0,0,0,.35);display:flex;gap:14px;align-items:center}
.xrh-code{font:700 28px/1 ui-monospace,Consolas,monospace;letter-spacing:6px;direction:ltr;background:#111827;padding:8px 12px;border-radius:8px}
.xrh-bar button,.xrh-card button{font:inherit;border:0;border-radius:8px;padding:8px 12px;cursor:pointer;background:#374151;color:#fff}
.xrh-bar button.xrh-end{background:#b91c1c}
.xrh-modal{position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;direction:rtl;font:15px system-ui,Arial,sans-serif}
.xrh-card{background:#fff;color:#111;border-radius:14px;padding:22px 26px;max-width:380px;display:flex;flex-direction:column;gap:10px}
.xrh-card button{background:#2563eb}.xrh-card button[data-a=no]{background:#6b7280}
.xrh-cursor{position:fixed;z-index:2147483645;width:18px;height:18px;border-radius:50%;background:rgba(234,88,12,.85);border:2px solid #fff;pointer-events:none;transform:translate(-50%,-50%);display:none}`;
    document.head.appendChild(s);
  }

  function mk(tag, cls) { const e = document.createElement(tag); e.className = cls; e.setAttribute('data-rh-ignore', ''); document.body.appendChild(e); return e; }

  /* ═════════════════════════ צד משתמש ═════════════════════════ */

  const U = {
    code: null, token: null, scope: 'app', loginPath: null, pendingLogin: false, sawPw: false, lw: null, lwT: null,
    ws: null, consent: false, control: false,
    tag: 0, seq: 0, st: { mid: 0 }, last: '', timer: null, obs: null, bar: null, cur: null, fails: 0,

    async start() {
      if (this.code) return;
      const r = await post('/create');
      if (!r.ok) { alert(r.msg || 'שגיאה ביצירת קוד'); return; }
      this.code = r.code; this.token = r.token; this.consent = false;
      this.scope = r.scope || 'app'; this.loginPath = (this.scope === 'login') ? location.pathname : null; this.control = false; this.persist();
      this.ui(); this.setStatus('ממתין לעוזר… (תוקף ' + Math.round(r.ttl / 60) + ' דקות)'); this.connect();
      this.watchLogin();
    },

    /* חידוש אוטומטי אחרי מעבר דף */
    resume() {
      try {
        const s = JSON.parse(sessionStorage.getItem('xrh') || 'null'); if (!s) return;
        Object.assign(this, { code: s.code, token: s.token, consent: s.consent, control: s.control, scope: s.scope || 'app', loginPath: s.loginPath || null, pendingLogin: !!s.pendingLogin });
        // יצאנו ממסך ה-login (כניסה הצליחה) - לא משדרים כלום עד שהשרת מחליט לפי המדיניות
        if (this.scope === 'login' && this.loginPath && location.pathname !== this.loginPath) {
          this.pendingLogin = true; this.consent = false; this.control = false;
        }
        if (!this.pendingLogin) this.watchLogin();
        this.ui(); this.setStatus(this.consent ? 'עזרה מרחוק פעילה' : 'ממתין לעוזר…'); this.connect();
      } catch (e) { sessionStorage.removeItem('xrh'); }
    },

    persist() {
      sessionStorage.setItem('xrh', JSON.stringify({ code: this.code, token: this.token, consent: this.consent, control: this.control, scope: this.scope, loginPath: this.loginPath, pendingLogin: this.pendingLogin }));
    },
    loginHandled() { this.pendingLogin = false; this.scope = 'app'; this.loginPath = null; this.unwatchLogin(); this.persist(); },

    /* ─── זיהוי כניסה למערכת ───
       עובד גם כשהפריימוורק מחליף מסך בלי לשנות URL (GoToHomepage):
       ראינו שדה סיסמה במסך הנוכחי, והוא נעלם → הכניסה הצליחה.
       כניסה שנכשלה משאירה את שדה הסיסמה, ולכן לא נחשבת. */
    hasPw() { return !!document.querySelector('input[type="password"]'); },
    checkLogin() {
      if (this.scope !== 'login' || this.pendingLogin) return false;
      if (this.hasPw()) { this.sawPw = true; return false; }
      if (!this.sawPw) return false;
      this.onLogin(); return true;
    },
    onLogin() {
      this.pendingLogin = true; this.consent = false; this.control = false;
      this.persist(); this.refreshUi(); this.setStatus('נכנסת למערכת…');
      this.send({ k: 'm', t: 'login-done' });
    },
    watchLogin() {
      if (this.lw || this.scope !== 'login') return;
      this.sawPw = this.hasPw();
      this.lw = new MutationObserver(() => { clearTimeout(this.lwT); this.lwT = setTimeout(() => this.checkLogin(), 150); });
      this.lw.observe(document.documentElement, { childList: true, subtree: true });
    },
    unwatchLogin() { if (this.lw) { this.lw.disconnect(); this.lw = null; } clearTimeout(this.lwT); },

    connect() {
      const ws = this.ws = new WebSocket(wsUrl()); let opened = false;
      ws.onopen = () => {
        wsAuth(ws, this.code, this.token);
        opened = true; this.fails = 0;
        if (this.pendingLogin) { this.setStatus('נכנסת למערכת…'); this.send({ k: 'm', t: 'login-done' }); return; }
        if (this.consent) { this.bind(); this.snap(true); }
      };
      ws.onmessage = e => { try { this.onMsg(JSON.parse(e.data)); } catch (_) { } };
      ws.onclose = () => {
        if (!this.code || ws !== this.ws) return;
        if (!opened && ++this.fails >= 3) return this.end();
        setTimeout(() => this.code && this.connect(), 2000);
      };
    },

    send(o) { if (this.ws && this.ws.readyState === 1) this.ws.send(JSON.stringify(o)); },

    onMsg(m) {
      if (m.k !== 'm') return;
      switch (m.t) {
        case 'denied': this.end(); break;          // השרת דחה את האימות (סשן שפג / טוקן שגוי)
        case 'joined': this.ask(m.helper); break;
        case 'need-snap': if (this.consent) this.snap(true); break;
        case 'evt': this.apply(m); break;
        case 'helper-left': this.setStatus('העוזר התנתק'); break;
        case 'reconsent':                          // אחרי כניסה למערכת - אישור מחדש
          this.loginHandled(); this.consent = false; this.control = false; this.persist(); this.refreshUi();
          this.setStatus('נכנסת למערכת - העוזר מחכה לאישור שלך'); this.ask(m.helper, true); break;
        case 'resume-ok':                          // המדיניות: להמשיך
          this.loginHandled(); this.consent = true; this.control = !!m.control; this.persist();
          this.bind(); this.snap(true); this.refreshUi(); break;
        case 'bye': this.end(); break;
      }
    },

    /* חלון אישור: הצופה לא רואה כלום עד שהמשתמש מאשר */
    ask(helper, afterLogin) {
      document.querySelectorAll('.xrh-modal').forEach(e => e.remove());
      const box = mk('div', 'xrh-modal');
      const txt = afterLogin
        ? 'נכנסת למערכת. האם להמשיך לאפשר ל-<b>' + esc(helper) + '</b> לראות את המסך שלך?'
        : '<b>' + esc(helper) + '</b> מבקש/ת לעזור לך מרחוק.';
      box.innerHTML = '<div class="xrh-card"><div>' + txt + '</div>' +
        '<button data-a="view">צפייה בלבד</button><button data-a="ctl">צפייה ושליטה</button><button data-a="no">דחה</button></div>';
      box.onclick = e => {
        const a = e.target.getAttribute && e.target.getAttribute('data-a'); if (!a) return;
        box.remove();
        if (a === 'no') return this.stop();
        this.consent = true; this.control = (a === 'ctl'); this.persist();
        this.send({ k: 'm', t: 'grant', control: this.control });
        this.bind(); this.snap(true); this.refreshUi();
      };
    },

    ui() {
      if (this.bar) return; injectCss();
      const b = this.bar = mk('div', 'xrh-bar');
      b.innerHTML = '<div><div style="opacity:.7;font-size:12px">קוד עזרה מרחוק</div><div class="xrh-code">' + esc(this.code) + '</div></div>' +
        '<div class="xrh-st"></div><button class="xrh-ctl" style="display:none">בטל שליטה</button><button class="xrh-end">סיים</button>';
      b.querySelector('.xrh-end').onclick = () => this.stop();
      b.querySelector('.xrh-ctl').onclick = () => { this.control = false; this.persist(); this.send({ k: 'm', t: 'grant', control: false }); this.refreshUi(); };
      this.refreshUi();
    },
    refreshUi() {
      if (!this.bar) return;
      this.bar.querySelector('.xrh-ctl').style.display = (this.consent && this.control) ? '' : 'none';
      if (this.consent) this.setStatus(this.control ? 'העוזר צופה ושולט' : 'העוזר צופה (ללא שליטה)');
    },
    setStatus(t) { if (this.bar) this.bar.querySelector('.xrh-st').textContent = t; },

    stop() { post('/close', { code: this.code, token: this.token }).catch(() => { }); this.end(); },

    end() {
      this.code = null; this.token = null; this.unwatchLogin(); this.pendingLogin = false;
      try { this.ws && this.ws.close(); } catch (_) { }
      if (this.obs) { this.obs.disconnect(); this.obs = null; ['input', 'change', 'scroll', 'resize'].forEach(t => removeEventListener(t, this.onUi, true)); }
      clearTimeout(this.timer); this.timer = null;
      [this.bar, this.cur].forEach(e => e && e.remove()); this.bar = this.cur = null;
      document.querySelectorAll('.xrh-modal').forEach(e => e.remove());
      sessionStorage.removeItem('xrh');
    },

    /* ─── שיקוף ─── */
    bind() {
      if (this.obs) return;
      const ign = n => { const el = n.nodeType === 1 ? n : n.parentElement; return el && el.closest && el.closest('[data-rh-ignore]'); };
      this.obs = new MutationObserver(rs => {
        if (rs.some(r => !(r.type === 'attributes' && r.attributeName === 'data-rhid') && !ign(r.target))) this.sched();
      });
      this.obs.observe(document.documentElement, { childList: true, subtree: true, attributes: true, characterData: true });
      this.onUi = () => this.sched();
      ['input', 'change', 'scroll', 'resize'].forEach(t => addEventListener(t, this.onUi, true));
    },

    sched() { if (this.timer || !this.consent) return; this.timer = setTimeout(() => { this.timer = null; this.snap(); }, CFG.snapDelay); },

    async snap(force) {
      if (this.checkLogin()) return;                  // בדיקה סינכרונית - אין מרוץ מול זיהוי הכניסה
      if (!this.consent || !this.ws || this.ws.readyState !== 1) return;
      const sc = [];
      const html = '<!DOCTYPE html>' + this.serialize(document, 0, sc);
      this.watchFrames(document, 0);
      // גם גלילה בלבד (בדף או בתוך iframe) היא שינוי שצריך לשלוח
      const key = html + '|' + scrollX + ',' + scrollY + '|' + JSON.stringify(sc);
      if (!force && key === this.last) return; this.last = key;

      sendBig(this.ws, this.st, {
        t: 'snap', seq: ++this.seq, html, base: document.baseURI, title: document.title,
        vw: innerWidth, vh: innerHeight, sx: scrollX, sy: scrollY, sc
      });
    },

    /** עותק של מסמך (ושל ה-iframes מאותו origin שבתוכו, עד FRAMEDEPTH רמות) כ-HTML.
     *  sc = מיקומי גלילה מכל המסמכים (data-rhid ייחודי לכל המסמכים - מונה משותף) */
    serialize(doc, depth, sc) {
      const root = doc.documentElement, keep = e => !e.closest('[data-rh-ignore]');
      const all = [root, ...root.querySelectorAll('*')];
      all.forEach(e => { if (!e.hasAttribute('data-rhid')) e.setAttribute('data-rhid', ++this.tag); });
      all.forEach(e => { if ((e.scrollTop || e.scrollLeft) && keep(e)) sc.push({ id: +e.getAttribute('data-rhid'), t: e.scrollTop, l: e.scrollLeft }); });

      const clone = root.cloneNode(true);
      clone.querySelectorAll('[data-rh-ignore]').forEach(e => e.remove());

      // מצב טפסים (value לא מופיע ב-outerHTML)
      const live = [...root.querySelectorAll('input,textarea,select')].filter(keep);
      const copy = clone.querySelectorAll('input,textarea,select');
      live.forEach((el, i) => {
        const c = copy[i]; if (!c) return; const t = (el.type || '').toLowerCase();
        if (t === 'password' || el.closest('[data-rh-mask]')) { c.setAttribute('value', ''); return; }   // סיסמאות לא נשלחות לעולם
        if (el.tagName === 'TEXTAREA') c.textContent = el.value;
        else if (el.tagName === 'SELECT') [...c.options].forEach((o, j) => el.options[j].selected ? o.setAttribute('selected', '') : o.removeAttribute('selected'));
        else if (t === 'checkbox' || t === 'radio') el.checked ? c.setAttribute('checked', '') : c.removeAttribute('checked');
        else c.setAttribute('value', el.value);
      });

      // canvas (למשל עמודי PDF ב-pdfViewer) - כתמונה; רק מה שנראה על המסך, השאר ריק
      const liveC = [...root.querySelectorAll('canvas')].filter(keep), copyC = clone.querySelectorAll('canvas');
      liveC.forEach((cv, i) => {
        const c = copyC[i]; if (!c) return;
        const img = doc.createElement('img');
        [...c.attributes].forEach(a => img.setAttribute(a.name, a.value));
        if (!cv.style.width) img.style.width = cv.clientWidth + 'px';
        if (!cv.style.height) img.style.height = cv.clientHeight + 'px';
        img.setAttribute('src', cv.closest('[data-rh-mask],[data-rh-block]') ? BLANK : this.canvasUrl(cv));
        c.replaceWith(img);
      });

      // iframes מאותו origin (pdfViewer, iframe של xTafnit) - התוכן נכנס כ-srcdoc; iframe מ-origin אחר נשאר כמו שהוא
      const liveF = [...root.querySelectorAll('iframe,frame')].filter(keep), copyF = clone.querySelectorAll('iframe,frame');
      liveF.forEach((f, i) => {
        const c = copyF[i]; if (!c || depth >= CFG.frameDepth || f.closest('[data-rh-block]')) return;
        let inner = null; try { inner = f.contentDocument; } catch (_) { }
        if (!inner || !inner.documentElement) return;
        let h; try { h = this.serialize(inner, depth + 1, sc); } catch (_) { return; }
        c.removeAttribute('src');
        c.setAttribute('srcdoc', '<!DOCTYPE html>' + h);
      });

      clone.querySelectorAll('script,noscript').forEach(s => { s.textContent = ''; s.removeAttribute('src'); });
      clone.querySelectorAll('[data-rh-block]').forEach(e => { e.innerHTML = ''; });

      // ב-iframe: base לכתובת המקורית, כדי ש-CSS ותמונות ייטענו אצל העוזר
      if (depth > 0) {
        const head = clone.querySelector('head');
        if (head) { const b = doc.createElement('base'); b.setAttribute('href', doc.baseURI); head.insertBefore(b, head.firstChild); }
      }
      return clone.outerHTML;
    },

    /** canvas -> JPEG (מטמון קצר; canvas שלא על המסך נשלח ריק כדי לחסוך תעבורה) */
    canvasUrl(cv) {
      if (!cv.width || !cv.height) return BLANK;
      const r = cv.getBoundingClientRect(), win = cv.ownerDocument.defaultView;
      if (r.bottom < 0 || r.right < 0 || r.top > win.innerHeight || r.left > win.innerWidth) return BLANK;
      const cache = this.cvCache || (this.cvCache = new WeakMap()), e = cache.get(cv), now = Date.now();
      if (e && e.w === cv.width && e.h === cv.height && now - e.t < 1500) return e.u;
      let u = BLANK;
      try { u = cv.toDataURL('image/jpeg', CFG.canvasQuality); } catch (_) { }      // canvas "מזוהם" (תוכן מ-origin אחר) - נשאר ריק
      cache.set(cv, { w: cv.width, h: cv.height, t: now, u });
      return u;
    },

    /** שינויים וגלילה בתוך iframes מאותו origin גם מפעילים תמונת מצב */
    watchFrames(doc, depth) {
      if (!this.obs || depth >= CFG.frameDepth) return;
      const seen = this.watched || (this.watched = new WeakSet());
      doc.querySelectorAll('iframe,frame').forEach(f => {
        if (!seen.has(f)) { seen.add(f); f.addEventListener('load', () => this.sched()); }
        let inner = null; try { inner = f.contentDocument; } catch (_) { }
        if (!inner || !inner.documentElement || seen.has(inner)) return;
        seen.add(inner);
        this.obs.observe(inner.documentElement, { childList: true, subtree: true, attributes: true, characterData: true });
        ['input', 'change', 'scroll', 'resize'].forEach(t => inner.defaultView.addEventListener(t, this.onUi, true));
        this.watchFrames(inner, depth + 1);
      });
    },

    /* ─── הפעלת קלט של העוזר ─── */
    apply(m) {
      if (!this.control || !this.consent) return;           // הגנה נוספת בצד הלקוח
      const el = m.id ? findById(document, +m.id, 0) : null;
      if (el && el.closest('[data-rh-ignore],[data-rh-block]')) return;
      if (el && el.type === 'password') return;

      switch (m.e) {
        case 'mv': {
          const c = this.cur || (this.cur = mk('div', 'xrh-cursor'));
          c.style.display = 'block'; c.style.left = (+m.x) + 'px'; c.style.top = (+m.y) + 'px'; break;
        }
        case 'focus': if (el && el.focus) el.focus(); break;
        case 'click':
          if (!el || el.disabled) break;
          if (el.focus) el.focus({ preventScroll: true });
          ['mousedown', 'mouseup', 'click'].forEach(n => el.dispatchEvent(new MouseEvent(n, { bubbles: true, cancelable: true, view: el.ownerDocument.defaultView, clientX: +m.x, clientY: +m.y })));
          break;
        case 'input': {
          if (!el || el.disabled || el.readOnly) break;
          const proto = Object.getPrototypeOf(el), d = Object.getOwnPropertyDescriptor(proto, 'value');
          d && d.set ? d.set.call(el, String(m.v)) : (el.value = String(m.v));
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          break;
        }
        case 'key': {
          const t = el || document.activeElement || document.body;
          if (m.key === 'Enter' && (/^(BUTTON|A|SUMMARY)$/.test(t.tagName) || t.type === 'checkbox')) { t.click(); break; }
          ['keydown', 'keypress', 'keyup'].forEach(n => t.dispatchEvent(new KeyboardEvent(n, { key: String(m.key), bubbles: true, cancelable: true, shiftKey: !!m.sh })));
          break;
        }
        case 'scroll':
          if (el) { el.scrollTop = +m.y; el.scrollLeft = +m.x; } else scrollTo(+m.x, +m.y);
          break;
      }
    }
  };

  /* ═════════════════════════ צד עוזר ═════════════════════════ */

  const H = {
    code: null, token: null, ws: null, fr: null, wrap: null, control: false, lastSeq: 0, vw: 1280, vh: 800, mute: 0, onState: () => { },

    /** creds = { user, pass } - הזדהות העוזר מול xTafnit (HTTP Basic) */
    async start(code, host, onState, creds) {
      this.onState = onState || (() => { });
      const auth = creds ? { Authorization: 'Basic ' + btoa(unescape(encodeURIComponent(creds.user + ':' + creds.pass))) } : {};
      const r = await post('/join', { code }, auth);
      if (!r.ok) { this.onState('error', r.http === 401 ? 'שם משתמש או סיסמה שגויים' : (r.msg || 'שגיאה')); return false; }
      return this.attach(code, r.token, host);
    },

    /** חיבור עם טוקן שכבר התקבל בשרת (מסך TafnitCore.System.UI.App.Tools.Helper.HelperPage - עוזר מחובר, קוד בלבד) */
    attach(code, token, host, onState) {
      if (onState) this.onState = onState;
      this.code = code; this.token = token; this.build(host); this.onState('waiting', 'ממתין לאישור המשתמש…');

      const asm = assembler(m => this.onSnap(m));
      const ws = this.ws = new WebSocket(wsUrl());
      ws.onopen = () => wsAuth(ws, code, this.token);
      ws.onmessage = e => {
        let f; try { f = JSON.parse(e.data); } catch (_) { return; }
        if (f.k === 'c') asm(f);
        else if (f.k === 'm') switch (f.t) {
          case 'denied': this.onState('error', 'הגישה נדחתה'); this.cleanup(); break;
          case 'grant': this.control = !!f.control; this.onState(this.control ? 'control' : 'view', this.control ? 'שליטה פעילה' : 'צפייה בלבד'); break;
          case 'user-offline': this.onState('wait', 'המשתמש עובר דף… ממתין'); break;
          case 'paused': this.control = false; this.onState('wait', 'המשתמש נכנס למערכת – ממתין לאישור מחדש'); break;
          case 'bye': this.onState('closed', 'הסשן הסתיים'); this.cleanup(); break;
        }
      };
      ws.onclose = () => { if (this.code) { this.onState('closed', 'החיבור נותק'); } };
      return true;
    },

    stop() { post('/close', { code: this.code, token: this.token }).catch(() => { }); this.cleanup(); },
    cleanup() { this.code = null; this.token = null; try { this.ws && this.ws.close(); } catch (_) { } },
    send(o) { if (this.ws && this.ws.readyState === 1 && this.control) this.ws.send(JSON.stringify(Object.assign({ k: 'm', t: 'evt' }, o))); },

    build(host) {
      host.innerHTML = '';
      const wrap = this.wrap = document.createElement('div');
      wrap.style.cssText = 'position:relative;overflow:hidden;width:100%;height:100%;background:#1f2937';
      const fr = this.fr = document.createElement('iframe');
      fr.setAttribute('sandbox', 'allow-same-origin');                 // בלי scripts / forms / popups
      fr.style.cssText = 'border:0;background:#fff;position:absolute;left:0;top:0;transform-origin:0 0';
      fr.srcdoc = '<!DOCTYPE html><html><body></body></html>';
      fr.onload = () => { if (!fr._bound) { fr._bound = true; this.bindInput(fr.contentDocument); } };
      wrap.appendChild(fr); host.appendChild(wrap);
      addEventListener('resize', () => this.fit());
    },

    fit() {
      if (!this.fr) return;
      const s = Math.min(this.wrap.clientWidth / this.vw, this.wrap.clientHeight / this.vh);
      Object.assign(this.fr.style, { width: this.vw + 'px', height: this.vh + 'px', transform: 'scale(' + s + ')' });
    },

    onSnap(m) {
      if (m.t !== 'snap' || m.seq <= this.lastSeq) return; this.lastSeq = m.seq;
      const doc = this.fr.contentDocument; if (!doc || !doc.documentElement) return;
      this.vw = m.vw; this.vh = m.vh; this.fit();

      // המשתמש עשוי לגלוש בכתובת פנימית (למשל http://10.0.0.5 או xtafnit.local) שהעוזר החיצוני לא מגיע אליה.
      // מחליפים את ה-origin של המשתמש ב-origin שדרכו העוזר מחובר לאותו שרת.
      let html = m.html, baseHref = m.base;
      try {
        const ub = new URL(m.base);
        if (ub.origin !== location.origin) {
          html = html.split(ub.origin).join(location.origin);
          baseHref = location.origin + ub.pathname;
        }
      } catch (_) { }

      const d = new DOMParser().parseFromString(html, 'text/html');
      d.querySelectorAll('meta[http-equiv]').forEach(e => e.remove());
      const base = d.createElement('base'); base.href = baseHref; d.head.insertBefore(base, d.head.firstChild);

      const a = doc.activeElement, fid = a && a.getAttribute && a.getAttribute('data-rhid');
      const ss = a && a.selectionStart, se = a && a.selectionEnd;
      this.mute = Date.now() + 300;
      doc.replaceChild(doc.importNode(d.documentElement, true), doc.documentElement);

      if (fid) { const e = doc.querySelector('[data-rhid="' + fid + '"]'); if (e) { e.focus({ preventScroll: true }); try { e.setSelectionRange(ss, se); } catch (_) { } } }

      // גלילה - גם בתוך iframes משוקפים (srcdoc נטען אחרי ההחלפה, לכן שוב ב-load של כל iframe)
      const applyScroll = () => {
        this.mute = Date.now() + 300;
        (m.sc || []).forEach(s => { const e = findById(doc, s.id, 0); if (e) { e.scrollTop = s.t; e.scrollLeft = s.l; } });
      };
      const bound = this.boundDocs || (this.boundDocs = new WeakSet());
      const hook = (d, depth) => d.querySelectorAll('iframe,frame').forEach(f => f.addEventListener('load', () => {
        let nd = null; try { nd = f.contentDocument; } catch (_) { }
        if (!nd || !nd.documentElement) return;
        if (!bound.has(nd)) { bound.add(nd); this.bindInput(nd, true); }
        applyScroll();
        if (depth + 1 < CFG.frameDepth) hook(nd, depth + 1);
      }));
      hook(doc, 0);
      applyScroll();
      doc.defaultView.scrollTo(m.sx, m.sy);
      this.onState('live', m.title || '');
    },

    /** nested = מסמך של iframe משוקף: גלילת השורש וסמן העכבר לא נשלחים (הקואורדינטות יחסיות ל-iframe) */
    bindInput(doc, nested) {
      const idOf = t => { const e = t && t.closest ? t.closest('[data-rhid]') : null; return e ? +e.getAttribute('data-rhid') : null; };
      const textual = t => /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName) && !/^(checkbox|radio|button|submit|reset)$/.test(t.type || '');

      doc.addEventListener('click', ev => {
        if (textual(ev.target)) return this.send({ e: 'focus', id: idOf(ev.target) });
        ev.preventDefault();
        this.send({ e: 'click', id: idOf(ev.target), x: ev.clientX, y: ev.clientY });
      }, true);

      doc.addEventListener('input', ev => { const t = ev.target; if (t.type !== 'password') this.send({ e: 'input', id: idOf(t), v: t.value }); }, true);
      doc.addEventListener('change', ev => { const t = ev.target; if (t.tagName === 'SELECT') this.send({ e: 'input', id: idOf(t), v: t.value }); }, true);

      doc.addEventListener('keydown', ev => {
        if (!['Enter', 'Escape', 'Tab', 'F2', 'F3', 'F4', 'F5', 'F8', 'F9'].includes(ev.key)) return;
        if (!(ev.key === 'Enter' && ev.target.tagName === 'TEXTAREA')) ev.preventDefault();
        this.send({ e: 'key', id: idOf(ev.target), key: ev.key, sh: ev.shiftKey });
      }, true);

      doc.addEventListener('scroll', ev => {
        if (Date.now() < this.mute) return;
        const t = ev.target;
        if (t === doc) { if (!nested) this.send({ e: 'scroll', x: doc.defaultView.scrollX, y: doc.defaultView.scrollY }); }
        else if (t.getAttribute) this.send({ e: 'scroll', id: idOf(t), x: t.scrollLeft, y: t.scrollTop });
      }, true);

      if (nested) return;
      let lt = 0;
      doc.addEventListener('mousemove', ev => { const n = Date.now(); if (n - lt < 80) return; lt = n; this.send({ e: 'mv', x: ev.clientX, y: ev.clientY }); }, true);
    }
  };

  w.XRH = { user: U, helper: H, config: CFG };

  /* לחיצה על כפתור "עזרה מרחוק" (capture - לפני הפריימוורק) */
  document.addEventListener('click', ev => {
    const t = ev.target && ev.target.closest ? ev.target.closest(CFG.startSelector) : null;
    if (!t || t.closest('[data-rh-ignore]')) return;
    ev.preventDefault(); ev.stopPropagation();
    U.start();
  }, true);

  /* חידוש אוטומטי של סשן פעיל אחרי ניווט */
  if (sessionStorage.getItem('xrh')) {
    (document.readyState === 'loading') ? document.addEventListener('DOMContentLoaded', () => U.resume()) : U.resume();
  }
})(window);
