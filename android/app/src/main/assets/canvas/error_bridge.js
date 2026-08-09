/* Penpot catches workspace exceptions itself and shows only a generic toast, but it
   logs the real error via console.error — forward those (plus uncaught errors and
   promise rejections) to the native log so canvas issues are diagnosable.
   The only deliberate deviation from the iOS script: the sink is the injected
   PenpotBridge JavascriptInterface instead of webkit.messageHandlers. */
(function(){
  if (window.__penpotErrLog) return; window.__penpotErrLog = true;
  function send(kind, msg){
    try { window.PenpotBridge && window.PenpotBridge.log(kind + ': ' + msg); } catch(e){}
  }
  window.addEventListener('error', function(e){
    send('js-error', (e.message||'') + ' @' + (e.filename||'') + ':' + (e.lineno||0)
         + (e.error && e.error.stack ? '\n' + e.error.stack : ''));
  }, true);
  window.addEventListener('unhandledrejection', function(e){
    var r = e.reason;
    send('promise', (r && (r.stack || r.message)) || String(r));
  });
  var ce = console.error;
  console.error = function(){
    var parts = [];
    for (var i = 0; i < arguments.length; i++) {
      var a = arguments[i];
      try { parts.push(a instanceof Error ? (a.stack || a.message) : (typeof a === 'object' ? JSON.stringify(a) : String(a))); }
      catch(err) { parts.push(String(a)); }
    }
    send('console.error', parts.join(' '));
    ce.apply(console, arguments);
  };
})();
