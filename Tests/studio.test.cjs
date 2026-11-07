const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const engine=require('../Resources/source.js'),writing=require('../Resources/writing.js'),{gesture}=require('../Resources/arrange.js');
const asset=name=>fs.readFileSync(path.join(__dirname,'../Resources',name+'.html'),'utf8');
const id=(s,tag)=>engine.index(s).nodes.find(n=>n.tag===tag).id;
const blank=asset('canvas-page'),page=engine.run(blank,id(blank,'body'),{kind:'insert',item:'Button',point:{x:80,y:60}}).text;
test('the free page is genuinely blank, and a dropped part has authored coordinates directly under the body',()=>{
  const ix=engine.index(blank);assert.equal(ix.error,'');assert.ok(!ix.nodes.some(n=>n.parent===id(blank,'body')));
  const part=engine.index(page).nodes[id(page,'button')];
  assert.equal(part.parent,id(page,'body'));assert.match(part.attrs.style.value,/position: absolute; left: 80px; top: 60px/);
});
test('each of eight handles changes the requested axes and preserves the opposite positioned edge',()=>{
  const frame={width:100,height:50,x:20,y:15,w:104,h:54};
  for(const handle of ['n','e','s','w','ne','se','nw','sw']){
    const {values:v}=gesture({...frame,handle},12,8,{snap:false,shift:false});
    if(handle.includes('w'))assert.equal(v.left+v.width,120);
    if(handle.includes('n'))assert.equal(v.top+v.height,65);
    if(handle.includes('s'))assert.equal(v.height,58);
    if(handle.includes('e'))assert.equal(v.width,112);
    if(!/[ew]/.test(handle))assert.equal(v.width,undefined);
    if(!/[ns]/.test(handle))assert.equal(v.height,undefined);
  }
});
test('an inline element gains an editable box in the same patch as the first resize',()=>{
  const s="<p>See <a href='a' style='color: red'>notes</a><!--keep--></p>";
  const result=engine.run(s,1,{kind:'frame',promote:true,values:{width:140}});
  assert.equal(result.text,s.replace('color: red','color: red; display: inline-block; width: 140px;'));
});
test('phone positions override the base styles, repeated edits update one rule, other devices keep their layouts',()=>{
  const layer=id(page,'button');
  let s=engine.run(page,layer,{kind:'frame',band:'phone',values:{left:16,width:96}}).text;
  assert.equal(engine.index(s).nodes[layer].attrs.style.value,engine.index(page).nodes[layer].attrs.style.value);
  assert.match(s,/@media \(max-width: 600px\) \{\s*#wb-button-1 \{ left: 16px !important; width: 96px !important; \}/);
  s=engine.run(s,layer,{kind:'frame',band:'phone',values:{left:32}}).text;
  assert.ok(!s.includes('16px !important'));assert.equal((s.match(/@media \(max-width: 600px\)/g)||[]).length,1);
  s=engine.run(s,layer,{kind:'frame',band:'tablet',values:{height:52}}).text;
  assert.match(s,/min-width: 601px\) and \(max-width: 1024px\)/);assert.ok(s.includes('left: 32px !important'));
  assert.ok(!s.includes('!important !important'));assert.equal(engine.index(s).nodes[layer].attrs.id.value,'wb-button-1');
});
test('a group mobile layout updates the selected siblings in one source result',()=>{
  let s=engine.run(page,id(page,'body'),{kind:'insert',item:'Circle',point:{x:98,y:156}}).text;
  const a=id(s,'button'),b=id(s,'div');
  const op={kind:'selectionFrames',band:'phone',members:[{id:a,values:{left:24}},{id:b,values:{left:42}}]};
  const r=engine.run(s,a,op);
  assert.match(r.text,/#wb-button-1 \{ left: 24px !important/);assert.match(r.text,/#wb-div-1 \{ left: 42px !important/);
  assert.throws(()=>engine.run(s,a,{...op,band:'unknown'}));
  assert.throws(()=>engine.run(s,a,{...op,members:[op.members[0],{id:id(s,'head'),values:{left:4}}]}));
});
test('word colors, typeface and size use the same authored span without restyling adjacent text',()=>{
  const original="<p data-note='Ω'>Field &amp; <em>bench tools</em>.</p>\r\n<!-- keep -->";
  let s=original,a=s.indexOf('bench'),b=a+5;
  for(const [kind,value] of [['color','#BB2255'],['font-family','Avenir Next, sans-serif'],['font-size','24px']]){
    const e=writing.plan(s,engine.index(s).nodes,0,a,b,{kind,value});s=s.slice(0,e.start)+e.insert+s.slice(e.end);a=e.caret;b=e.endCaret;
    assert.equal(s.slice(a,b),'bench');
  }
  assert.equal(s,original.replace('bench','<span style="color: #BB2255; font-family: Avenir Next, sans-serif; font-size: 24px;">bench</span>'));
});
test('a caret changes the current block font and retains the logical text position',()=>{
  const s='<h2 id="x">A Ω</h2>',pos=s.indexOf('Ω'),e=writing.plan(s,engine.index(s).nodes,0,pos,pos,{kind:'font-family',value:'Georgia, serif'});
  const next=s.slice(0,e.start)+e.insert+s.slice(e.end);assert.equal(next[e.caret],'Ω');assert.equal(e.caret,e.endCaret);assert.match(next,/font-family: Georgia, serif/);
});
test('unsafe font declarations cannot escape the selected text or introduce rules',()=>{
  const s='<p>Test</p>';assert.throws(()=>writing.plan(s,engine.index(s).nodes,0,3,6,{kind:'font-family',value:'Georgia; color:red'}));
});
test('studio starter is a self-contained free canvas with embedded JPEG, live local links and responsive layout',()=>{
  const s=asset('studio'),ix=engine.index(s);assert.equal(ix.error,'');const body=ix.nodes[id(s,'body')];assert.ok(body.attrs['data-free-page']);
  const art=ix.nodes.find(n=>n.tag==='img');assert.equal(art.parent,body.id);const jpeg=Buffer.from(art.attrs.src.value.split(',')[1],'base64');assert.equal(jpeg.readUInt16BE(0),0xffd8);assert.equal(jpeg.readUInt16BE(jpeg.length-2),0xffd9);
  for(const link of ix.nodes.filter(n=>n.tag==='a'))assert.ok(ix.nodes.some(n=>'#'+n.attrs.id?.value===link.attrs.href.value));
  assert.match(s,/@media \(max-width: 700px\)/);assert.ok(!s.includes('src="http'));
});
