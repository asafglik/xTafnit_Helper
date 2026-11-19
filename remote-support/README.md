# xTafnit Remote Support (IRIS prototype)

This directory is a development prototype for ObjectScript WebSocket-based support with a browser-side client and support console.

**NOT PRODUCTION READY.** Authentication, authorization, consent, audit, sensitive-field redaction, and Kendo/xTafnit compatibility require review and implementation before use with real users.

Files:
- `src/Support.WebSocket.cls` — ObjectScript WebSocket relay prototype
- `static/client.js` — browser client prototype
- `static/console.html` — support console prototype

Do not expose the prototype publicly or use with customer data. Run only in an isolated test environment. The implementation has not been compiled or validated against IRIS 2025.