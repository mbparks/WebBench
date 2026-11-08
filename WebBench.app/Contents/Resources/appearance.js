// Design and Write only. Run and exported pages never load editor controls.
(() => {
  const {marker,token}=WB;
  const post=(kind,data)=>window.webkit.messageHandlers.design.postMessage({token,kind,...data});
  // A browsing context receives its own mouse events. During editing, hit-test the real
  // frame box in the parent document so ordinary selection and resize handles still work.
  if (WB.tree?.some(row=>row.tag==='iframe')) {
    const selector='iframe['+marker+']';
    const frames=Array.from(document.querySelectorAll(selector));
    const shield=document.createElement('style');
    shield.textContent=selector+'{pointer-events:none!important}';
    document.head.append(shield);
    window.webBenchHitAt=(x,y)=>{
      const overFrame=frames.some(frame=>{
        const rect=frame.getBoundingClientRect();
        return x>=rect.left && x<=rect.right && y>=rect.top && y<=rect.bottom;
      });
      if(!overFrame) return document.elementFromPoint(x,y);
      shield.sheet.disabled=true;
      try { return document.elementFromPoint(x,y); }
      finally { shield.sheet.disabled=false; }
    };
    for (const type of ['pointerdown','pointerup','pointermove','click','dblclick','contextmenu']) {
      window.addEventListener(type,event=>{
        if(!event.isTrusted || event.target.closest?.(selector) || (type.startsWith('pointer') && event.target.hasPointerCapture?.(event.pointerId))) return;
        const frame=window.webBenchHitAt(event.clientX,event.clientY);
        if(!frame?.matches(selector)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        const EventType=type.startsWith('pointer')?PointerEvent:MouseEvent;
        frame.dispatchEvent(new EventType(type,event));
      },true);
    }
  }
  if(WB.tree?.some(row=>row.tag==='div') && document.querySelector('div[data-html-snippet]')) {
    const hint=marker+'-empty-snippet';
    const style=document.createElement('style');
    style.textContent='['+hint+']::before{content:"Custom HTML";display:inline-block;padding:8px 12px;border:1px dashed #628470;color:#264c3b;background:#edf2ea;font:13px system-ui}';
    document.head.append(style);
    for(const node of document.querySelectorAll('div[data-html-snippet]')) {
      if(node.getBoundingClientRect().height<=1) node.setAttribute(hint,'');
    }
  }
  const transparent=c=>c==='transparent'||/^rgba\(.*[,/]\s*0(?:\.0+)?\s*\)$/.test(c);
  const snapshot=()=>{
    if(!document.body)return;
    const root=getComputedStyle(document.documentElement), body=getComputedStyle(document.body);
    post('paper',{color:transparent(body.backgroundColor)?root.backgroundColor:body.backgroundColor,
      image:root.backgroundImage!=='none'||body.backgroundImage!=='none'});
  };
  window.webBenchPaper=snapshot;
  window.addEventListener('load',snapshot);
  window.addEventListener('resize',snapshot);
  window.webBenchPaint=(scope,id,value,keepImage)=>{
    if(!/^(?:transparent|#[\da-f]{6}(?:[\da-f]{2})?)$/i.test(value))return;
    try{
      const target=scope==='element'?document.querySelector('['+marker+'="'+id+'"]'):null;
      const elements=scope==='page'?[document.documentElement,document.body]:[target];
      const parser=document.createElement('span');
      const parts=[];
      for(const el of elements){
        if(!el)throw Error('The paint target is unavailable. Select it on the page again.');
        const attr=el.getAttribute(marker);
        const sourceID=attr!==null?Number(attr):el===document.documentElement?-1:el===document.body?-2:null;
        if(sourceID==null || (sourceID>=0 && ((window.webBenchWritingMaps?!window.webBenchWritingMaps(el):WB.tree[sourceID]?.tag!==el.localName) ||
            document.querySelectorAll('['+marker+'="'+sourceID+'"]').length!==1)))throw Error('This object has no unique source target.');
        const color=scope==='page' && el===document.body?'transparent':value;
        parser.style.color=color;
        const expected=parser.style.color;
        const cs=getComputedStyle(el), old=el.getAttribute('style'), part={id:sourceID};
        const equal=(actual,desired)=>actual===desired||(transparent(actual)&&transparent(desired));
        const changeColor=!equal(cs.backgroundColor,expected);
        const changeImage=!keepImage&&cs.backgroundImage!=='none';
        if(!changeColor&&!changeImage)continue;
        let css=old||'';
        try{
          for(const [prop,val,wanted,needed,key] of [
            ['background-color',color,expected,changeColor,'strongColor'],
            ['background-image','none','none',changeImage,'strongImage']
          ]){
            if(!needed)continue;
            let trial=WebBench.paintCSS(css,prop,val,false);
            el.setAttribute('style',trial);
            if(!equal(getComputedStyle(el).getPropertyValue(prop),wanted)){
              trial=WebBench.paintCSS(css,prop,val,true);
              el.setAttribute('style',trial);part[key]=true;
            }
            if(!equal(getComputedStyle(el).getPropertyValue(prop),wanted))
              throw Error('A CSS transition, animation or other style controls this background. Inspect the element’s CSS.');
            css=trial;
            if(prop==='background-color')part.color=color;else part.image=true;
          }
        }finally{if(old===null)el.removeAttribute('style');else el.setAttribute('style',old);}
        parts.push(part);
      }
      post('paint',{scope,id,parts});
    }catch(e){post('notice',{message:e.message});}
  };
})();
