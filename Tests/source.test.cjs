const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),w=require('../Resources/source.js');
const fixture=fs.readFileSync(path.join(__dirname,'../Fixtures/Site/index.html'),'utf8');
const select=(s,label)=>w.info(s).nodes.find(n=>n.label===label).id;
test('temporary instrumentation preserves every original source unit when removed',()=>{
 const s='\ufeff<!doctype HTML>\r\n<!-- 🔧 -->\r\n<main data-test = \'a>b\'><script>const x="<b>";</script><p>e\u0301</p></main>';
 const r=w.info(s,'data-unique');assert.equal(r.error,'');assert.equal(r.html.replace(/ data-unique="\d+"/g,''),s);
 assert.equal(r.nodes.length,3);assert.equal(s.slice(r.nodes[2].start,r.nodes[2].start+3),'<p>');
});
test('small visual text and attribute changes have exact diffs',()=>{
 const s="<h1 class = 'hero'>Voltage &amp; current</h1>\r\n<!-- keep -->";
 assert.equal(w.run(s,0,{kind:'text',value:'Power <W>'}).text,s.replace('Voltage &amp; current','Power &lt;W&gt;'));
 assert.equal(w.run(s,0,{kind:'attr',key:'class',value:'display'}).text,s.replace('hero','display'));
});
test('ambiguous input enters source fallback',()=>{
 for(const s of ['<p title="oops>','<main><em>x</main>','<!-- unterminated','<a ID="x" id="y"></a>'])assert.ok(w.info(s).error);
 assert.throws(()=>w.run('<p>left <em>right</em></p>',0,{kind:'text',value:'drop contents'}));
 assert.throws(()=>w.run('<svg><g></g></svg>',1,{kind:'attr',key:'class',value:'a'}));
 assert.throws(()=>w.run('<button value></button>',0,{kind:'attr',key:'value',value:'a'}));
});
test('flow insertion, reorder, and relocation preserve intervening bytes',()=>{
 const s='<main><div><i>A</i>\n  <b>B</b></div><section></section></main>';
 const r=w.run(s,1,{kind:'insert',item:'Button',before:3});assert.equal(r.text,s.replace('<b>','<button type="button">Button</button><b>'));
 assert.equal(w.run(s,3,{kind:'reorder',step:-1}).text,s.replace('<i>A</i>\n  <b>B</b>','<b>B</b>\n  <i>A</i>'));
 assert.equal(w.run(s,4,{kind:'relocate',child:3}).text,s.replace('<b>B</b>','').replace('<section>','<section><b>B</b>'));
 assert.throws(()=>w.run(s,1,{kind:'relocate',child:0}));
});
test('positioned insertion and workbench coordinate patch',()=>{
 const id=select(fixture,'div#meter');const r=w.run(fixture,id,{kind:'move',x:55,y:71});
 assert.equal(r.text,fixture.replace('left: 24px; top: 32px','left: 55px; top: 71px'));
 const b=w.run(fixture,select(fixture,'div#bench'),{kind:'insert',item:'Button',point:{x:98.9,y:10}});
 assert.ok(b.text.includes('<button style="position: absolute; left: 99px; top: 10px;" type="button">'));
});
test('breakpoint rule edits only the intended CSS range',()=>{
 const s=fs.readFileSync(path.join(__dirname,'../Fixtures/Site/css/bench.css'),'utf8');
 const r=w.replaceRule(s,{styleIndex:-1,path:[7,0],selector:'.control',prop:'margin-top',value:'11px'});
 assert.equal(r,s.replace('margin-top: 2px','margin-top: 11px'));
 assert.throws(()=>w.replaceRule(s,{styleIndex:-1,path:[0],selector:'wrong',prop:'color',value:'red'}));
});
test('CSS preserves other declarations, comments, priority and URL punctuation',()=>{
 const s='/* pre */ .c { background: url("a;b"); /* author */ color : red !important; }';
 assert.equal(w.replaceRule(s,{styleIndex:-1,path:[0],selector:'.c',prop:'color',value:'blue'}),s.replace('red','blue'));
 assert.throws(()=>w.replaceRule('.c { color:red; color:green }',{styleIndex:-1,path:[0],selector:'.c',prop:'color',value:'blue'}));
});
test('element-scoped breakpoint assigns one ID and contains width',()=>{
 const s='<html><head></head><body><button>Read</button></body></html>';
 const r=w.style(s,3,{prop:'margin-top',value:'8px',mobile:true,width:540});assert.match(r.text,/@media \(max-width: 540px\)/);
 assert.equal(r.text.slice(r.focus,r.focus+7),'<button');assert.match(r.text,/<button id="wb-button-1">/);
});
test('shared class external override leaves HTML untouched',()=>{
 const r=w.style(fixture,select(fixture,'button.control'),{prop:'gap',value:'8px',selector:'.control',mobile:true,width:600,external:true,css:'/* original */'});
 assert.equal(r.text,fixture);assert.ok(r.css.startsWith('/* original */\n@media'));
});
test('click wiring is one undoable source result, inline handler navigates without mutation',()=>{
 const s='<html><body><button>Read</button></body></html>';
 const r=w.run(s,2,{kind:'handler'});assert.match(r.text,/id="wb-button-1"/);
 assert.ok(r.text.slice(r.range[0],r.range[0]+r.range[1]).startsWith('// Write the click action'));
 const inline='<button onclick="doMath()">Read</button>';const found=w.run(inline,0,{kind:'handler'});
 assert.equal(found.text,inline);assert.equal(inline.substr(...found.range),'doMath()');
});
test('asset references are escaped in source',()=>{
 const r=w.run('<main></main>',0,{kind:'asset',url:'../art/tool.svg',alt:'Meter "A" & B'});
 assert.equal(r.text,'<main><img src="../art/tool.svg" alt="Meter &quot;A&quot; &amp; B"></main>');
});

test('optional HTML endings map safely while invalid nesting stays in Code',()=>{
 const s='<html><body><ul><li>One<li>Two</ul><p>End';
 const ix=w.info(s);assert.equal(ix.error,'');assert.equal(w.run(s,3,{kind:'text',value:'First'}).text,s.replace('One','First'));
 assert.throws(()=>w.run(s,3,{kind:'reorder',step:1}));
});
test('inline CSS change retains unrelated literal quotes',()=>{
 const s=`<div style="font-family: 'IBM Plex Mono'; left: 8px;"></div>`;
 assert.equal(w.run(s,0,{kind:'inline',prop:'left',value:'10px'}).text,s.replace('8px','10px'));
});

test('moving a positioned object preserves every byte between the coordinate values',()=>{
 const s=`<div style="left: 24px; /* maker's note */ font-family:'Desk'; top: 32px;"></div>`;
 assert.equal(w.run(s,0,{kind:'move',x:59,y:50}).text,s.replace('24px','59px').replace('32px','50px'));
});
