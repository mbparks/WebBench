// Generate a self-contained browser geometry check. Native AppKit/WKWebView checks live in SampleChecks.swift.
const fs=require('node:fs'),path=require('node:path');
const resources=path.join(__dirname,'../Resources');
const engine=require(path.join(resources,'source.js'));
const fixture='<!doctype html><html><head><style>*{box-sizing:border-box}body{margin:0;font:16px system-ui}main{padding:24px}#row{display:flex;gap:16px;padding:12px;border:1px solid #ccc}#board{position:relative;height:160px;margin-top:12px;background:#edf4ed}#board button{position:absolute;width:50px;height:30px}</style></head><body><main><section id="row"><p id="one">Meter</p><p id="two">Scope</p></section><!-- preserve --><section id="board" data-design-canvas><button id="a" style="left:10px;top:20px">A</button><button id="b" style="left:80px;top:40px">B</button><button id="c" style="left:230px;top:60px">C</button></section></main></body></html>';
const sources=Object.fromEntries(['source','layout-drop','arrange','canvas','writing','document'].map(name=>[name,fs.readFileSync(path.join(resources,name+'.js'),'utf8')]));
const json=value=>JSON.stringify(value).replace(/</g,'\\u003c');
function checkPage() {
  let draft=original,messages=[],w,d;
  const frame=document.querySelector('iframe'),results=document.querySelector('pre');
  const yes=(ok,reason)=>{if(!ok)throw new Error(reason);results.textContent+='PASS  '+reason+'\n';};
  async function render(writeTarget) {
    const parsed=WebBench.info(draft,'data-wb-test');
    const options={token:'browser',marker:'data-wb-test',tree:parsed.nodes,source:draft,writeTarget};
    const pieces=writeTarget?['source','layout-drop','writing','document']:['source','layout-drop','arrange','canvas'];
    const code='const WB='+JSON.stringify(options)+';window.webkit={messageHandlers:{design:{postMessage:m=>parent.collect(m)}}};'+pieces.map(k=>scripts[k]).join('\n');
    const loaded=new Promise(resolve=>frame.onload=resolve);
    frame.srcdoc=parsed.html.replace('</body>','<script>'+code.replace(/<\/script/gi,'<\\/script')+'</'+'script></body>');
    await loaded;w=frame.contentWindow;d=frame.contentDocument;
    if(!messages.some(m=>m.kind==='ready'))throw Error('Canvas did not initialize.');
  }
  window.collect=m=>messages.push(m);
  function last(kind){const m=messages.filter(e=>e.kind===kind).at(-1);if(!m)throw Error('Missing '+kind);return m;}
  function pos(e,edge=false){const r=e.getBoundingClientRect();return [edge?r.left+1:r.x+r.width/2,r.y+r.height/2];}
  function pointer(e,type,x,y){e.dispatchEvent(new w.PointerEvent(type,{bubbles:true,cancelable:true,button:0,pointerId:3,clientX:x,clientY:y,altKey:true}));}
  function drag(item,phase,x,y){w.webBenchPaletteDrag(item,phase,x/w.innerWidth,y/w.innerHeight,false,false);}
  (async()=>{
    await render();
    const target=pos(d.querySelector('#two'),true);
    drag('Button','hover',...target);
    yes(d.querySelector('#one').nextElementSibling.matches('button[inert]') && !messages.some(m=>m.kind==='paletteDrop'),'Palette hover renders a button between the two flex children without a source edit');
    drag('Button','cancel',0,0);
    yes(!d.querySelector('#row button'),'Cancelling removes the preview');
    drag('Button','hover',...target);drag('Button','drop',...target);
    let m=last('paletteDrop');
    draft=WebBench.run(draft,m.id,{kind:'insert',item:m.item,before:m.before,point:m.point}).text;
    const button='<button type="button">Button</button>';
    yes(draft===original.replace('<p id="two">',button+'<p id="two">'),'Drop emits a single exact insertion at the previewed slot');
    await render();
    const b=d.querySelector('#row button'),p=pos(d.querySelector('#one'),true);
    pointer(b,'pointerdown',...pos(b));pointer(b,'pointermove',...p);pointer(b,'pointerup',...p);
    m=last('flowDrop');
    draft=WebBench.run(draft,m.id,{kind:'relocate',child:m.child,before:m.before,point:m.point}).text;
    yes(draft===original.replace('<p id="one">',button+'<p id="one">'),'Dragging the rendered button before Meter preserves all other source');
    await render();
    const label=d.querySelector('#row button'),[x,y]=pos(label);
    label.dispatchEvent(new w.MouseEvent('dblclick',{bubbles:true,clientX:x,clientY:y}));
    m=last('writeAt');await render([m.id,m.offset]);
    const host=d.querySelector('#row button');
    yes(d.activeElement===host,'Double-click gives the rendered button label a typing caret');
    const range=d.createRange();range.selectNodeContents(host);w.getSelection().removeAllRanges();w.getSelection().addRange(range);
    host.dispatchEvent(new w.InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertText',data:'Measure'}));
    m=last('write');draft=draft.slice(0,m.start)+m.value+draft.slice(m.start+m.old.length);
    yes(host.textContent==='Measure'&&draft.includes('>Measure</button>'),'Typing changes the visible label and its corresponding source');
    await render();
    for(const [i,id] of ['a','b','c'].entries())d.getElementById(id).dispatchEvent(new w.MouseEvent('click',{bubbles:true,metaKey:i>0}));
    const ids=last('multiSelect').ids;
    w.webBenchArrange(ids,'spaceX');m=last('selectionFrames');
    const spaced=WebBench.run(draft,ids[0],{kind:'selectionFrames',members:m.members}).text;
    yes(spaced===draft.replace('left:80px','left:120px'),'Equal spacing changes only the middle layer coordinate');
    const a=d.querySelector('#a'),pa=pos(a);
    pointer(a,'pointerdown',...pa);pointer(a,'pointermove',pa[0]+19,pa[1]+11);
    yes(a.style.left==='29px'&&d.querySelector('#b').style.left==='99px','Dragging a selection moves the rendered objects together');
    pointer(a,'pointerup',pa[0]+19,pa[1]+11);m=last('selectionFrames');
    yes(a.style.left==='10px'&&m.members.every(v=>Object.keys(v.values).length===2),'Release restores preview styles and submits one multi-layer edit');
    results.textContent+='COMPLETE';
  })().catch(error=>{results.textContent+='FAIL  '+error.message;});
}
if(!process.argv[2])throw Error('Supply a destination HTML path.');
fs.writeFileSync(process.argv[2],'<!doctype html><html><meta charset="utf-8"><title>WebBench canvas checks</title><style>body{font:15px system-ui;margin:24px}iframe{width:720px;height:300px;border:1px solid #777}pre{white-space:pre-wrap;line-height:1.5}</style><h1>WebBench canvas checks</h1><iframe title="Rendered test document"></iframe><pre></pre><script>'+sources.source.replace(/<\/script/gi,'<\\/script')+'\nconst scripts='+json(sources)+',original='+json(fixture)+';('+checkPage.toString()+')();</script></html>');
