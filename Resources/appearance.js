// Design and Write only. Run and exported pages never load editor controls.
(() => {
  const {marker,token}=WB;
  const post=(kind,data)=>window.webkit.messageHandlers.design.postMessage({token,kind,...data});
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
