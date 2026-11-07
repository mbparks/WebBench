const test=require('node:test'), assert=require('node:assert/strict');
const engine=require('../Resources/source');
function id(html, label){return engine.info(html).nodes.find(n=>n.label===label).id;}
test('every searchable insert option produces a single mapped root in an allowed container',()=>{
  const catalog=engine.catalog(), rules=engine.parentRules();
  assert.equal(new Set(catalog.map(x=>x.id)).size,catalog.length);
  assert.deepEqual(new Set(catalog.map(x=>x.id)),new Set(Object.keys(engine.palette)));
  for(const item of catalog){
    const parent=(rules[item.tag]??rules['*'])[0];
    const s='<'+parent+'><!-- keep --></'+parent+'>';
    const {text,focus}=engine.run(s,0,{kind:'insert',item:item.id});
    assert.equal(engine.index(text).error,'',item.id);
    const root=engine.index(text).nodes.find(n=>n.start===focus);
    assert.equal(root.parent,0,item.id);assert.equal(root.tag,item.tag);
    assert.equal(text,s.replace('<!-- keep -->','<!-- keep -->'+engine.palette[item.id]));
  }
});
test('moves before, after and inside preserve exact subtree bytes, script, href and comments',()=>{
  const s="<main>\r\n<section id='a'><p>A</p><!-- slot --><button id='go'>Go</button></section>\r\n<section id='b'><a href='./meter'>Meter</a></section><script>go.onclick=f;</script></main>";
  const tag="<button id='go'>Go</button>";
  for(const [parent,before,expected] of [
    ['section#a','p',s.replace(tag,'').replace('<p>',tag+'<p>')],
    ['section#b','a',s.replace(tag,'').replace('<a ',tag+'<a ')],
    ['section#b',null,s.replace(tag,'').replace('</a>','</a>'+tag)]
  ]){
    const result=engine.run(s,id(s,parent),{kind:'relocate',child:id(s,'button#go'),before:before&&id(s,before)});
    assert.equal(result.text,expected);
    assert.equal(result.text.slice(result.focus,result.focus+tag.length),tag);
  }
});
test('structural children, cycles, nested forms, implicit boundaries and captions are guarded',()=>{
  const s='<main><form><section><p>P</p></section></form><ul><li>Item</li></ul><figure><p>Art</p><figcaption>Caption</figcaption></figure></main>';
  const op=(name,item)=>engine.run(s,id(s,name),{kind:'insert',item});
  assert.throws(()=>op('section','Form'));assert.throws(()=>op('ul','Button'));
  assert.throws(()=>op('section','List item'));assert.match(op('ul','List item').text,/<li>Item<\/li><li>List item/);
  assert.throws(()=>engine.run(s,id(s,'section'),{kind:'relocate',child:id(s,'form')}));
  assert.match(op('figure','Button').text,/<button[^>]*>Button<\/button><figcaption>/);
  assert.throws(()=>engine.run('<section><p>Tail</section>',0,{kind:'insert',item:'Button'}),/implicit/);
});
test('moving a layer into its current slot is a byte-for-byte no-op',()=>{
  const s='<main><p>1</p><!-- marker -->\r\n<p>2</p></main>';
  for(const before of [1,2])assert.equal(engine.run(s,0,{kind:'relocate',child:1,before}).text,s);
});
test('a whole-line move preserves CRLF and surrounding indentation',()=>{
  const s="<main>\r\n  <section>\r\n    <button>Go</button>\r\n  </section>\r\n  <aside>\r\n    <!-- keep -->\r\n  </aside>\r\n</main>";
  const expected=s.replace("    <button>Go</button>\r\n","").replace("  </aside>","    <button>Go</button>\r\n  </aside>");
  assert.equal(engine.run(s,id(s,'aside'),{kind:'relocate',child:id(s,'button')}).text,expected);
});
