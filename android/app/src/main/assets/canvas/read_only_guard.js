/* Makes the workspace view-only: swallows every trusted input event that could select,
   move, or edit shapes before Penpot sees it. The synthetic wheel events from touch_pan.js
   are untrusted, so panning/zooming keeps working. Guarded by the route so a
   session-expired login page shown in the web view stays usable.
   MUST be injected after touch_pan.js — the document-level touch stoppers rely on the
   pan handlers having registered (and run) first. Ported verbatim from iOS. */
(function(){
  if (window.__penpotReadOnly) return; window.__penpotReadOnly = true;
  function inWorkspace(){ return location.hash.indexOf('/workspace') !== -1; }
  function guard(e){
    if (!e.isTrusted || !inWorkspace()) return;
    e.preventDefault(); e.stopImmediatePropagation();
  }
  // pointermove/mousemove stay allowed: they only feed Penpot's internal position
  // streams (hover, zoom targets) and cannot select or move anything on their own —
  // that needs pointerdown/click, which stay blocked.
  ['pointerdown','pointerup','pointercancel',
   'mousedown','mouseup','click','dblclick','auxclick','contextmenu',
   'keydown','keypress','keyup','dragstart','drop','cut','paste','beforeinput'
  ].forEach(function(t){ window.addEventListener(t, guard, {capture:true, passive:false}); });
  // Touch events must stay live for the pan/zoom translation (registered on document
  // before this script), but must not travel on to Penpot's own canvas handlers.
  ['touchstart','touchmove','touchend','touchcancel'].forEach(function(t){
    document.addEventListener(t, function(e){
      if (e.isTrusted && inWorkspace()) e.stopImmediatePropagation();
    }, {capture:true, passive:false});
  });
})();
