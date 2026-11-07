const test = require('node:test');
const assert = require('node:assert/strict');
const {gesture} = require('../Resources/arrange.js');
const engine = require('../Resources/source.js');
const start = {handle:'move',x:24,y:32,width:80,height:40,w:88,h:48,targets:{x:[],y:[]}};
test('free movement maps both axes in CSS coordinates',()=>{
  assert.deepEqual(gesture(start,35,18,{snap:false}).values,{left:59,top:50});
  assert.deepEqual(gesture(start,0,0,{snap:true}).values,{});
});
test('grid snapping leaves the stationary axis at its authored coordinate',()=>{
  assert.deepEqual(gesture({...start,y:31},19,0,{snap:true}).values,{left:40});
});
test('nearby sibling edges and centers take precedence over the grid',()=>{
  const g={...start,targets:{x:[131],y:[68]}};
  assert.deepEqual(gesture(g,17,10,{snap:true}),{values:{left:43,top:44},guides:{x:131,y:68}});
});
test('holding Shift constrains a move to its dominant axis',()=>{
  assert.deepEqual(gesture(start,-19,2,{snap:false,shift:true}).values,{left:5});
});
test('edge handles resize CSS dimensions independently of borders and padding',()=>{
  assert.deepEqual(gesture({...start,handle:'e'},15,30,{snap:false}).values,{width:95});
  assert.deepEqual(gesture({...start,handle:'s'},15,-60,{snap:false}).values,{height:1});
});
test('Shift on the corner preserves proportions after snapping',()=>{
  assert.deepEqual(gesture({...start,handle:'se'},18,2,{snap:true,shift:true}).values,{width:96,height:49});
});
const original = "<main>\r\n<!-- keep -->\r\n<div id='tool' style='left: 24px; --label: \"x;y\"; width: 80px !important; top: 32px'>Meter</div>\r\n</main>";
function frame(values,source=original) { return engine.run(source,1,{kind:'frame',values}).text; }
test('one frame patch keeps unrelated CSS, attribute quotes, priorities and CRLF',()=>{
  assert.equal(frame({left:59,top:50,width:96}),original.replace('24px','59px').replace('80px','96px').replace('32px','50px'));
  assert.equal(frame({left:24}),original);
});
test('stacking changes z-index without reordering or duplicating markup',()=>{
  const output=frame({'z-index':-1});
  assert.equal(output,original.replace("32px'>","32px; z-index: -1;'>"));
});
test('duplicate declarations and unsupported units safely reject the entire change',()=>{
  assert.throws(()=>frame({top:8,width:20},original.replace('width: 80px','width: 50%; width: 80px')),/Multiple fallback/);
  assert.throws(()=>frame({left:Infinity}),/valid/);
  assert.throws(()=>frame({height:0}),/valid/);
  assert.throws(()=>frame({width:'50%'}),/valid/);
  assert.throws(()=>frame({transform:3}),/valid/);
});
test('toolbar placement preserves shape styling and makes ordinary portable HTML',()=>{
  const s='<main data-design-canvas>\r\n<!-- board -->\r\n</main>';
  const added=engine.run(s,0,{kind:'insert',item:'Box',point:{x:48,y:64}});
  assert.equal(added.text,s.replace('</main>','<div style="width: 160px; height: 96px; background-color: #d8e6dc; position: absolute; left: 48px; top: 64px;"></div></main>'));
  assert.equal(added.focus,s.indexOf('</main>'));
  const flow=engine.run('<section><p>Keep</p></section>',0,{kind:'insert',item:'Text box',before:1});
  assert.equal(flow.text,'<section><p style="margin: 0;">Text box</p><p>Keep</p></section>');
});

test('adding a design area and freeing a layer do not convert the surrounding page',()=>{
  const s="<main><!-- keep --><div style='color: teal;'>Layer</div></main>";
  const free=engine.run(s,1,{kind:'free',values:{left:40,top:10,width:100}}).text;
  assert.equal(free,s.replace('color: teal;','color: teal; position: absolute; left: 40px; top: 10px; width: 100px;'));
  const area=engine.run(s,0,{kind:'insert',item:'Design area'}).text;
  assert.ok(area.includes('data-design-canvas'));
  assert.equal(area.slice(0,s.indexOf('</main>')),s.slice(0,s.indexOf('</main>')));
  const photo=engine.run(s,0,{kind:'asset',url:'art/test.svg',alt:'Meter',point:{x:8,y:16}}).text;
  assert.ok(photo.includes('width: 192px; height: auto; position: absolute; left: 8px; top: 16px;'));
});

test('dropping a layer into a board relocates its original fragment and applies its drop coordinates',()=>{
  const s="<main><p id='mark' style='color: teal;'>A &amp; B</p><!-- keep --><section data-design-canvas></section></main>";
  const markup="<p id='mark' style='color: teal; position: absolute; left: 16px; top: 48px;'>A &amp; B</p>";
  const moved=engine.run(s,2,{kind:'relocate',child:1,point:{x:16,y:48}}).text;
  assert.equal(moved,"<main><!-- keep --><section data-design-canvas>"+markup+"</section></main>");
  assert.equal(engine.run(moved,1,{kind:'relocate',child:2,point:{x:24,y:40}}).text,
    moved.replace('16px','24px').replace('48px','40px'));
});

const {selection,bounds}=require('../Resources/arrange.js');
const members=[
  {id:3,x:12,y:16,rect:{x:30,y:20,width:40,height:28}},
  {id:6,x:66.25,y:58,rect:{x:90,y:70,width:20,height:10}},
  {id:4,x:184,y:112,rect:{x:210,y:120,width:30,height:18}}
];
test('each alignment uses the reference border box and retains CSS origin offsets',()=>{
  for(const [command,key,axis,size,fraction] of [
    ['left','left','x','width',0],['centerX','left','x','width',.5],['right','left','x','width',1],
    ['top','top','y','height',0],['centerY','top','y','height',.5],['bottom','top','y','height',1]]){
    const edits=selection(members,command),anchor=members[0].rect;
    assert.deepEqual(edits[0].values,{});
    for(const [i,e] of edits.slice(1).entries()){
      const f=members[i+1],newEdge=f.rect[axis]+e.values[key]-f[axis]+f.rect[size]*fraction;
      assert.equal(newEdge,anchor[axis]+anchor[size]*fraction);
      assert.equal(Object.keys(e.values).length,1);
    }
  }
});
test('distribution preserves endpoints and handles uneven sizes in either axis',()=>{
  assert.deepEqual(selection(members,'spaceX').map(m=>m.values),[{}, {left:106.25}, {}]);
  assert.deepEqual(selection([...members].reverse(),'spaceY').map(m=>m.values),[{}, {top:67}, {}]);
  assert.throws(()=>selection(members.slice(0,2),'spaceX'),/three/);
  const crowded=members.map(f=>({...f,rect:{...f.rect,width:200}}));
  assert.throws(()=>selection(crowded,'spaceX'),/farther apart/);
});
test('translate applies one delta to every coordinate, without rounding each member to a grid',()=>{
  assert.deepEqual(bounds(members),{x:30,y:20,width:210,height:118});
  assert.deepEqual(selection(members,'move',2.5,0).map(m=>m.values),[{left:14.5},{left:68.75},{left:186.5}]);
  assert.ok(selection(members,'move',0,0).every(m=>!Object.keys(m.values).length));
});
const layout="<main>\r\n<p style='left: 110px; --x: \"a;b\"'>Ω</p><!-- keep -->\r\n<div id=b></div><p style='top:30px !important'>C</p></main>";
const group=(input,members)=>engine.run(input,members[0].id,{kind:'selectionFrames',members});
test('one source edit updates only affected values even when the selection is in reverse source order',()=>{
  const r=group(layout,[{id:3,values:{top:37}},{id:2,values:{left:6.5}},{id:1,values:{left:9}}]);
  const expected=layout.replace('110px','9px').replace('<div id=b','<div style="left: 6.5px;" id=b').replace('30px','37px');
  assert.equal(r.text,expected);assert.equal(r.focus,expected.lastIndexOf('<p'));
});
test('selection preflight rejects a bad last member without a partially edited result',()=>{
  const dirty=layout.replace('top:30px','top:0;top:30px');
  assert.throws(()=>group(dirty,[{id:1,values:{left:8}},{id:3,values:{top:2}}]),/Multiple/);
  for(const bad of [[{id:1,values:{}},{id:1,values:{}}],[{id:1,values:{}},{id:0,values:{}}],
    [{id:1,values:{}},{id:2,values:{width:15}}]])assert.throws(()=>group(layout,bad));
});
test('dropping a flow layer back into its original slot preserves even intervening comments',()=>{
  assert.equal(engine.run(layout,0,{kind:'relocate',child:1,before:2}).text,layout);
});
test('Delete removes only the selected markup, leaving whitespace and comments in place',()=>{
  const r=engine.run(layout,3,{kind:'deleteLayers',ids:[3,1]});
  assert.equal(r.text,"<main>\r\n<!-- keep -->\r\n<div id=b></div></main>");
  assert.throws(()=>engine.run(layout,0,{kind:'deleteLayers',ids:[0]}));
});
test('list-item drag retains a valid list parent and refuses a stray table cell',()=>{
  const s='<main><ul><li>A</li><li>B</li></ul><table><tbody><tr><td>V</td></tr></tbody></table></main>';
  assert.equal(engine.run(s,1,{kind:'relocate',child:3,before:2}).text,s.replace('<li>A</li><li>B</li>','<li>B</li><li>A</li>'));
  assert.throws(()=>engine.run(s,0,{kind:'relocate',child:3}),/specific container/);
  assert.throws(()=>engine.run(s,0,{kind:'relocate',child:7}),/specific container/);
});
