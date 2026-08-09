/* Translates touch gestures into the wheel events Penpot's desktop canvas pans/zooms on:
   one-finger drag → pan, two-finger pinch → zoom (Penpot zooms on ctrl+wheel).
   Ported verbatim from the iOS PenpotCanvasView. */
(function(){
  if (window.__penpotTouch) return; window.__penpotTouch = true;
  var lastX=0,lastY=0,panning=false,lastDist=0;
  function dist(t){return Math.hypot(t[0].clientX-t[1].clientX, t[0].clientY-t[1].clientY);}
  function fire(x,y,dx,dy,zoom){
    var el=document.elementFromPoint(x,y)||document.body;
    el.dispatchEvent(new WheelEvent('wheel',{deltaX:dx,deltaY:dy,clientX:x,clientY:y,ctrlKey:!!zoom,bubbles:true,cancelable:true}));
  }
  document.addEventListener('touchstart',function(e){
    if(e.touches.length===1){panning=true;lastX=e.touches[0].clientX;lastY=e.touches[0].clientY;}
    else if(e.touches.length===2){panning=false;lastDist=dist(e.touches);}
  },{passive:false,capture:true});
  document.addEventListener('touchmove',function(e){
    var t=e.touches;
    if(t.length===1&&panning){var x=t[0].clientX,y=t[0].clientY;fire(x,y,lastX-x,lastY-y,false);lastX=x;lastY=y;e.preventDefault();}
    else if(t.length===2){var nd=dist(t),cx=(t[0].clientX+t[1].clientX)/2,cy=(t[0].clientY+t[1].clientY)/2;fire(cx,cy,0,lastDist-nd,true);lastDist=nd;e.preventDefault();}
  },{passive:false,capture:true});
  document.addEventListener('touchend',function(e){if(e.touches.length===0)panning=false;},{passive:false,capture:true});
})();
