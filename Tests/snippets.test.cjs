const test = require('node:test');
const assert = require('node:assert/strict');
const web = require('../Resources/source');
const page = "<!doctype html>\r\n<html><head><!-- Ω --></head><body><section id='panel'><p>Keep</p></section></body></html>\r\n";
const byTag = (html,tag)=>web.index(html).nodes.find(n=>n.tag===tag).id;
const add = (type,text,options={})=>web.run(page,byTag(page,'section'),{kind:'snippet',type,text,...options});
const edit = (html,node,type,text,options={})=>web.run(html,node,{kind:'snippet',type,text,existing:true,...options}).text;

test('literal code is escaped and editing preserves unchanged character references',()=>{
  const literal='if (a < b && c > 2) {\r\n  log("</script>");\r\n}';
  const added=add('code',literal), n=byTag(added.text,'pre');
  assert.equal(web.snippetDetails(added.text,n).text,literal);
  assert(!added.text.includes('</script>'));
  assert.equal(edit(added.text,n,'code',literal),added.text);
  const imported="<pre id='src'><code class='language-js'>&#x1f9f0; &quot;A&quot;\r\n  &lt;b&gt; &amp; B</code></pre>";
  assert.equal(edit(imported,0,'code','🧰 "A"\r\n  <b> & C'),imported.replace(' B</code>',' C</code>'));
  assert.equal(edit(imported,0,'code','🧪 "A"\r\n  <b> & B'),imported.replace('&#x1f9f0;','🧪'));
  assert.throws(()=>web.snippetDetails('<pre><code><em>A</em></code></pre>',0),/Code/);
});
test('custom HTML preserves multiple roots, comments, scripts and wrapper position',()=>{
  const fragment="<!-- Widget -->\r\n<style>.on { color: red }</style>\r\n<button id='go'>Press</button><script>go.onclick=()=>go.classList.add('on');</script>";
  const {text,focus}=add('html',fragment,{point:{x:13,y:24}});
  const node=web.index(text).nodes.find(n=>n.start===focus);
  assert.equal(web.snippetDetails(text,node.id).text,fragment);
  assert.equal(text.slice(0,node.start)+text.slice(node.end),page);
  assert.equal(edit(text,node.id,'html',fragment),text);
  assert.equal(edit(text,node.id,'html',fragment.replace('Press','Test')),text.replace('Press','Test'));
  for(const invalid of ['<div>','<body>X</body>','</div><p>Break out</p>']) assert.throws(()=>edit(text,node.id,'html',invalid));
});
test('URL changes patch the original iframe attributes and support project paths',()=>{
  const original=page.replace('</section>',"<iframe loading='lazy' sandbox='allow-scripts' title='A &amp; B' src='parts/old.html?a=1&amp;b=2' allowfullscreen></iframe></section>");
  const id=byTag(original,'iframe'),details=web.snippetDetails(original,id);
  assert.equal(details.title,'A & B');
  assert.equal(details.url,'parts/old.html?a=1&b=2');
  assert.equal(edit(original,id,'iframe',details.text,{title:details.title,fields:true,url:'../new.html?a=1&b=2'}),original.replace('parts/old','../new'));
  for(const url of ['javascript:alert(1)','data:text/html,X','file:///tmp/x','https:broken','https://','']) {
    assert.throws(()=>add('iframe','',{fields:true,title:'Child',url}));
  }
});
test('pasted provider iframe survives insertion and no-op reopen even with custom attributes and leading whitespace',()=>{
  const pasted=' \r\n<iframe title="Ω" src="https://embed.example/widget?x=1&amp;y=2" loading="lazy" allow="fullscreen" allowfullscreen style="background: url(&quot;a&amp;b&quot;); width: 100%;"></iframe>\r\n';
  const {text,focus}=add('iframe',pasted,{before:byTag(page,'p')});
  assert.equal(text,page.replace('<p>Keep',pasted+'<p>Keep'));
  const row=web.index(text).nodes.find(n=>n.start===focus);
  assert.equal(row.tag,'iframe');
  const detail=web.snippetDetails(text,row.id);
  assert.equal(edit(text,row.id,'iframe',detail.text),text);
  const free=add('iframe',pasted,{point:{x:12,y:4}}).text;
  assert(free.includes('url(&quot;a&amp;b&quot;)') && free.includes('left: 12px;'));
  assert.throws(()=>add('iframe',pasted+'<script>foo()</script>'),/Custom HTML/);
  assert.throws(()=>add('iframe','plain text'));
});
test('srcdoc stays in the saved iframe, Design gets a sandboxed placeholder with its original geometry',()=>{
  const raw='<iframe id="child" width="222" srcdoc="&lt;script>console.log(123)&lt;/script>" allow="camera" onload="track()" sandbox="allow-scripts"></iframe>';
  const {text}=add('iframe',raw), id=byTag(text,'iframe');
  assert.equal(web.snippetDetails(text,id).fields,false);
  const design=web.info(text,'data-design-check');
  assert.equal(design.nodes[id].snippet,'iframe');
  for(const removed of ['console.log(123)','onload="track()"','allow="camera"','sandbox="allow-scripts"']) assert(!design.html.includes(removed));
  assert.match(design.html,/width="222"/);
  assert(design.html.includes('Iframe embed'));
  assert.equal(web.info(text).html,text);
  assert.equal(edit(text,id,'iframe',raw,{fields:false}),text);
});
