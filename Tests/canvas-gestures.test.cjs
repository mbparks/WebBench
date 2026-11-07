// Drive the production isolated-world listeners with a small DOM/geometry test double.
// Real WebKit and native undo are covered by the in-app sample checks on a Mac.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const marker = 'data-test-id';

function canvasFixture(photoBudget = 2 * 1024 * 1024) {
  const objects = [], messages = [], windowListeners = {};
  class Element {
    constructor(tag,id) {
      this.localName=tag; this.children=[];this.classList=[];this.attrs=new Map();this.listeners={};
      this.clientLeft=this.clientTop=this.scrollLeft=this.scrollTop=0;this.isConnected=true;this.textContent='';
      this.values={};this.style={
        getPropertyValue:k=>this.values[k] || '',getPropertyPriority:()=>'',removeProperty:k=>delete this.values[k],
        setProperty:(k,v)=>{this.values[k]=v;this.attrs.set('style',Object.entries(this.values).map(([p,w])=>p+': '+w+';').join(' '));}
      };
      if(id!=null){this.attrs.set(marker,String(id));objects[id]=this;}
    }
    remove(){
      if(this.parentElement){const a=this.parentElement.children;a.splice(a.indexOf(this),1);this.parentElement=null;}
    }
    insertBefore(e,ref){e.remove();e.parentElement=this;const at=this.children.indexOf(ref);
      if(at<0)this.children.push(e);else this.children.splice(at,0,e);}
    get parent(){return this.parentElement}
    hasAttribute(k){return this.attrs.has(k)}
    getAttribute(k){return this.attrs.get(k)??null}
    setAttribute(k,v){
      this.attrs.set(k,v);
      if(k==='style')this.values=Object.fromEntries(v.split(';').filter(x=>x.includes(':')).map(x=>x.split(':').map(t=>t.trim())));
    }
    removeAttribute(k){this.attrs.delete(k);if(k==='style')this.values={};}
    toggleAttribute(k,enabled){if(enabled)this.attrs.set(k,'');else this.attrs.delete(k);}
    addEventListener(type,fn){this.listeners[type]=fn}
    append(...children){for(const c of children){c.parentElement=this;this.children.push(c);}}
    appendChild(child){this.append(child)}
    attachShadow(){this.shadow=new Element('shadow');return this.shadow}
    closest(selector){
      if(selector==='['+marker+']' && this.attrs.has(marker))return this;
      if(selector==='[data-design-canvas]' && this.attrs.has('data-design-canvas'))return this;
      return this.parentElement?.closest(selector)??null;
    }
    matches(selector){return selector.split(',').includes(this.localName)}
    contains(e){return !!e && (e===this || this.contains(e.parentElement))}
    getBoundingClientRect(){
      const x=parseFloat(this.values.left)||0, y=parseFloat(this.values.top)||0;
      const w=Math.min(this.limit??Infinity,parseFloat(this.values.width)||640), h=parseFloat(this.values.height)||400;
      return {x,y,left:x,top:y,width:w,height:h,right:x+w,bottom:y+h};
    }
    getClientRects(){return [this.getBoundingClientRect()]}
    hasPointerCapture(){return false}
    setPointerCapture(){}
    scrollIntoView(){}
  }
  const html=new Element('html',0),head=new Element('head',1),body=new Element('body',2);
  const stage=new Element('main',3),box=new Element('div',4);
  html.append(head,body);body.append(stage);stage.append(box);stage.setAttribute('data-design-canvas','');
  stage.setAttribute('style','position: relative; isolation: isolate;');
  box.setAttribute('style','position:absolute; left: 24px; top: 32px; width: 80px; height: 40px;');
  box.offsetParent=stage;
  const second=new Element('button',5),third=new Element('p',6);
  for(const [e,x,y] of [[second,140,82],[third,270,160]]){
    stage.append(e);e.offsetParent=stage;e.setAttribute('style','position:absolute;left:'+x+'px;top:'+y+'px;width:64px;height:40px');
  }
  let hit=stage;
  const tree=objects.map((e,id)=>({id,tag:e.localName,parent:Number(e.parentElement?.getAttribute(marker)??-1)}));
  const document={documentElement:html,head,body,styleSheets:[],elementFromPoint:()=>hit,createElement:name=>{
      if(name!=='template')return new Element(name);
      return {content:{},set innerHTML(value){this.content.firstElementChild=new Element(/^<(\w+)/.exec(value)[1]);}};
    },
    querySelectorAll(selector){
      const m=selector.match(/="(\d+)"\]/);return m && objects[+m[1]] ? [objects[+m[1]]] : [];
    },
    querySelector(selector){return this.querySelectorAll(selector)[0]},getElementsByClassName(){return []}
  };
  const window={webkit:{messageHandlers:{design:{postMessage:m=>messages.push(JSON.parse(JSON.stringify(m)))}}},
    addEventListener:(type,fn)=>(windowListeners[type]??=[]).push(fn)};
  function css(e) {
    const r=e.getBoundingClientRect();
    return {transform:'none',zoom:'1',position:e.values.position||'static',display:e.values.display||'block',flexDirection:e.values['flex-direction']||'row',flexWrap:'nowrap',
      width:r.width+'px',height:r.height+'px',left:r.x+'px',top:r.y+'px',opacity:'1',
      isolation:e.values.isolation||'auto',zIndex:e.values['z-index']||'auto',fontSize:'16px',textAlign:'start',
      backgroundColor:'rgb(0, 0, 0)',color:'rgb(0, 0, 0)',getPropertyValue:key=>e.values[key]||''};
  }
  const js=['source','layout-drop','arrange','canvas'].map(name=>fs.readFileSync(path.join(__dirname,'../Resources',name+'.js'),'utf8')).join('\n');
  vm.runInNewContext(js,{window,document,WB:{token:'test',marker,tree,photoBudget},
    FileReader:class {readAsDataURL(blob){this.result='data:image/png;base64,'+blob.bytes.toString('base64');this.onload();}},getComputedStyle:css,
    innerWidth:640,innerHeight:400,scrollX:0,scrollY:0,setTimeout,clearTimeout});
  function fire(type,target,x,y,extra={}) {
    const ev={target,button:0,pointerId:1,clientX:x,clientY:y,altKey:true,preventDefault(){},stopImmediatePropagation(){},...extra};
    for(const fn of windowListeners[type]??[])fn(ev);
    target.listeners[type]?.(ev);
  }
  const chrome=html.children.find(e=>e.shadow);
  const handle=direction=>chrome.shadow.children.find(e=>e.style.cursor===direction+'-resize');
  return {window,box,stage,second,third,body,messages,fire,chrome,handle,setHit:e=>{hit=e;},grip:handle('se')};
}

test('pointer preview moves actual layer, restores authored DOM, and commits once at release',()=>{
  const {box,messages,fire}=canvasFixture(), original=box.getAttribute('style');
  fire('pointerdown',box,30,35);fire('pointermove',box,65,53);
  assert.equal(box.values.left,'59px');assert.equal(box.values.top,'50px');
  assert.equal(messages.filter(m=>m.kind==='frame').length,0);
  fire('pointerup',box,65,53);
  assert.equal(box.getAttribute('style'),original);
  assert.deepEqual(messages.filter(m=>m.kind==='frame').map(m=>m.values),[{left:59,top:50}]);
});
test('cancelling an active drag restores exact style and produces no source patch',()=>{
  const {box,messages,fire}=canvasFixture(), original=box.getAttribute('style');
  fire('pointerdown',box,30,35);fire('pointermove',box,65,53);fire('keydown',box,0,0,{key:'Escape'});
  fire('pointerup',box,65,53);assert.equal(box.getAttribute('style'),original);
  assert.ok(!messages.some(m=>m.kind==='frame'));
});
test('corner handle and constraint validation use the same path as numeric Arrange',()=>{
  const {window,box,grip,fire,messages}=canvasFixture();
  window.webBenchSelect(4,'width');
  fire('pointerdown',grip,104,72);fire('pointermove',box,120,80,{shiftKey:true});
  fire('pointerup',box,120,80,{shiftKey:true});
  assert.deepEqual(messages.at(-1).values,{width:96,height:48});
  box.limit=90;window.webBenchFrame(4,{width:250});
  assert.equal(messages.at(-1).kind,'notice');assert.equal(box.values.width,'80px');
});
test('click-to-place reports the board and the same snapped coordinates shown before commit',()=>{
  const {window,stage,messages,fire}=canvasFixture();
  window.webBenchTools('Box',true);fire('pointermove',stage,141,248,{altKey:false});
  fire('click',stage,141,248,{altKey:false});
  assert.deepEqual(messages.at(-1),{token:'test',kind:'place',id:3,before:null,point:{x:144,y:248},item:'Box',scroll:[0,0]});
});

test('an explicit conversion preserves the measured frame and restores the authored style before commit',()=>{
  const {window,box,messages}=canvasFixture();
  box.setAttribute('style','width: 80px; height: 40px;');
  window.webBenchSelect(4,'width');window.webBenchLift(4);
  assert.equal(box.getAttribute('style'),'width: 80px; height: 40px;');
  assert.equal(messages.at(-1).kind,'free');
  assert.deepEqual(messages.at(-1).values,{left:0,top:0,width:80});
});

test('modifier-click across canvas objects selects, toggles and keeps the first layer as anchor',()=>{
  const {window,box,second,third,stage,fire,messages}=canvasFixture();
  fire('click',box,30,35);fire('click',second,145,87,{metaKey:true});fire('click',third,273,162,{shiftKey:true});
  assert.deepEqual(messages.at(-1).ids,[4,5,6]);
  window.webBenchToggle(3);assert.equal(messages.at(-1).kind,'notice');
  window.webBenchArrange([4,5,6],'top');
  assert.deepEqual(messages.at(-1).members,[{id:4,values:{}},{id:5,values:{top:32}},{id:6,values:{top:32}}]);
  fire('click',box,31,35,{metaKey:true});assert.deepEqual(messages.at(-1).ids,[5,6]);
  fire('keydown',stage,0,0,{key:'Escape'});assert.equal(messages.at(-1).id,5);
});
test('group drag, cancellation and arrow nudges restore every original DOM attribute',()=>{
  const {window,box,second,third,fire,messages}=canvasFixture(),nodes=[box,second,third];
  const before=nodes.map(e=>e.getAttribute('style'));
  window.webBenchSelectMany([4,5,6],'width');
  fire('pointerdown',second,145,85);fire('pointermove',second,164,98);
  assert.deepEqual(nodes.map(e=>e.values.left),['43px','159px','289px']);
  fire('keydown',second,0,0,{key:'Escape'});fire('pointerup',second,164,98);
  assert.deepEqual(nodes.map(e=>e.getAttribute('style')),before);
  assert.equal(messages.filter(e=>e.kind==='selectionFrames').length,0);
  fire('pointerdown',second,145,85);fire('pointermove',second,164,98);fire('pointerup',second,164,98);
  assert.equal(messages.filter(e=>e.kind==='selectionFrames').length,1);
  assert.deepEqual(messages.at(-1).members.map(m=>m.values.left),[43,159,289]);
  fire('keydown',second,0,0,{key:'ArrowDown',altKey:false,shiftKey:true});
  assert.deepEqual(messages.at(-1).members.map(m=>m.values.top),[42,92,170]);
  assert.deepEqual(nodes.map(e=>e.getAttribute('style')),before);
});
test('native tile hover, cancellation and release share the CSS-pixel drop location',()=>{
  const {window,stage,second,messages,setHit}=canvasFixture();
  setHit(stage);window.webBenchPaletteDrag('Button','hover',.25,.5,false,true);
  const ghost=stage.children.at(-1);
  assert.equal(ghost.localName,'button');assert.equal(ghost.style.left,'160px');assert.equal(ghost.style.top,'200px');
  assert.ok(ghost.inert);assert.ok(!messages.some(m=>m.kind==='paletteDrop'));
  window.webBenchPaletteDrag('Button','cancel',0,0,false,true);assert.ok(!stage.children.includes(ghost));
  window.webBenchPaletteDrag('Button','drop',.25,.5,false,true);assert.deepEqual(messages.at(-1).point,{x:160,y:200});
  stage.removeAttribute('data-design-canvas');stage.values.display='flex';setHit(second);
  window.webBenchPaletteDrag('Button','hover',141/640,90/400,false,true);
  assert.equal(stage.children[1].inert,true);
  window.webBenchPaletteDrag('Button','drop',141/640,90/400,false,true);
  assert.equal(messages.at(-1).id,3);assert.equal(messages.at(-1).before,5);assert.equal(messages.at(-1).point,null);
});
test('directly dragging a flow item hits the release position even when the source holds pointer capture',()=>{
  const {box,stage,second,third,fire,messages,setHit}=canvasFixture();
  stage.removeAttribute('data-design-canvas');stage.values.display='grid';
  for(const e of [box,second,third])e.values.position='static';
  fire('pointerdown',third,280,170);setHit(second);fire('pointermove',third,141,90);fire('pointerup',third,141,90);
  const m=messages.at(-1);assert.deepEqual([m.kind,m.id,m.child,m.before,m.point],['flowDrop',3,6,5,null]);
});
test('a constrained group member rejects the whole drag and restores every style',()=>{
  const {box,second,window,messages}=canvasFixture();
  const before=[box,second].map(e=>e.getAttribute('style'));
  window.webBenchSelectMany([4,5],'width');
  const get=second.getBoundingClientRect.bind(second);
  second.getBoundingClientRect=()=>({...get(),x:140,left:140});
  window.webBenchArrange([4,5],'move',20,0);
  assert.equal(messages.at(-1).kind,'notice');assert.ok(!messages.some(m=>m.kind==='selectionFrames'));
  assert.deepEqual([box,second].map(e=>e.getAttribute('style')),before);
});

test('northwest grip resizes the visible box while held, then commits the opposite-edge anchor once',()=>{
  const {window,box,handle,fire,messages}=canvasFixture(), original=box.getAttribute('style');
  window.webBenchSelect(4,'width');
  fire('pointerdown',handle('nw'),24,32);fire('pointermove',box,13,25);
  assert.deepEqual([box.values.left,box.values.top,box.values.width,box.values.height],['13px','25px','91px','47px']);
  assert.ok(!messages.some(m=>m.kind==='frame'));
  fire('pointerup',box,13,25);
  assert.deepEqual(messages.filter(m=>m.kind==='frame').map(m=>m.values),[{left:13,top:25,width:91,height:47}]);
  assert.equal(box.getAttribute('style'),original);
});
test('size scrubbing previews several values, cancels exactly, and commits once for the chosen breakpoint',()=>{
  const {window,box,chrome,messages}=canvasFixture(), original=box.getAttribute('style');
  window.webBenchSelect(4,'width');window.webBenchScale(.5);window.webBenchVariant(true);
  assert.equal(chrome.values['--hit'],'44px');
  window.webBenchScrub(4,'width',110,'preview');window.webBenchScrub(4,'width',125,'preview');
  assert.equal(box.getBoundingClientRect().width,125);
  window.webBenchScrub(4,'width',125,'cancel');assert.equal(box.getAttribute('style'),original);
  assert.ok(!messages.some(m=>m.kind==='frame'));
  window.webBenchScrub(4,'width',150,'preview');window.webBenchScrub(4,'width',150,'commit');
  const edits=messages.filter(m=>m.kind==='frame');
  assert.equal(edits.length,1);assert.deepEqual(edits[0].values,{width:150});assert.equal(edits[0].band,'tablet');
  assert.equal(box.getAttribute('style'),original);
});
test('Page canvas explicitly bypasses nested containers for overlapping objects',()=>{
  const {window,body,second,messages,setHit}=canvasFixture();
  body.setAttribute('data-free-page','');body.setAttribute('style','position: relative;');
  window.webBenchDropOnPage(true);
  setHit(second);window.webBenchPaletteDrag('Button','drop',.25,.25,false,false);
  const m=messages.at(-1);assert.equal(m.id,2);assert.equal(m.before,null);
  assert.deepEqual(m.point,{x:160,y:100});
});

function testPhoto(name, count) {
  const bytes = Buffer.alloc(count);
  for (let i=0; i<bytes.length; i++) bytes[i] = i % 251;
  return {name, size: count, bytes, slice:(start, end)=>({bytes:bytes.subarray(start,end)})};
}
test('oversized Finder photo keeps its drop position and transfers exact bytes in bounded chunks',async()=>{
  const {window,stage,fire,messages}=canvasFixture();
  const file=testPhoto('field photo.JPG',2*1024*1024+73);
  fire('drop',stage,42,71,{dataTransfer:{files:[file]}});
  const m=messages.at(-1);
  assert.equal(m.kind,'photoFile'); assert.equal(m.size,file.size); assert.equal(m.id,3);
  assert.deepEqual(m.point,{x:42,y:71});
  const parts=[];
  for(let pos=0;pos<file.size;pos+=524288) {
    parts.push(Buffer.from(await window.webBenchPhotoPart(m.key,pos,Math.min(524288,file.size-pos)),'base64'));
  }
  assert.deepEqual(Buffer.concat(parts),file.bytes);
  await assert.rejects(window.webBenchPhotoPart(m.key,0,524289));
  fire('drop',stage,42,71,{dataTransfer:{files:[file]}});
  assert.equal(messages.at(-1).kind,'notice');
  window.webBenchReleasePhoto(m.key);
  await assert.rejects(window.webBenchPhotoPart(m.key,0,1));
  assert.equal(messages.filter(v=>v.kind==='asset').length,0);
});
test('folder budget keeps small JPEG bytes and routes non-web TIFF through photo tools',()=>{
  const {stage,fire,messages}=canvasFixture(12*1024*1024);
  const file=testPhoto('camera.jpg',2*1024*1024+1);
  fire('drop',stage,4,8,{dataTransfer:{files:[file]}});
  assert.equal(messages.at(-1).kind,'asset');
  assert.deepEqual(Buffer.from(messages.at(-1).data,'base64'),file.bytes);
  fire('drop',stage,4,8,{dataTransfer:{files:[testPhoto('photo.tiff',81)]}});
  assert.equal(messages.at(-1).kind,'photoFile');
  fire('drop',stage,4,8,{dataTransfer:{files:[testPhoto('notes.txt',20)]}});
  assert.equal(messages.at(-1).kind,'notice');
});

test('native palette drop and armed click choose the nested section inside a free canvas',()=>{
  const {window,body,box,messages,fire,setHit}=canvasFixture();
  body.setAttribute('data-free-page',''); body.setAttribute('style','position:relative');
  setHit(box);
  window.webBenchPaletteDrag('Button','drop',.10,.13,false,false);
  const drop=messages.at(-1);assert.equal(drop.id,4);assert.equal(drop.kind,'paletteDrop');
  assert.deepEqual(drop.point,{x:40,y:20});
  window.webBenchTools('Button',false);fire('click',box,64,52);
  const click=messages.at(-1);assert.equal(click.id,drop.id);assert.deepEqual(click.point,drop.point);
  fire('click',box,64,52);assert.equal(messages.at(-1).kind,'select');assert.equal(messages.at(-1).id,4);
});
test('positioned flex and grid containers keep normal insertion order inside a free page',()=>{
  for (const layout of ['flex','grid']) {
    const {window,body,box,messages,setHit}=canvasFixture();
    body.setAttribute('data-free-page','');box.values.display=layout;setHit(box);
    window.webBenchPaletteDrag('Paragraph','drop',.10,.13,true,false);
    assert.equal(messages.at(-1).id,4);assert.equal(messages.at(-1).point,null);
  }
});
