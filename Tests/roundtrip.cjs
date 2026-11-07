// End-to-end source and disk checks without a browser. The script harness uses a DOM test double.
const fs=require('node:fs'), os=require('node:os'), path=require('node:path'), cp=require('node:child_process');
const crypto=require('node:crypto'), vm=require('node:vm'), assert=require('node:assert/strict');
const engine=require('../Resources/source.js'),root=path.resolve(__dirname,'..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'WebBench-QA-'));
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(x=>x.isDirectory()?walk(path.join(dir,x.name)):[path.join(dir,x.name)]).sort();}
function hashes(dir){return Object.fromEntries(walk(dir).map(p=>[path.relative(dir,p),crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex')]));}
function execute(file,edits={}){
 const args=[file];
 for(const [i,[name,text]] of Object.entries(edits).entries()){
   const staged=path.join(tmp,'edit-'+i);fs.writeFileSync(staged,text);args.push(name,staged);
 }
 cp.execFileSync(path.join(tmp,'probe'),args);
}
function read(p){return fs.readFileSync(p,'utf8');}
function pick(s,label){return engine.info(s).nodes.find(n=>n.label===label).id;}
class Element extends EventTarget {
 constructor(){super();this.style={left:'0px',top:'0px'};this.textContent='';this.children=[];this.valueAsNumber=0;}
 get offsetLeft(){return parseInt(this.style.left);}
 get offsetTop(){return parseInt(this.style.top);}
 append(...nodes){this.children.push(...nodes);}
}
function runtime(ids,script){
 const elements=Object.fromEntries(ids.map(id=>[id,new Element()]));
 const window=new EventTarget(), document={getElementById:id=>elements[id],createElement:()=>new Element()};
 vm.runInNewContext(script,{window,document,console:{log(){},info(){}}});
 return {elements,window};
}
function emit(target,type,properties={}){target.dispatchEvent(Object.assign(new Event(type),properties));}
try{
 cp.execFileSync('swiftc',[path.join(root,'Sources/Project.swift'),path.join(__dirname,'StorageProbe.swift'),'-o',path.join(tmp,'probe')]);
 const fixtures=path.join(tmp,'Fixtures');fs.cpSync(path.join(root,'Fixtures'),fixtures,{recursive:true});
 const site=path.join(fixtures,'Site'),single=path.join(fixtures,'Field-Instrument.html'),html=path.join(site,'index.html'),css=path.join(site,'css/bench.css');
 const baseline=hashes(fixtures);
 execute(single);execute(site);assert.deepEqual(hashes(fixtures),baseline);
 console.log('PASS no-op SHA-256 and reopen for all '+Object.keys(baseline).length+' original files');console.log(JSON.stringify(baseline,null,2));
 const writing=require('../Resources/writing.js');
 const draft=path.join(tmp,'writing.html');
 const originalDraft="<!doctype html>\r\n<p id='readout'>Main &amp; auxiliary</p>\r\n<!-- retain -->";
 fs.writeFileSync(draft,Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(originalDraft)]));
 let current=originalDraft;
 function writeAt(a,b,op) {
   const ix=engine.index(current), host=ix.nodes.findLast(n=>n.tag==='p' && n.open<=a && b<=n.close);
   const e=writing.plan(current,ix.nodes,host.id,a,b,op);
   current=current.slice(0,e.start)+e.insert+current.slice(e.end);
   return e.caret;
 }
 const start=current.indexOf('auxiliary');
 writeAt(start,start+9,{kind:'bold'});
 const end=current.indexOf('</p>');
 let caret=writeAt(end,end,{kind:'paragraph'});
 caret=writeAt(caret,caret,{kind:'text',value:'Load <20 Ω'});
 writeAt(caret,caret,{kind:'element',value:'button'});
 execute(draft,{'writing.html':current});execute(draft);
 const expected=originalDraft.replace('auxiliary</p>','<strong>auxiliary</strong></p>\r\n<p>Load &lt;20 Ω<button type="button">Button</button></p>');
 assert.deepEqual(fs.readFileSync(draft),Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(expected)]));
 console.log('PASS document formatting, Return, typing and caret insertion → exact UTF-8 BOM/CRLF save and reopen');
 const board=path.join(tmp,'Studio-board.html'), boardOriginal=read(path.join(root,'Resources/board.html'));
 fs.writeFileSync(board,boardOriginal);execute(board);
 assert.deepEqual(fs.readFileSync(board),Buffer.from(boardOriginal));
 const parent=engine.index(boardOriginal).nodes.find(n=>n.tag==='main');
 const layer=engine.run(boardOriginal,parent.id,{kind:'insert',item:'Box',point:{x:48,y:64}});
 const boxId=engine.index(layer.text).nodes.find(n=>n.start===layer.focus).id;
 const arranged=engine.run(layer.text,boxId,{kind:'frame',values:{left:100,width:200,height:120,'z-index':2}});
 const expectedBoard=boardOriginal.replace('</main>','<div style="width: 200px; height: 120px; background-color: #d8e6dc; position: absolute; left: 100px; top: 64px; z-index: 2;"></div></main>');
 execute(board,{'Studio-board.html':arranged.text});execute(board);
 assert.deepEqual(fs.readFileSync(board),Buffer.from(expectedBoard));
 console.log('PASS design canvas no-op, object placement, resize, stacking and exact saved/reopened HTML');
 const spread=path.join(tmp,'Tools.html');
 const authored="<main style='position:relative'>\r\n<button style='position:absolute;left:24px;top:8px'>Ω</button><!-- keep -->\r\n<a href='notes.html' style='position:absolute;left:90px;top:70px'>Notes</a></main>";
 fs.writeFileSync(spread,Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(authored)]));
 const grouped=engine.run(authored,2,{kind:'selectionFrames',members:[{id:2,values:{left:99.5}},{id:1,values:{left:33.5}}]}).text;
 execute(spread,{'Tools.html':grouped});execute(spread);
 assert.deepEqual(fs.readFileSync(spread),Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(authored.replace('24px','33.5px').replace('90px','99.5px'))]));
 console.log('PASS two-layer translation preserves exact BOM, CRLF, link, Unicode and comment after disk save/reopen');
 const paper=read(path.join(root,'Resources','canvas-page.html')), doc=path.join(tmp,'canvas.html'),snapshot=path.join(tmp,'Published');
 fs.writeFileSync(doc,paper);
 let made=engine.run(paper,pick(paper,'body'),{kind:'insert',item:'Button',point:{x:288,y:192}}).text;
 const button=pick(made,'button');
 for(const [prop,value] of [['font-family','Georgia, serif'],['color','#fc8844']]){
   made=engine.run(made,button,{kind:'inline',prop,value}).text;
 }
 made=engine.run(made,button,{kind:'frame',values:{width:186,height:64}}).text;
 made=engine.run(made,button,{kind:'frame',band:'phone',values:{left:24,top:40,width:128}}).text;
 const expectedExport=path.join(tmp,'expected-export.html');
 fs.writeFileSync(expectedExport,made);
 cp.execFileSync(path.join(tmp,'probe'),['--snapshot',doc,'canvas.html',expectedExport,snapshot]);
 assert.equal(read(doc),paper);assert.equal(read(path.join(snapshot,'index.html')),made);
 assert.ok(made.includes('left: 288px; top: 192px'));assert.ok(made.includes('left: 24px !important'));
 assert.ok(!made.includes('data-wb-'));
 console.log('PASS blank paper → drop, font, color, live-frame commit, phone positioning → snapshot and byte-exact reopen with original unchanged');
 const faviconDoc=path.join(tmp,'tab.html'),publishedAppearance=path.join(tmp,'Published-Appearance');
 const beforePaint="<!doctype html>\r\n<html><head><!-- keep --></head><body><button>Run</button><script>// keep</script></body></html>";
 fs.writeFileSync(faviconDoc,Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(beforePaint)]));
 let painted=engine.backgrounds(beforePaint,'page',[{id:pick(beforePaint,'html'),color:'#225B48'},{id:pick(beforePaint,'body'),color:'transparent'}],0).text;
 painted=engine.backgrounds(painted,'element',[{id:pick(painted,'button'),color:'#CC993388'}],0).text;
 const pngIcon='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAQUlEQVR4nGNgGAWjYKQDRnQBpWiP/9S25N7SHRj2wAATtS0jFYw6YNQBow4YdcCoA0YdMOqAUQeMOmDUAaNgFAAAwAwELDLHNeUAAAAASUVORK5CYII=';
 const finished=engine.setIcon(painted,-1,pngIcon,32).text;
 const out=path.join(tmp,'expected-tab.html');fs.writeFileSync(out,finished);
 cp.execFileSync(path.join(tmp,'probe'),['--snapshot',faviconDoc,'tab.html',out,publishedAppearance]);
 assert.deepEqual(fs.readFileSync(faviconDoc),Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(beforePaint)]));
 assert.deepEqual(fs.readFileSync(path.join(publishedAppearance,'index.html')),Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),Buffer.from(finished)]));
 execute(faviconDoc,{'tab.html':finished});execute(faviconDoc);
 assert.deepEqual(fs.readFileSync(faviconDoc),fs.readFileSync(path.join(publishedAppearance,'index.html')));
 console.log('PASS whole-page and button backgrounds plus embedded favicon, exact BOM/CRLF working save and independent snapshot reopen');
 const original=read(html), originalCSS=read(css);
 const heading=engine.run(original,pick(original,'h1'),{kind:'text',value:'Instrument bench'}).text;
 execute(site,{'index.html':heading});assert.equal(read(html),original.replace('<h1>Workbench fixture</h1>','<h1>Instrument bench</h1>'));
 const after=hashes(fixtures);assert.deepEqual(Object.keys(after).filter(p=>baseline[p]!==after[p]),['Site/index.html']);
 console.log('PASS visual text edit → exact diff → save → reopen');
 const insertion=engine.run(heading,pick(heading,'div.actions'),{kind:'insert',item:'Button'}).text;
 const scoped=engine.style(insertion,pick(insertion,'button'),{prop:'margin-top',value:'19px',mobile:true,width:600,external:true,css:originalCSS});
 execute(site,{'index.html':scoped.text,'css/bench.css':scoped.css});assert.equal(read(css),originalCSS+'\n@media (max-width: 600px) {\n  #wb-button-1 { margin-top: 19px; }\n}\n');
 assert.equal(read(html),insertion.replace('<button type="button">Button','<button id="wb-button-1" type="button">Button'));
 console.log('PASS exact two-file insertion and mobile CSS diff after save/reopen');
 const shifted=engine.run(read(html),pick(read(html),'div#meter'),{kind:'move',x:59,y:50}).text;
 execute(site,{'index.html':shifted});assert.equal(read(html),scoped.text.replace('left: 24px; top: 32px','left: 59px; top: 50px'));
 assert.ok(read(html).includes('href="notes.html"'));assert.ok(fs.existsSync(path.join(site,'notes.html')));
 const script=read(path.join(site,'js/bench.js'));const bench=runtime(['signal','meter'],script);
 const meter=bench.elements.meter;meter.style={left:'59px',top:'50px'};
 emit(meter,'pointerdown',{button:0,clientX:5,clientY:8});emit(bench.window,'pointermove',{buttons:1,clientX:15,clientY:19});emit(bench.window,'pointerup');
 assert.deepEqual(meter.style,{left:'69px',top:'61px'});
 for(const key of 'ODIN')emit(bench.window,'keydown',{key});
 assert.equal(bench.elements.signal.textContent,'Mjölnir unlocked');assert.equal(bench.elements.signal.children.length,1);
 assert.equal(hashes(fixtures)['Site/js/bench.js'],baseline['Site/js/bench.js']);
 console.log('PASS moved object, relative link target, original pointer and ODIN handlers with DOM test double');
 let app=read(path.join(root,'Resources/blank.html'));
 for(const [item,tag,id] of [['Number input','input','reading'],['Button','button','compute'],['Output','output','result']]){
   app=engine.run(app,pick(app,'section.layout'),{kind:'insert',item}).text;
   app=engine.run(app,pick(app,tag),{kind:'attr',key:'id',value:id}).text;
 }
 app=engine.run(app,pick(app,'button#compute'),{kind:'handler'}).text.replace('// Write the click action here.',"document.getElementById('result').textContent = String(document.getElementById('reading').valueAsNumber * 9 / 5 + 32);");
 execute(single,{[path.basename(single)]:app});
 const reopened=read(single);assert.equal(reopened,app);const range=engine.scripts(reopened)[0];
 const instrument=runtime(['compute','result','reading'],reopened.slice(range.start,range.end));
 instrument.elements.reading.valueAsNumber=25;emit(instrument.elements.compute,'click');assert.equal(instrument.elements.result.textContent,'77');
 assert.ok(!app.includes('data-wb-'));console.log('PASS saved single-file instrument, generated handler, 25 °C → 77 °F with DOM test double');
} finally{fs.rmSync(tmp,{recursive:true,force:true});}
