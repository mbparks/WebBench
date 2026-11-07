// Shared by the Select and Write canvases. Only the measured destination crosses the native bridge.
const LayoutDrop = (() => {
  const {marker,token}=WB;
  const key=e=>e?.hasAttribute?.(marker)?Number(e.getAttribute(marker)):-1;
  function mapped(e) {
    if(!e)return false;
    if(window.webBenchWritingMaps)return window.webBenchWritingMaps(e);
    for(let a=e;a;a=a.parentElement?.closest('['+marker+']')){
      const n=WB.tree[key(a)];
      if(!n || n.tag!==a.localName || n.parent!==key(a.parentElement?.closest('['+marker+']')) ||
         document.querySelectorAll('['+marker+'="'+n.id+'"]').length!==1)return false;
    }
    return true;
  }
  let dropOnPage=false;
  window.webBenchDropOnPage=value=>{ dropOnPage=Boolean(value); };
  function locate(hit,x,y,free,skip=null,tag='div') {
    let e=hit?.closest?.('['+marker+']');
    if(e?.localName==='html' && mapped(document.body))e=document.body;
    if(!e || skip?.contains(e))return null;
    const page=document.body?.hasAttribute('data-free-page')?document.body:null;
    const canContain=p=>WebBench.accepts(p.localName,tag) && mapped(p);
    let p=dropOnPage && page && !skip ? page : e;
    if(p===e && canContain(e) && e.localName!=='body' && !e.hasAttribute('data-design-canvas')) {
      const r=e.getBoundingClientRect(), outer=e.parentElement&&getComputedStyle(e.parentElement);
      const side=outer && (outer.display.includes('grid') || (outer.display.includes('flex')&&outer.flexDirection.startsWith('row')));
      const nearEdge=side?Math.min(x-r.left,r.right-x)<Math.min(7,r.width/5):Math.min(y-r.top,r.bottom-y)<Math.min(7,r.height/5);
      if(nearEdge && e.children.length && e.parentElement && canContain(e.parentElement))p=e.parentElement;
    }
    while(p && !canContain(p))p=p.parentElement;
    if(!p || skip?.contains(p))return null;
    const style=getComputedStyle(p);
    const board=p.closest('[data-design-canvas]') || page;
    if((board||free) && style.position!=='static' && !/flex|grid/.test(style.display) && WebBench.accepts(p.localName,'div')) {
      for(let a=p;a;a=a.parentElement){
        const css=getComputedStyle(a);
        if(css.transform!=='none'||['scale','rotate','translate','perspective'].some(k=>css[k]&&css[k]!=='none')||
          (css.zoom&&!['1','normal'].includes(css.zoom)))return null;
      }
      const r=p.getBoundingClientRect();
      return {id:key(p),before:null,parent:p,beforeEl:null,point:{x:x-r.x-p.clientLeft+p.scrollLeft,y:y-r.y-p.clientTop+p.scrollTop},layout:'absolute'};
    }
    while(e && e!==p && e.parentElement!==p)e=e.parentElement;
    const css=getComputedStyle(p), grid=css.display.includes('grid');
    const row=grid || (css.display.includes('flex')&&css.flexDirection.startsWith('row'));
    const reverse=row?(css.direction==='rtl')!==(css.flexDirection==='row-reverse'):css.flexDirection==='column-reverse';
    const kids=[...p.children].filter(k=>k!==skip && mapped(k) && k.getClientRects().length);
    function earlier(k){
      const b=k.getBoundingClientRect();
      if(row && (grid||css.flexWrap!=='nowrap')){
        if(y<b.top)return true;
        if(y>b.bottom)return false;
      }
      const delta=row?x-b.left-b.width/2:y-b.top-b.height/2;
      return reverse?delta>0:delta<0;
    }
    const index=kids.indexOf(e);
    let before=index===-1?kids.find(earlier):(earlier(e)?e:kids[index+1]);
    if(!before && p.localName==='figure' && tag!=='figcaption' && kids.length>1 && kids.at(-1).localName==='figcaption')before=kids.at(-1);
    return {id:key(p),before:before?key(before):null,parent:p,beforeEl:before||null,horizontal:row,reverse,layout:css.display};
  }
  let ghost=null, chrome=null,caption=null,line=null;
  function clear() {
    ghost?.remove();ghost=null;
    if(chrome)chrome.style.display='none';
  }
  function show(d,item,x,y) {
    if(!chrome){
      chrome=document.createElement('div');
      chrome.style.cssText='all:initial!important;position:fixed!important;inset:0!important;pointer-events:none!important;z-index:2147483647!important';
      chrome.setAttribute('aria-hidden','true');document.documentElement.appendChild(chrome);
      const root=chrome.attachShadow({mode:'closed'});line=document.createElement('div');caption=document.createElement('div');
      line.style.cssText='position:fixed;box-sizing:border-box;outline:2px solid #178162;background:#17816225;pointer-events:none';
      caption.style.cssText='position:fixed;padding:3px 7px;border-radius:4px;background:#124936;color:white;font:12px system-ui;pointer-events:none';
      root.append(line,caption);
    }
    chrome.style.display='block';
    let r=d.parent.getBoundingClientRect();
    if(item && Object.hasOwn(WebBench.palette,item)) {
      const template=document.createElement('template');template.innerHTML=WebBench.palette[item];
      ghost=template.content.firstElementChild;
      ghost.inert=true;ghost.setAttribute('aria-hidden','true');
      ghost.style.setProperty('pointer-events','none','important');
      if(item==='Image'){ghost.removeAttribute('src');ghost.alt='Image';ghost.style.width='120px';ghost.style.height='80px';}
      if(d.point){ghost.style.position='absolute';ghost.style.left=d.point.x+'px';ghost.style.top=d.point.y+'px';}
      d.parent.insertBefore(ghost,d.beforeEl||null);r=ghost.getBoundingClientRect();
    }else if(!d.point) {
      const last=[...d.parent.children].filter(k=>mapped(k)&&k.getClientRects().length).at(-1);
      const ref=d.beforeEl||last;
      if(ref){
        const b=ref.getBoundingClientRect(),end=(!d.beforeEl)!==d.reverse;
        r=d.horizontal?{x:end?b.right:b.left,y:b.top,width:2,height:b.height}:
          {x:b.left,y:end?b.bottom:b.top,width:b.width,height:2};
      }
    }
    Object.assign(line.style,{left:r.x+'px',top:r.y+'px',width:Math.max(2,r.width)+'px',height:Math.max(2,r.height)+'px'});
    const name=e=>e.localName+(e.id?'#'+e.id:'');
    caption.textContent='Inside '+name(d.parent)+(d.beforeEl?' · before '+name(d.beforeEl):d.point?' · free placement':' · at end');
    Object.assign(caption.style,{left:Math.max(0,Math.min(x+9,innerWidth-150))+'px',top:Math.max(0,y-28)+'px'});
  }
  function hit(x,y){return document.elementFromPoint(x,y);}
  window.webBenchPaletteDrag=(item,phase,u,v,free,snap)=>{
    clear();
    if(phase==='cancel'||u<0||v<0||u>=1||v>=1)return;
    const x=u*innerWidth,y=v*innerHeight,d=locate(hit(x,y),x,y,free,null,WebBench.tagFor(item));
    if(!d){
      if(phase==='drop')window.webkit.messageHandlers.design.postMessage({kind:'notice',token,message:'Drop inside a page container.'});
      return;
    }
    if(d.point && snap){d.point.x=Math.round(d.point.x/8)*8;d.point.y=Math.round(d.point.y/8)*8;}
    if(phase==='drop'){
      window.webkit.messageHandlers.design.postMessage({kind:'paletteDrop',token,item,id:d.id,before:d.before,point:d.point||null,scroll:[scrollX,scrollY]});
    }else show(d,item,x,y);
  };
  let pendingPhoto=null;
  window.webBenchReleasePhoto=key=>{if(pendingPhoto?.key===key)pendingPhoto=null;};
  window.webBenchPhotoPart=async(key,offset,length)=>{
    if(pendingPhoto?.key!==key || !Number.isSafeInteger(offset)||offset<0||!Number.isSafeInteger(length)||length<1||length>524288)throw Error('Expired photo drop.');
    const blob=pendingPhoto.file.slice(offset,offset+length);
    return await new Promise((resolve,reject)=>{const reader=new FileReader();
      reader.onload=()=>resolve(reader.result.split(',')[1]);reader.onerror=()=>reject(Error('Cannot read the photo.'));reader.readAsDataURL(blob);});
  };
  function photo(file, where, stillCurrent=()=>true) {
    const send = (kind, values) => window.webkit.messageHandlers.design.postMessage({token,kind,...values});
    const raster = /\.(png|jpe?g|gif|webp|avif|heic|heif|tiff?|bmp)$/i.test(file.name);
    if (raster && (file.size > (WB.photoBudget || 12*1024*1024) || /\.(heic|heif|tiff?|bmp)$/i.test(file.name))) {
      if (pendingPhoto) { send('notice',{message:'Finish the current photo import first.'}); return; }
      const key = String(Date.now())+'-'+Math.random();
      pendingPhoto = {key,file};
      send('photoFile',{...where,key,name:file.name,size:file.size});
      return;
    }
    if (!raster && (!/\.svg$/i.test(file.name) || file.size > 12*1024*1024)) {
      send('notice',{message:'Choose a supported photo or a smaller SVG.'});
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      if (stillCurrent()) send('asset',{...where,name:file.name,data:reader.result.split(',')[1]});
      else send('notice',{message:'The insertion point moved. Drop the photo again.'});
    };
    reader.onerror = () => send('notice',{message:'The photo could not be read. Choose it again.'});
    reader.readAsDataURL(file);
  }
  return {locate,clear,show,photo};
})();
