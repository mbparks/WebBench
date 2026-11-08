// Injected only into Edit's isolated WKContentWorld. WB is supplied by the native host.
(() => {
  const {marker,token,tree}=WB;
  const key=e=>e?.hasAttribute?.(marker)?Number(e.getAttribute(marker)):-1;
  const el=id=>document.querySelector('['+marker+'="'+id+'"]');
  const post=(kind,body={})=>window.webkit.messageHandlers.design.postMessage({kind,token,...body});
  const label=e=>e.localName+(e.id?'#'+e.id:'')+[...e.classList].map(c=>'.'+c).join('');
  const canMap=e=>{
    const n=tree[key(e)];
    if(!n||n.tag!==e.localName||document.querySelectorAll('['+marker+'="'+n.id+'"]').length!==1)return false;
    for(let node=e;node;node=node.parentElement?.closest('['+marker+']')){
      const row=tree[key(node)],parent=node.parentElement?.closest('['+marker+']');
      if(!row || row.tag!==node.localName || row.parent!==key(parent))return false;
    }
    return true;
  };
  // Capture picking before the ordinary drag, text and keyboard edit handlers.
  let workflowMode = false;
  window.webBenchWorkflowMode = enabled => { workflowMode = !!enabled; };
  for (const type of ['pointerdown','pointerup','click','dblclick','keydown','dragstart','drop','contextmenu']) {
    window.addEventListener(type, event => {
      if (!workflowMode) return;
      if (type === 'keydown' && event.key !== 'Escape' && !['Backspace','Delete','ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(event.key)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (type === 'keydown' && event.key === 'Escape') post('workflowCancelPick');
      if (type === 'click') {
        const target = event.target.closest?.('[' + marker + ']');
        if (target && canMap(target)) post('workflowPick', { id: key(target) });
      }
    }, true);
  }
  // Shadow DOM keeps selection handles and guides out of the author's styling.
  const chrome=document.createElement('div');
  chrome.setAttribute('aria-hidden','true');
  chrome.style.cssText='all:initial!important;position:fixed!important;inset:0!important;pointer-events:none!important;z-index:2147483647!important;display:block!important;';
  document.documentElement.appendChild(chrome);
  const shadow=chrome.attachShadow({mode:'closed'});
  const sheet=document.createElement('style');
  sheet.textContent=`
    *{box-sizing:border-box}
    .selection,.tip,.grip,.guide{display:none;position:fixed;pointer-events:none}
    .selection{border:1.5px solid #168463;box-shadow:0 0 0 1px #ffffffad}
    .member{position:fixed;pointer-events:none;border:1px solid #188a69}
    .member.anchor{border:2px solid #164fc7}
    .hover{display:none;position:fixed;pointer-events:none;outline:1px dashed #188a6999}
    .tip{padding:3px 7px;border-radius:12px;background:#193e32;color:#e5f3c2;font:600 11px system-ui;white-space:nowrap}
    .grip{width:var(--hit,22px);height:var(--hit,22px);transform:translate(-50%,-50%);pointer-events:auto;touch-action:none}
    .grip::after{content:"";position:absolute;left:50%;top:50%;width:var(--dot,9px);height:var(--dot,9px);transform:translate(-50%,-50%);background:white;border:1.5px solid #12664f;border-radius:2px;box-shadow:0 1px 2px #0004}
    .guide{background:#cc4c8a}
  `;
  shadow.append(sheet);
  function overlay(className) {
    const e=document.createElement('div');e.className=className;shadow.append(e);return e;
  }
  const dots=overlay('grid');
  dots.style.cssText='display:none;position:fixed;inset:0;pointer-events:none;background:radial-gradient(circle at 1px 1px,#618c7829 1px,transparent 1.2px) 0 0/16px 16px';
  function gridOrigin(){dots.style.backgroundPosition=(-scrollX)+'px '+(-scrollY)+'px';}
  window.webBenchGrid=on=>{dots.style.display=on?'block':'none';gridOrigin();};
  const box=overlay('selection'), hint=overlay('tip'), hover=overlay('hover');
  const grips=new Map(['nw','n','ne','w','e','sw','s','se'].map(direction=>{
    const g=overlay('grip');g.style.cursor=direction+'-resize';
    g.addEventListener('pointerdown',ev=>begin(ev,selected,direction));
    return [direction,g];
  }));
  const gx=overlay('guide'), gy=overlay('guide');
  let scale=1, scoped=false;
  window.webBenchVariant=on=>{if(scoped!==on){cancelGesture();cancelScrub();scoped=on;}};
  const priority=(e,k)=>scoped?'important':e.style.getPropertyPriority(k);
  function currentBand(){return scoped?(innerWidth<=600?'phone':innerWidth<=1024?'tablet':'desktop'):'';}

  window.webBenchScale=value=>{scale=Math.max(.1,Number(value)||1);chrome.style.setProperty('--hit',(22/scale)+'px');chrome.style.setProperty('--dot',(8/scale)+'px');outline();};
  let free=false, snap=true, tool='', move=null, ignoreClick=false;
  let members=[], outlines=[];
  let selected=null, prop='margin-top', destination=null;
  window.webBenchPlacement=enabled=>{free=enabled;};
  // This guide exists only in the isolated Edit overlay. Pointer events pass through to the page.
  let blankGuide;
  if(document.body?.hasAttribute('data-free-page') && !document.body.children.length && !document.body.textContent?.trim()) {
    blankGuide=overlay('blank-guide');
    blankGuide.innerHTML='<div class="sample-pieces"><i class="sample-photo"><b></b></i><i class="sample-type">Aa</i><i class="sample-grid"><b></b><b></b><b></b><b></b></i></div><strong>Drag in your first element</strong><span>Double-click placed text to start writing.</span>';
    const guideStyle=document.createElement('style');
    guideStyle.textContent=`
      .blank-guide{position:absolute;inset:0;display:grid;place-content:center;justify-items:center;align-content:center;gap:13px;padding:22px;text-align:center;pointer-events:none;color:#253e34}
      .blank-guide strong{font:normal clamp(23px,3.1vw,43px)/1.12 Georgia,serif;letter-spacing:-.04em;color:#213e32;background:#fffffff2;border-radius:6px;padding:2px 9px}
      .blank-guide span{max-width:32em;font:500 clamp(13px,1.3vw,17px)/1.45 system-ui,sans-serif;color:#435d50;background:#fffffff2;border-radius:5px;padding:1px 6px}
      .sample-pieces{position:relative;width:172px;height:93px;margin-bottom:5px}
      .sample-pieces i{position:absolute;box-shadow:0 5px 9px #233e301b;border:1px solid #2b443932;border-radius:7px}
      .sample-photo{width:70px;height:67px;left:4px;top:18px;transform:rotate(-13deg);background:#adced1;overflow:hidden}
      .sample-photo:before{content:"";position:absolute;background:#fff3c4;width:14px;height:14px;border-radius:50%;top:10px;right:11px}
      .sample-photo b{position:absolute;bottom:-23px;left:0;width:60px;height:55px;background:#40827c;transform:rotate(35deg);border-radius:4px}
      .sample-type{width:72px;height:81px;top:0;left:53px;transform:rotate(4deg);background:#f2d5bc;color:#663e38;font:italic 38px/81px Georgia,serif;text-align:center}
      .sample-grid{width:51px;height:51px;left:114px;top:37px;transform:rotate(13deg);background:#d7ebae;display:grid;grid-template-columns:1fr 1fr;gap:3px;padding:11px}
      .sample-grid b{border:1.5px solid #355d49;border-radius:1px}
      @media(max-height:260px){.sample-pieces{display:none}.blank-guide{gap:4px}}
    `;
    shadow.append(guideStyle);
  }
  window.webBenchEmptyHint=visible=>{if(blankGuide)blankGuide.style.display=visible&&!tool?'grid':'none';};
  const cursorSheet=document.createElement('style');
  const armedAttr=marker+'-placing';
  cursorSheet.textContent='body ['+marker+']{cursor:grab!important} html['+armedAttr+'],html['+armedAttr+'] *{cursor:crosshair!important}';
  (document.head||document.documentElement).appendChild(cursorSheet);
  window.webBenchTools=(item,enabled)=>{tool=item || '';snap=enabled;document.documentElement.toggleAttribute(armedAttr,!!tool);clear();window.webBenchEmptyHint(true);};
  function place(node,rect) {
    Object.assign(node.style,{display:'block',left:rect.x+'px',top:rect.y+'px',width:rect.width+'px',height:rect.height+'px'});
  }
  function tip(text,x,y) {
    hint.textContent=text;
    Object.assign(hint.style,{display:'block',left:Math.max(0,Math.min(x+8,innerWidth-178))+'px',top:Math.max(0,y-26)+'px'});
  }
  function clearGuides(){gx.style.display='none';gy.style.display='none';}
  function frameOf(e) {
    const cs=getComputedStyle(e),r=e.getBoundingClientRect();
    const px=v=>/^-?(?:\d+\.?\d*|\.\d+)px$/.test(v);
    let axisAligned=true;
    for(let a=e;a;a=a.parentElement){
      const s=getComputedStyle(a);
      if(s.transform!=='none'||['rotate','scale','translate','perspective'].some(p=>s[p] && s[p]!=='none')||
         (s.zoom && !['1','normal'].includes(s.zoom))) axisAligned=false;
    }
    const canMove=axisAligned && cs.position==='absolute' && e.offsetParent===e.parentElement &&
      e.offsetParent && getComputedStyle(e.offsetParent).position!=='static' && px(cs.left)&&px(cs.top);
    const replaced=['img','input','button','textarea','select','video','canvas','iframe'].includes(e.localName);
    const inlineBox=cs.display==='inline' && !replaced;
    const num=v=>parseFloat(v)||0;
    const content=cs.boxSizing!=='border-box';
    const width=px(cs.width)?parseFloat(cs.width):Math.max(1,r.width-(content?num(cs.paddingLeft)+num(cs.paddingRight)+num(cs.borderLeftWidth)+num(cs.borderRightWidth):0));
    const height=px(cs.height)?parseFloat(cs.height):Math.max(1,r.height-(content?num(cs.paddingTop)+num(cs.paddingBottom)+num(cs.borderTopWidth)+num(cs.borderBottomWidth):0));
    const canResize=axisAligned && !/^(html|body|thead|tbody|tfoot|tr|col|option|script|style)$/.test(e.localName) &&
      !e.closest('svg,math') && !['contents','none'].includes(cs.display) && e.getClientRects().length>0;
    const parentStyle=e.parentElement && getComputedStyle(e.parentElement);
    const canStack=canMove && (e.parentElement===document.documentElement || parentStyle.isolation==='isolate' ||
      parentStyle.zIndex!=='auto' || Number(parentStyle.opacity)<1 || ['sticky','fixed'].includes(parentStyle.position));
    const canLift=canResize && ['static','relative'].includes(cs.position) && e.parentElement &&
      canMap(e.parentElement) && parentStyle.position!=='static' && !e.matches('table,tbody,thead,tfoot,tr,td,th');
    return {canMove:!!canMove,canLift:!!canLift,canStack:!!canStack,canResize:!!canResize,x:parseFloat(cs.left)||0,y:parseFloat(cs.top)||0,
      width,height,inlineBox,fontFamily:cs.fontFamily||"",stack:Number.parseInt(cs.zIndex,10)||0,
      hasImage:cs.backgroundImage && cs.backgroundImage!=='none',fill:cs.backgroundColor,ink:cs.color,fontSize:cs.fontSize,align:cs.textAlign};
  }
  function handles(r,show) {
    const leading=show && selected && frameOf(selected).canMove;
    const midX=(Math.max(0,r.x)+Math.min(innerWidth,r.x+r.width))/2, midY=(Math.max(0,r.y)+Math.min(innerHeight,r.y+r.height))/2;
    for(const [edge,g] of grips) {
      if(!show || (!leading && /[nw]/.test(edge))){g.style.display='none';continue;}
      const x=edge.includes('w')?r.x:edge.includes('e')?r.x+r.width:midX;
      const y=edge.includes('n')?r.y:edge.includes('s')?r.y+r.height:midY;
      if(x< -1 || y< -1 || x>innerWidth+1 || y>innerHeight+1){g.style.display='none';continue;}
      const inset=5/scale;
      Object.assign(g.style,{display:'block',left:Math.min(innerWidth-inset,Math.max(inset,x))+'px',
        top:Math.min(innerHeight-inset,Math.max(inset,y))+'px'});
    }
  }
  function outline() {
    if(move?.active) return;
    outlines.forEach(node=>{node.style.display='none';});
    box.style.borderStyle=members.length>1?'dashed':'solid';
    if(members.length>1) {drawSelection();return;}
    if(!selected?.isConnected){box.style.display='none';handles({},false);return;}
    const r=selected.getBoundingClientRect();place(box,r);handles(r,!tool && frameOf(selected).canResize);
  }
  function drawSelection() {
    const frames=members.map(e=>({rect:e.getBoundingClientRect()}));
    for(let i=0;i<members.length;i++) {
      if(!outlines[i])outlines[i]=overlay(i===0?'member anchor':'member');
      place(outlines[i],frames[i].rect);
    }
    place(box,Arrange.bounds(frames));handles({},false);
  }
  function movable(e) {
    if(!e||!canMap(e)||!frameOf(e).canMove||!e.getClientRects().length)return false;
    const r=e.getBoundingClientRect();
    return r.width>0&&r.height>0;
  }
  function setMembers(next,scroll=false) {
    cancelScrub();
    selected=next[0]||null;members=next;
    if(selected)inspect(scroll);else {outline();post('deselect');}
  }
  const memberIDs=()=>members.map(key);
  const sameIDs=ids=>Array.isArray(ids)&&ids.length===members.length&&ids.every((id,i)=>id===key(members[i]));
  function toggle(e) {
    if(!e||!canMap(e))return;
    if(members.includes(e)){setMembers(members.filter(m=>m!==e));return;}
    if(members.length && (e.parentElement!==selected.parentElement||![...members,e].every(movable))){
      post('notice',{message:'Select free-positioned layers with the same parent. Use Layers to select a containing object.'});return;
    }
    setMembers([...members,e]);
  }
  window.webBenchToggle=id=>toggle(el(id));
  window.webBenchSelectMany=(ids,property,scroll=false)=>{
    prop=property;
    const nodes=ids.map(el);
    if(nodes.some(e=>!e||!canMap(e))){post('unmapped',{id:ids[0]});return;}
    if(nodes.length>1 && !nodes.every(e=>e.parentElement===nodes[0].parentElement&&movable(e))){
      setMembers(nodes.slice(0,1),scroll);
      post('notice',{message:'At this viewport the layers no longer share a movable coordinate system.'});return;
    }
    setMembers(nodes,scroll);
  };
  function matchRules(e,property) {
    const css=getComputedStyle(e), candidates=[], track=[], custom='--wb-'+Math.random().toString(36).slice(2);
    let limited=false;
    const matching=selector=>{try{return [...document.querySelectorAll(selector)].filter(x=>x!==box&&x!==hint);}catch{return [];}};
    function visit(list,source,styleIndex,path=[],context=[]) {
      for(let i=0;i<list.length;i++) {
        const r=list[i], here=[...path,i];
        if(r.selectorText && r.style) {
          if(r.cssRules?.length)limited=true;
          try{if(!e.matches(r.selectorText))continue;}catch{continue;}
          const value=r.style.getPropertyValue(property);
          if(/^(margin|padding|inset|border|width|height)/.test(property) && Array.from(r.style).some(k=>/-(inline|block)(-|$)/.test(k)))limited=true;
          if(value && /^(revert|revert-layer|inherit|unset)$/.test(value.trim()))limited=true;
          if(!value) {if(r.style.getPropertyValue('all'))limited=true;continue;}
          const affected=matching(r.selectorText),num=candidates.length;
          candidates.push({selector:r.selectorText,value,priority:r.style.getPropertyPriority(property),source,styleIndex,path:here,media:context.join(' · '),count:affected.length,examples:affected.slice(0,6).map(label).join(', ')});
          track.push(r.style);r.style.setProperty(custom,'p'+num,r.style.getPropertyPriority(property));
        } else if(r.type===3){limited=true;}
        else if(r.cssRules) {
          if(r.media && !matchMedia(r.conditionText).matches)continue;
          if(r.constructor.name==='CSSSupportsRule'&&!CSS.supports(r.conditionText))continue;
          visit(r.cssRules,source,styleIndex,here,[...context,r.conditionText||r.name||r.constructor.name]);
        }
      }
    }
    let winner=-1;
    const originalStyle=e.getAttribute('style');
    try {
      const styles=[...document.querySelectorAll('style')];
      for(const sheet of document.styleSheets) {
        if(sheet.ownerNode===cursorSheet || sheet.disabled || (sheet.media.mediaText&&!matchMedia(sheet.media.mediaText).matches))continue;
        try{visit(sheet.cssRules,sheet.href||'',styles.indexOf(sheet.ownerNode),[],sheet.media.mediaText?[sheet.media.mediaText]:[]);}
        catch{limited=true;}
      }
      const inline=e.style?.getPropertyValue(property);
      if(inline){const num=candidates.length;candidates.push({selector:'style attribute',source:'',styleIndex:-2,path:[],media:'',value:inline,priority:e.style.getPropertyPriority(property),count:1,examples:label(e)});track.push(e.style);e.style.setProperty(custom,'p'+num,e.style.getPropertyPriority(property));}
      const v=css.getPropertyValue(custom).trim(); if(/^p\d+$/.test(v))winner=Number(v.slice(1));
      if(e.getAnimations?.().length)limited=true;
    } finally {
      for(const style of track)style.removeProperty(custom);
      if(track.includes(e.style)){
        if(originalStyle==null)e.removeAttribute('style');else e.setAttribute('style',originalStyle);
      }
    }
    return {rules:candidates,winner:limited?-1:winner,limited,computed:css.getPropertyValue(property)};
  }
  window.webBenchMatches=selector=>[...document.querySelectorAll(selector)].filter(e=>e!==chrome).map(e=>{
    const path=[];for(let a=e;a;a=a.parentElement){
      let part=a.localName;if(a.id){path.unshift(part+'#'+a.id);break;}
      if(a.parentElement)part+=':nth-child('+([...a.parentElement.children].indexOf(a)+1)+')';
      path.unshift(part);
    }
    return path.join(' > ')+'   '+label(e);
  }).join('\n');
  function inspect(scroll=false) {
    const e=selected;if(!e)return;
    if(scroll)e.scrollIntoView({block:'nearest',inline:'nearest'});
    outline();
    if(members.length>1){post('multiSelect',{ids:memberIDs(),prop});return;}
    const classes=[...e.classList].filter(c=>/^[A-Za-z_][\w-]*$/.test(c)).map(name=>{
      const matched=[...document.getElementsByClassName(name)];
      return {name,count:matched.length,examples:matched.slice(0,6).map(label).join(', ')};
    });
    const cs=getComputedStyle(e),frame=frameOf(e);
    let front=0,back=0;
    if(frame.canMove)for(const s of e.parentElement.children) {
      if(s===e)continue;
      const z=Number(getComputedStyle(s).zIndex)||0;front=Math.max(front,z);back=Math.min(back,z);
    }
    post('select',{id:key(e),label:label(e),position:cs.position,photoURL:e.localName==='img'&&!/^data:/i.test(e.getAttribute('src')||'')?(e.currentSrc||e.src||''):'',responsivePhoto:e.localName==='img'&&(e.hasAttribute('srcset')||e.parentElement?.localName==='picture'),frontLevel:front+1,backLevel:back-1,prop,text:e.children.length||e.textContent.length>20000?'':e.textContent,textEditable:e.localName!=='iframe' && e.children.length===0 && e.textContent.length<=20000,classes,...matchRules(e,prop),
      sheets:[...document.styleSheets].map(s=>s.href).filter(Boolean),...frame,display:cs.display,
      attributes:Object.fromEntries(['id','class','href','src','alt','value','title','aria-label','for','type'].map(a=>[a,(a==='src' && e.localName==='iframe' ? e.getAttribute(marker+'-src') : e.getAttribute(a))||'']))});
  }
  window.webBenchSelect=(id,property,scroll=false)=>window.webBenchSelectMany([id],property,scroll);
  window.addEventListener('click',event=>{
    event.preventDefault();event.stopImmediatePropagation();
    if(ignoreClick || event.target===chrome)return;
    if(tool){
      LayoutDrop.clear();
      const d=toolDestination(event);
      if(!d){post('notice',{message:'Click a mapped layout container to place this element.'});return;}
      const item=tool;tool='';clear();
      post('place',{id:d.id,before:d.before,point:d.point||null,item,scroll:[scrollX,scrollY]});return;
    }
    const e=event.target.closest?.('['+marker+']');if(!e||!canMap(e)){post('unmapped',{id:key(e)});return;}
    if(event.metaKey||event.shiftKey){
      const layer=members.find(m=>m.contains(e));
      // A label inside a positioned object selects its movable container.
      let target=e;while(target && !movable(target))target=target.parentElement?.closest('['+marker+']');
      toggle(layer||target||e);return;
    }
    setMembers([e]);
  },true);
  window.addEventListener('submit',e=>e.preventDefault(),true);
  window.addEventListener('dragover',event=>{
    event.preventDefault();destination=toolDestination(event);handles({},false);
    if(!destination){hint.style.display='none';outline();return;}
    const d=destination, r=(d.beforeEl||d.parent).getBoundingClientRect();
    place(box,d.point?{x:r.x+d.parent.clientLeft+d.point.x-d.parent.scrollLeft,y:r.y+d.parent.clientTop+d.point.y-d.parent.scrollTop,width:16,height:16}:d.beforeEl?(d.horizontal?{x:r.left,y:r.top,width:3,height:r.height}:{x:r.left,y:r.top,width:r.width,height:3}):r);
    hint.textContent=label(d.parent)+' · '+d.layout+' · '+(d.point?Math.round(d.point.x)+', '+Math.round(d.point.y)+' px':d.beforeEl?'before '+label(d.beforeEl):'append');
    Object.assign(hint.style,{display:'block',left:Math.max(0,Math.min(event.clientX+8,innerWidth-210))+'px',top:Math.max(0,event.clientY-26)+'px'});
  },true);
  const clear=()=>{LayoutDrop.clear();destination=null;clearGuides();hint.style.display='none';outline();};
  window.addEventListener('dragleave',ev=>{if(!ev.relatedTarget)clear();});
  window.addEventListener('drop',async ev=>{
    ev.preventDefault();ev.stopImmediatePropagation();const d=toolDestination(ev);clear();if(!d)return;
    const where={id:d.id,before:d.before,point:d.point||null};
    const f=ev.dataTransfer.files[0];
    if(f){LayoutDrop.photo(f,where);return;}
    const item=ev.dataTransfer.getData('text/plain');if(item.startsWith('WebBench:'))post('drop',{...where,item:item.slice(9)});
  },true);
  function toolDestination(ev) {
    const target=document.elementFromPoint?.(ev.clientX,ev.clientY)||ev.target;
    const item=ev.dataTransfer?.getData?.('text/plain')?.replace(/^WebBench:/,'') || tool;
    const parts=item.split('/');
    const row=parts[0]==='Node' && parts[1]===WB.token ? WB.tree[Number(parts[2])] : null;
    const tag=row?.tag || WebBench.tagFor(item) || (ev.dataTransfer?.files?.length?'img':'div');
    const d=LayoutDrop.locate(target,ev.clientX,ev.clientY,free,null,tag);
    if(d?.point && snap && !ev.altKey) {
      d.point.x=Math.round(d.point.x/Arrange.grid)*Arrange.grid;d.point.y=Math.round(d.point.y/Arrange.grid)*Arrange.grid;
    }
    return d;
  }
  function showToolAt(ev) {
    handles({},false);box.style.display='none';hint.style.display='none';
    window.webBenchPaletteDrag(tool,'hover',ev.clientX/innerWidth,ev.clientY/innerHeight,free,snap&&!ev.altKey);
  }
  window.addEventListener('dblclick',event=>{
    if(tool)return;
    const snippet=event.target.closest?.('iframe,pre,div[data-html-snippet]');
    if(snippet && canMap(snippet)) {
      event.preventDefault();post('editSnippet',{id:key(snippet)});return;
    }
    const e=event.target.closest?.('p,h1,h2,h3,h4,h5,h6,li,td,th,figcaption,button,a,label,span,div');
    if(!e || !canMap(e))return;
    if(!e.textContent && !e.children.length){event.preventDefault();post('writeAt',{id:key(e),offset:0});return;}
    if(!e.textContent.trim())return;
    const caret=document.caretRangeFromPoint?.(event.clientX,event.clientY);
    if(!caret || caret.startContainer.nodeType!==Node.TEXT_NODE || !e.contains(caret.startContainer)){
      if(!e.children.length){event.preventDefault();post('writeAt',{id:key(e),offset:e.textContent.length});}
      return;
    }
    const leaf=caret.startContainer.parentElement.closest('['+marker+']');
    if(!leaf || !canMap(leaf))return;
    const r=document.createRange();r.selectNodeContents(leaf);r.setEnd(caret.startContainer,caret.startOffset);
    event.preventDefault();post('writeAt',{id:key(leaf),offset:r.toString().length});
  },true);
  function guidesFor(e,frame,rect) {
    const parent=e.parentElement, baseX=rect.x-frame.x,baseY=rect.y-frame.y;
    const x=[],y=[];
    for(const sibling of [parent,...parent.children]) {
      if(sibling===e || !sibling.getClientRects().length) continue;
      const r=sibling.getBoundingClientRect();
      x.push(r.left-baseX,r.left+r.width/2-baseX,r.right-baseX);
      y.push(r.top-baseY,r.top+r.height/2-baseY,r.bottom-baseY);
    }
    return {x,y};
  }
  function snapshots() {
    if(members.length<2||!members.every(e=>e.parentElement===selected.parentElement && movable(e)))
      throw new Error('Choose free-positioned siblings in a single container.');
    return members.map(element=>({...frameOf(element),id:key(element),element,
      rect:element.getBoundingClientRect(),original:element.getAttribute('style')}));
  }
  function previewMembers(frames,changes) {
    for(let i=0;i<frames.length;i++){
      const f=frames[i];restoreStyle(f);
      for(const [name,value] of Object.entries(changes[i].values))
        f.element.style.setProperty(name,value+'px',priority(f.element,name));
    }
  }
  function commitMembers(command,dx,dy,canvasFocus=false) {
    try {
      const frames=snapshots(),changes=Arrange.selection(frames,command,dx,dy);
      if(scoped && changes.some((c,i)=>Object.keys(c.values).some(k=>frames[i].element.style.getPropertyPriority(k)==='important')))
        throw new Error('An important inline declaration controls a selected object. Edit it at all widths or in Inspect.');
      if(!changes.some(c=>Object.keys(c.values).length))return;
      // Exercise every override together. Restore all members even on a failed measurement.
      try {
        previewMembers(frames,changes);
        for(let i=0;i<frames.length;i++) {
          const f=frames[i],v=changes[i].values,r=f.element.getBoundingClientRect(),base=f.rect;
          const near=(a,b)=>Math.abs(a-b)<0.06;
          if(!near(r.x,base.x+(v.left??f.x)-f.x)||!near(r.y,base.y+(v.top??f.y)-f.y)||
             !near(r.width,base.width)||!near(r.height,base.height))
            throw new Error('Page CSS constrains a selected layer. Inspect its controlling rule.');
        }
      } finally {frames.forEach(restoreStyle);}
      post('selectionFrames',{band:currentBand(),ids:memberIDs(),members:changes,command,canvasFocus,scroll:[scrollX,scrollY]});
    } catch(error){post('notice',{message:error.message});}
  }
  window.webBenchArrange=(ids,command,dx=0,dy=0)=>{
    if(sameIDs(ids))commitMembers(command,dx,dy);
  };
  function groupDrag(ev) {
    try {
      const frames=snapshots(),r=Arrange.bounds(frames);
      const parent=selected.parentElement,pr=parent.getBoundingClientRect();
      const ox=pr.x+parent.clientLeft-parent.scrollLeft,oy=pr.y+parent.clientTop-parent.scrollTop;
      const targets={x:[],y:[]};
      for(const e of [parent,...parent.children]){
        if(members.includes(e)||!e.getClientRects().length)continue;
        const b=e.getBoundingClientRect();
        targets.x.push(b.x-ox,b.x+b.width/2-ox,b.right-ox);
        targets.y.push(b.y-oy,b.y+b.height/2-oy,b.bottom-oy);
      }
      move={frames,element:selected,rect:r,x:r.x-ox,y:r.y-oy,w:r.width,h:r.height,targets,
        handle:'move',ptr:ev.pointerId,sx:ev.clientX,sy:ev.clientY,active:false};
    }catch(error){post('notice',{message:error.message});}
  }
  function groupDelta(m,result) {
    return [(result.values.left??m.x)-m.x,(result.values.top??m.y)-m.y];
  }
  function begin(ev,e,handle) {
    if(tool || !e || ev.button!==0 || !canMap(e))return;
    const frame=frameOf(e);
    if(handle==='move'?!frame.canMove:!frame.canResize)return;
    const rect=e.getBoundingClientRect();
    move={...frame,id:key(e),element:e,rect,handle,ptr:ev.pointerId,sx:ev.clientX,sy:ev.clientY,
      w:rect.width,h:rect.height,targets:guidesFor(e,frame,rect),active:false};
    if(handle!=='move'){
      ev.preventDefault();move.capture=ev.currentTarget;
      try{move.capture?.setPointerCapture(ev.pointerId);}catch{}
    }
  }
  function showFrame(m,result) {
    const v=result.values;
    // Restore the exact attribute before each preview so a locked axis or cancelled gesture leaves no residue.
    restoreStyle(m);
    if(m.inlineBox && (v.width!=null||v.height!=null))m.element.style.setProperty('display','inline-block',m.element.style.getPropertyPriority('display'));
    for(const [k,value] of Object.entries(v)) m.element.style.setProperty(k,value+'px',priority(m.element,k));
    const rect=m.element.getBoundingClientRect();
    place(box,rect);handles(rect,m.handle!=='move');clearGuides();
    if(result.guides.x!=null)place(gx,{x:m.rect.x-m.x+result.guides.x,y:0,width:1,height:innerHeight});
    if(result.guides.y!=null)place(gy,{x:0,y:m.rect.y-m.y+result.guides.y,width:innerWidth,height:1});
    const text=m.handle==='move'?`X ${v.left??m.x}   Y ${v.top??m.y}`:`${Math.round(rect.width)} × ${Math.round(rect.height)} px`;
    tip(text,rect.x,rect.y);
  }
  function applyFrame(id,values,canvasFocus=false) {
    const e=el(id);
    if(members.length>1 || !e || e!==selected || !canMap(e))return;
    const f=frameOf(e), base=e.getBoundingClientRect(), names=Object.keys(values);
    if(scoped && names.some(k=>e.style.getPropertyPriority(k)==='important')){
      post('notice',{message:'An important inline declaration controls this object. Edit it at all widths or in Inspect.'});return;
    }
    if(!names.length || (names.includes('z-index') && !f.canStack))return;
    if(names.some(k=>!Number.isInteger(values[k]) || Math.abs(values[k])>1000000 ||
       (['left','top','z-index'].includes(k) ? !f.canMove :
        !['width','height'].includes(k)||!f.canResize||values[k]<1)))return;
    // Measure the proposed inline override before asking Swift to patch the source.
    // Flex constraints, !important rules, min/max sizes and active transitions may defeat it.
    const original=e.getAttribute('style');
    let valid=false;
    const promote=f.inlineBox && (values.width!=null || values.height!=null);
    try {
      if(promote)e.style.setProperty('display','inline-block',e.style.getPropertyPriority('display'));
      for(const k of names)e.style.setProperty(k,String(values[k])+(k==='z-index'?'':'px'),priority(e,k));
      const r=e.getBoundingClientRect();
      const near=(a,b)=>Math.abs(a-b)<1.1;
      valid=near(r.x,base.x+(values.left??f.x)-f.x) && near(r.y,base.y+(values.top??f.y)-f.y);
      if(values.width!=null || values.left!=null) valid=valid&&near(r.width,base.width+(values.width??f.width)-f.width);
      if(values.height!=null || values.top!=null) valid=valid&&near(r.height,base.height+(values.height??f.height)-f.height);
      if(values['z-index']!=null)valid=valid&&Number(getComputedStyle(e).zIndex)===values['z-index'];
      // In flow, alignment can reposition a resized box. Its CSS dimensions are the requested output.
      if(!f.canMove && !names.some(k=>!['width','height'].includes(k)))
        valid=(values.width==null||near(r.width,base.width+values.width-f.width)) &&
              (values.height==null||near(r.height,base.height+values.height-f.height));
    } finally {
      if(original==null)e.removeAttribute('style');else e.setAttribute('style',original);
    }
    if(!valid){post('notice',{message:'The page CSS constrains this frame. Use the Inspect tab to edit the controlling rule.'});return;}
    post('frame',{id,values,band:currentBand(),promote,canvasFocus,scroll:[scrollX,scrollY]});
  }
  window.webBenchLift=id=>{
    const e=el(id);if(!e || e!==selected || !canMap(e))return;
    const f=frameOf(e);if(!f.canLift)return;
    const parent=e.parentElement, pr=parent.getBoundingClientRect(), r=e.getBoundingClientRect();
    const style=getComputedStyle(e), original=e.getAttribute('style');
    const values={left:Math.round(r.x-pr.x-parent.clientLeft+parent.scrollLeft-(parseFloat(style.marginLeft)||0)),
      top:Math.round(r.y-pr.y-parent.clientTop+parent.scrollTop-(parseFloat(style.marginTop)||0)),width:Math.max(1,Math.round(f.width))};
    let valid=false;
    try {
      e.style.setProperty('position','absolute',e.style.getPropertyPriority('position'));
      for(const [k,v] of Object.entries(values))e.style.setProperty(k,v+'px',e.style.getPropertyPriority(k));
      const after=e.getBoundingClientRect(), parentAfter=parent.getBoundingClientRect();
      valid=frameOf(e).canMove && ['x','y','width','height'].every(k=>Math.abs(after[k]-r[k])<1.1) &&
        ['width','height'].every(k=>Math.abs(parentAfter[k]-pr[k])<1.1);
    } finally {if(original==null)e.removeAttribute('style');else e.setAttribute('style',original);}
    if(valid)post('free',{id,values,scroll:[scrollX,scrollY]});
    else post('notice',{message:'This layer or its container would change size. Set a stable container size in Inspect, then try again.'});
  };
  // Native size sliders and pointer handles share the same reversible preview and commit path.
  let scrub=null;
  function cancelScrub(){
    if(!scrub)return;
    restoreStyle(scrub);scrub=null;hint.style.display='none';outline();
  }
  window.webBenchScrub=(id,axis,value,phase)=>{
    if(phase==='cancel'){cancelScrub();return;}
    if(!['width','height'].includes(axis)||!Number.isInteger(value)||value<1||value>1000000)return;
    if(!selected||key(selected)!==id||members.length!==1||move){cancelScrub();return;}
    if(scrub && (scrub.id!==id || scrub.axis!==axis))cancelScrub();
    if(!scrub){const f=frameOf(selected);if(!f.canResize)return;
      scrub={...f,id,axis,element:selected,rect:selected.getBoundingClientRect(),original:selected.getAttribute('style'),handle:'size'};}
    if(phase==='commit'){const changed=Math.round(scrub[axis])!==value;cancelScrub();if(changed)applyFrame(id,{[axis]:value});return;}
    showFrame(scrub,{values:{[axis]:value},guides:{}});
  };
  window.webBenchCenter=id=>{
    if(!selected||key(selected)!==id||!frameOf(selected).canMove)return;
    const f=frameOf(selected),r=selected.getBoundingClientRect();
    applyFrame(id,{left:Math.round(f.x+Math.max(0,(innerWidth-r.width)/2)-r.x),
      top:Math.round(f.y+Math.max(0,(innerHeight-r.height)/2)-r.y)});
  };
  window.webBenchFrame=applyFrame;
  window.addEventListener('pointerdown',ev=>{
    if(ev.target===chrome||tool)return;
    let e=ev.target.closest?.('['+marker+']');
    if(members.length>1 && members.some(m=>m.contains(e))){groupDrag(ev);return;}
    if(selected?.contains(e) && frameOf(selected).canMove)e=selected;
    else while(e && (!canMap(e)||!frameOf(e).canMove))e=e.parentElement?.closest('['+marker+']');
    if(e){begin(ev,e,'move');return;}
    const leaf=ev.target.closest?.('['+marker+']');
    const flow=leaf && /^(span|em|strong|b|i|small|sup|sub)$/.test(leaf.localName)
      ?leaf.closest('p,h1,h2,h3,h4,h5,h6,button,label,a,li,figcaption')||leaf:leaf;
    if(flow && canMap(flow)&&!['html','body','head','script','style'].includes(flow.localName) && !ev.metaKey && ev.button===0){
      move={flow:true,id:key(flow),element:flow,ptr:ev.pointerId,sx:ev.clientX,sy:ev.clientY,active:false};
    }
  },true);
  window.addEventListener('pointermove',ev=>{
    hover.style.display='none';
    if(tool){showToolAt(ev);return;}
    const m=move;
    if(!m){
      const e=ev.target.closest?.('['+marker+']');
      if(e&&!members.includes(e)&&!['html','body'].includes(e.localName)&&canMap(e))place(hover,e.getBoundingClientRect());
      return;
    }
    if(m.ptr!==ev.pointerId)return;
    const dx=ev.clientX-m.sx,dy=ev.clientY-m.sy;
    if(!m.active && Math.hypot(dx,dy)<3)return;
    if(m.flow){
      if(!m.active){setMembers([m.element]);try{m.element.setPointerCapture(ev.pointerId);}catch{}}
      m.active=true;ev.preventDefault();window.getSelection?.()?.removeAllRanges();
      LayoutDrop.clear();
      const d=LayoutDrop.locate(document.elementFromPoint(ev.clientX,ev.clientY),ev.clientX,ev.clientY,free,m.element,m.element.localName);
      if(d)LayoutDrop.show(d,null,ev.clientX,ev.clientY);
      return;
    }
    if(!m.active){
      if(!m.frames){setMembers([m.element]);m.original=m.element.getAttribute('style');}
      m.active=true;
      try{(m.capture||m.element).setPointerCapture(ev.pointerId);}catch{}
    }
    ev.preventDefault();
    const result=Arrange.gesture(m,dx,dy,{snap:snap&&!ev.altKey,shift:ev.shiftKey});
    if(!m.frames){showFrame(m,result);return;}
    const [tx,ty]=groupDelta(m,result);
    try {previewMembers(m.frames,Arrange.selection(m.frames,'move',tx,ty));}
    catch(error){cancelGesture();post('notice',{message:error.message});return;}
    drawSelection();clearGuides();
    if(result.guides.x!=null)place(gx,{x:m.rect.x-m.x+result.guides.x,y:0,width:1,height:innerHeight});
    if(result.guides.y!=null)place(gy,{x:0,y:m.rect.y-m.y+result.guides.y,width:innerWidth,height:1});
    tip(m.frames.length+' layers · Δ '+Math.round(tx)+', '+Math.round(ty)+' px',m.rect.x+tx,m.rect.y+ty);
  },true);
  window.addEventListener('dragstart',ev=>{if(move||tool)ev.preventDefault();},true);
  function restoreStyle(m) {
    if(m.original==null)m.element.removeAttribute('style');else m.element.setAttribute('style',m.original);
  }
  function cancelGesture(){
    const m=move;move=null;
    if(m?.flow)LayoutDrop.clear();
    if(m?.active&&!m.flow){if(m.frames)m.frames.forEach(restoreStyle);else restoreStyle(m);}
    const capture=m?.capture||m?.element;
    if(capture?.hasPointerCapture?.(m.ptr))capture.releasePointerCapture(m.ptr);
    clearGuides();hint.style.display='none';outline();
  }
  window.addEventListener('pointercancel',cancelGesture,true);
  window.addEventListener('blur',cancelGesture);
  window.addEventListener('pointerup',ev=>{
    const m=move;if(!m||m.ptr!==ev.pointerId)return;
    if(m.flow){
      cancelGesture();
      if(!m.active)return;
      ev.preventDefault();ignoreClick=true;setTimeout(()=>{ignoreClick=false;},0);
      const d=LayoutDrop.locate(document.elementFromPoint(ev.clientX,ev.clientY),ev.clientX,ev.clientY,free,m.element,m.element.localName);
      if(d)post('flowDrop',{id:d.id,child:m.id,before:d.before,point:d.point||null,scroll:[scrollX,scrollY]});
      return;
    }
    const result=Arrange.gesture(m,ev.clientX-m.sx,ev.clientY-m.sy,{snap:snap&&!ev.altKey,shift:ev.shiftKey});
    cancelGesture();
    if(!m.active)return;
    ev.preventDefault();ignoreClick=true;setTimeout(()=>{ignoreClick=false;},0);
    if(m.frames){commitMembers('move',...groupDelta(m,result),true);return;}
    applyFrame(m.id,result.values,true);
  },true);
  window.addEventListener('keydown',ev=>{
    if(ev.isComposing)return;
    if(ev.key==='Escape'){const wasDragging=!!move?.active;cancelGesture();if(!wasDragging && !tool && members.length>1)setMembers([selected]);if(tool){tool='';post('cancelTool');}clear();return;}
    if(selected && !ev.metaKey && !ev.ctrlKey && !ev.altKey && ['Delete','Backspace'].includes(ev.key)){
      ev.preventDefault();post('deleteLayers',{ids:memberIDs()});return;
    }
    if(!selected || ev.altKey || ev.metaKey || ev.ctrlKey || !frameOf(selected).canMove)return;
    const step=ev.shiftKey?10:1,f=frameOf(selected);
    if(members.length>1) {
      const direction={ArrowLeft:[-step,0],ArrowRight:[step,0],ArrowUp:[0,-step],ArrowDown:[0,step]}[ev.key];
      if(direction){ev.preventDefault();commitMembers('move',...direction,true);}
      return;
    }
    const delta={ArrowLeft:{left:Math.round(f.x-step)},ArrowRight:{left:Math.round(f.x+step)},
      ArrowUp:{top:Math.round(f.y-step)},ArrowDown:{top:Math.round(f.y+step)}}[ev.key];
    if(delta){ev.preventDefault();applyFrame(key(selected),delta,true);}
  },true);
  let resize;window.addEventListener('resize',()=>{clearTimeout(resize);resize=setTimeout(()=>inspect(),90);});
  window.addEventListener('scroll',()=>{gridOrigin();hover.style.display='none';outline();},true);
  window.addEventListener('pointerout',e=>{if(!e.relatedTarget){hover.style.display='none';if(tool)LayoutDrop.clear();}},true);
  if(Array.isArray(WB.scroll))window.scrollTo(...WB.scroll);
  post('ready');
})();
