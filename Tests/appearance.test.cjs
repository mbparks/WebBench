const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const engine=require('../Resources/source.js');
const html='<!doctype html>\r\n<html><head>\r\n  <!-- author -->\r\n</head><body><button style="color: red">Go</button></body></html>';
const id=(s,tag)=>engine.index(s).nodes.find(n=>n.tag===tag).id;
const icon='data:image/png;base64,iVBORw0KGgo=';
test('a new favicon inserts one ordinary link and preserves CRLF and source around it',()=>{
  const s=engine.setIcon(html,-1,icon,32).text;
  assert.equal(s,html.replace('</head>','  <link rel="icon" type="image/png" sizes="32x32" href="'+icon+'">\r\n</head>'));
  const meta=engine.icons(s);assert.equal(meta.links.length,1);assert.equal(meta.links[0].href,icon);
  assert.equal(engine.setIcon(s,meta.links[0].id,icon,32).text,s);
});
test('editing one icon leaves other variants, touch icons, masks and custom attributes byte-identical',()=>{
  const first="<LINK href='sun.ico' rel='SHORTCUT icon' media='(prefers-color-scheme: light)' sizes='any' type='image/x-icon' data-name='☀'>";
  const s=html.replace('</head>',first+'<link rel="apple-touch-icon" href="touch.png"><link rel="mask-icon" href="mask.svg"><link rel="icon" href="dark.ico"></head>');
  const links=engine.icons(s).links;assert.equal(links.length,2);
  const edited=engine.setIcon(s,links[0].id,'../assets/favicon.png',48).text;
  assert.equal(edited,s.replace(first,first.replace('sun.ico','../assets/favicon.png').replace("'any'","'48x48'").replace('image/x-icon','image/png')));
});
test('single-file and nested-folder icons work with implicit heads, local base and unrelated body links',()=>{
  const doc='<!doctype html>\n<base href="/public/"><title>Bench</title><p>Meter</p><link rel="icon" href="inside-body.ico">';
  assert.deepEqual(engine.icons(doc),{base:'/public/',links:[]});
  const result=engine.setIcon(doc,-1,icon,16).text;
  assert.equal(engine.icons(result).links[0].href,icon);
  assert.ok(result.includes(doc.slice(doc.indexOf('<base'))));
  assert.throws(()=>engine.setIcon(doc,42,'../../outside.png',32));
});
test('setting document and element backgrounds is local and preserves an unrelated gradient, text and JS',()=>{
  const s=html.replace('<html>',"<html style='color: #456'>").replace('<body>',"<body style='background-image: linear-gradient(red, blue)'>");
  const item=id(s,'button');
  const page=engine.backgrounds(s,'page',[{id:id(s,'html'),color:'#285947'},{id:id(s,'body'),color:'transparent'}],item);
  assert.equal(page.text,s.replace('color: #456','color: #456; background-color: #285947;').replace('linear-gradient(red, blue)','linear-gradient(red, blue); background-color: transparent;'));
  assert.equal(page.focus,page.text.indexOf('<button'));
  const b=engine.backgrounds(page.text,'element',[{id:item,color:'#CD923B80'}],item).text;
  assert.equal(b,page.text.replace('color: red','color: red; background-color: #CD923B80;'));
  assert.equal(engine.backgrounds(b,'element',[{id:item,color:'#CD923B80'}],item).text,b);
});
test('solid color after an inline shorthand can replace a gradient, preserve its authored value and win important styles',()=>{
  const style='background-color: pink; /* author */ background: linear-gradient(red, blue) black !important';
  const s='<main style="'+style+'">Panel</main>';
  let r=engine.backgrounds(s,'element',[{id:0,color:'#003322',image:true,strongColor:true,strongImage:true}],0).text;
  assert.equal(r,s.replace(style,style+'; background-color: #003322 !important; background-image: none !important;'));
  assert.equal(engine.backgrounds(r,'element',[{id:0,color:'transparent'}],0).text,r.replace('#003322','transparent'));
});
test('fragment paint updates a single rule for implicit html and body and keeps the selected object',()=>{
  const s='<!-- preserved -->\r\n<p>one</p><p>two</p>';
  const r=engine.backgrounds(s,'page',[{id:-1,color:'#012345'},{id:-2,color:'transparent'}],1);
  assert.ok(r.text.includes('<style id="webbench-page-paint">:root { background-color: #012345; } :root > body { background-color: transparent; } </style>'));
  assert.equal(r.focus,r.text.indexOf('<p>two'));
  const next=engine.backgrounds(r.text,'page',[{id:-1,color:'#FEDCBA'}],2);
  assert.equal(next.text,r.text.replace('#012345','#FEDCBA'));assert.equal(next.focus,next.text.indexOf('<p>two'));
});
test('ambiguous paint targets and unsafe values fail without changing source',()=>{
  assert.throws(()=>engine.backgrounds(html,'element',[{id:id(html,'body'),color:'#ffffff'}],0));
  assert.throws(()=>engine.backgrounds(html,'element',[{id:id(html,'button'),color:'red;position:fixed'}],0));
  assert.throws(()=>engine.backgrounds(html,'page',[{id:-1,color:'#998877'}],0));
  assert.throws(()=>engine.setIcon(html,-1,'https://evil.example/icon.png',32));
});

test('the canvas reads both backgrounds, trials ordinary and important CSS, restores exact markup and sends one native operation',()=>{
  function node(tag,id,authored,baseColor,baseImage='none',locked=false){
    let style=authored;
    return {localName:tag,id,style:{},getAttribute:k=>k==='style'?style:k==='data-id'?String(id):null,
      setAttribute:(k,v)=>{if(k==='style')style=v},removeAttribute:k=>{if(k==='style')style=null},baseColor,baseImage,locked};
  }
  const rgb=v=>v==='transparent'?'rgba(0, 0, 0, 0)':v?.startsWith('#')?'rgb('+[1,3,5].map(p=>parseInt(v.slice(p,p+2),16)).join(', ')+')':v;
  const root=node('html',0,null,'rgb(255, 255, 255)'),body=node('body',1,'margin: 0;','rgb(255, 255, 255)','linear-gradient(red, blue)'),button=node('button',2,'color: red','rgb(0, 0, 0)','none',true);
  const nodes=[root,body,button],messages=[];
  const pick=sel=>nodes[Number(sel.match(/="(\d+)"/)?.[1])];
  const document={body,documentElement:root,querySelector:pick,querySelectorAll:sel=>[pick(sel)],createElement:()=>({style:{set color(v){this.value=rgb(v)},get color(){return this.value}}})};
  const window={addEventListener(){},webkit:{messageHandlers:{design:{postMessage:m=>messages.push(JSON.parse(JSON.stringify(m)))}}}};
  function getComputedStyle(e){
    function val(key,base){
      const matches=[...(e.getAttribute('style')??'').matchAll(new RegExp(key+':\\s*([^;]+)','g'))];
      const v=matches.at(-1)?.[1];if(!v||e.locked&&!v.includes('!important'))return base;
      return rgb(v.replace(/\s*!important$/,''));
    }
    return {get backgroundColor(){return val('background-color',e.baseColor)},get backgroundImage(){return val('background-image',e.baseImage)},getPropertyValue:k=>val(k,k==='background-color'?e.baseColor:e.baseImage)};
  }
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Resources/appearance.js'),'utf8'),{WB:{marker:'data-id',token:'test',tree:nodes.map(n=>({tag:n.localName}))},document,window,getComputedStyle,WebBench:engine});
  window.webBenchPaper();assert.deepEqual(messages.pop(),{kind:'paper',token:'test',color:'rgb(255, 255, 255)',image:true});
  window.webBenchPaint('page',2,'#103050',false);
  assert.deepEqual(messages.pop().parts,[{id:0,color:'#103050'},{id:1,color:'transparent',image:true}]);
  assert.equal(root.getAttribute('style'),null);assert.equal(body.getAttribute('style'),'margin: 0;');
  window.webBenchPaint('page',2,'#103050',true);assert.equal(messages.pop().parts[1].image,undefined);
  window.webBenchPaint('element',2,'#FFFFFF',false);
  assert.deepEqual(messages.pop().parts,[{id:2,strongColor:true,color:'#FFFFFF'}]);assert.equal(button.getAttribute('style'),'color: red');
});
test('applying a favicon keeps the inspected content object selected after the head shifts',()=>{
  const b=id(html,'button');
  const first=engine.setIcon(html,-1,'favicon.png',16,b);
  assert.equal(first.focus,first.text.indexOf('<button'));
  const link=engine.icons(first.text).links[0];
  const second=engine.setIcon(first.text,link.id,icon,48,id(first.text,'button'));
  assert.equal(second.focus,second.text.indexOf('<button'));
});
