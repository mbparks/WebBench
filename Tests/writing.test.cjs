const test = require('node:test');
const assert = require('node:assert/strict');
const engine = require('../Resources/source.js');
const {plan, boundaries} = require('../Resources/writing.js');

// Delimiters represent the rendered selection's exact UTF-16 source coordinates.
function edit(marked, op, tag='p') {
  const a = marked.indexOf('|'), b = marked.lastIndexOf('|')-1;
  assert.ok(a>=0 && b>=a);
  const s = marked.replaceAll('|',''), ix = engine.index(s);
  assert.equal(ix.error,'');
  const host = ix.nodes.findLast(n=>n.tag===tag && n.open<=a && n.close>=b);
  const r = plan(s,ix.nodes,host.id,a,b,op);
  if (!r) return marked;
  const text = s.slice(0,r.start)+r.insert+s.slice(r.end);
  assert.equal(engine.index(text).error,'');
  return text.slice(0,r.caret)+'|'+text.slice(r.caret,r.endCaret)+'|'+text.slice(r.endCaret);
}
test('typing changes one source range beside entities and CRLF',()=>{
  const s="<body>\r\n<!-- authored -->\r\n<p class='a'>A&#38; B |word|.</p></body>";
  assert.equal(edit(s,{kind:'text',value:'<Ω> & café'}),s.replace('|word|','&lt;Ω&gt; &amp; café||'));
});
test('entity, CRLF and astral offsets never split rendered characters',()=>{
  const dec = s=>({'&amp;':'&','&#x1F6E0;':'🛠','&copy;':'©','&fake;':'&fake;'})[s];
  assert.deepEqual(boundaries('A\r\n&amp;🛠&#x1F6E0;&copy;','A\n&🛠🛠©',dec),[0,1,3,8,null,10,null,19,25]);
  assert.deepEqual(boundaries('&fake;','&fake;',dec),[0,1,2,3,4,5,6]);
  assert.throws(()=>boundaries('&amp', '&',dec),/differs/);
});
test('Return keeps original attribute, line endings, indentation and following closing-tag spelling',()=>{
  assert.equal(edit("<main>\r\n  <p ID='v'>One||Two</P >\r\n</main>",{kind:'paragraph'}),
    "<main>\r\n  <p ID='v'>One</p>\r\n  <p>||Two</P >\r\n</main>");
});
test('Return inside emphasis preserves markup on both sides and does not duplicate IDs',()=>{
  assert.equal(edit('<h2 id="t"><em>left||right</em></h2>',{kind:'paragraph'},'h2'),
    '<h2 id="t"><em>left</em></h2><p><em>||right</em></p>');
  assert.throws(()=>edit('<p><span id="unique">left||right</span></p>',{kind:'paragraph'}),/duplicate/);
});
test('Shift-Return adds exactly a line break and typed markup is escaped',()=>{
  assert.equal(edit('<p>a||b</p>',{kind:'break'}),'<p>a<br>||b</p>');
  assert.equal(edit('<p>||</p>',{kind:'text',value:'<script>A&B</script>'}),'<p>&lt;script&gt;A&amp;B&lt;/script&gt;||</p>');
});
test('paste creates editable paragraphs and preserves text after the caret',()=>{
  assert.equal(edit('<p>a|X|b</p>',{kind:'paste',value:'One\r\nTwo\n<Three>'}),'<p>aOne</p><p>Two</p><p>&lt;Three&gt;||b</p>');
});
test('bold and italic toggle without rewriting entities or adjoining markup',()=>{
  const original="<p title='meter'><span>Ω</span> |A &#x26; B|.</p>";
  const bold=edit(original,{kind:'bold'});
  assert.equal(bold,original.replace('|A &#x26; B|','<strong>|A &#x26; B|</strong>'));
  assert.equal(edit(bold,{kind:'bold'}),original);
  assert.equal(edit('<p><em>un|der|line</em></p>',{kind:'italic'}),'<p><em>un</em>|der|<em>line</em></p>');
  assert.equal(edit('<p>||</p>',{kind:'text',value:'a',marks:['strong','em']}),'<p><em><strong>a||</strong></em></p>');
});
test('style and list changes preserve authored attributes and selection',()=>{
  assert.equal(edit("<p class='v' aria-label='thing'>|ABC|</p>",{kind:'block',value:'h2'}),"<h2 class='v' aria-label='thing'>|ABC|</h2>");
  const list=edit("<p id='x'>|one|</p>",{kind:'list',value:'ul'});
  assert.equal(list,"<ul><li id='x'>|one|</li></ul>");
  assert.equal(edit(list,{kind:'list',value:'ol'},'li'),"<ol><li id='x'>|one|</li></ol>");
  assert.equal(edit(list,{kind:'list',value:'ul'},'li'),"<p id='x'>|one|</p>");
});
test('Return continues a list, and Return on the empty last item exits it',()=>{
  const two=edit('<ul><li>One||</li></ul>',{kind:'paragraph'},'li');
  assert.equal(two,'<ul><li>One</li><li>||</li></ul>');
  assert.equal(edit(two,{kind:'paragraph'},'li'),'<ul><li>One</li></ul><p>||</p>');
});
test('link wraps selected source and updating it patches only the authored href',()=>{
  assert.equal(edit('<p>|R &amp; D|</p>',{kind:'link',value:'notes.html?a=1&b=2'}),'<p><a href="notes.html?a=1&amp;b=2">|R &amp; D|</a></p>');
  assert.equal(edit("<p><a class='v' href='old'>L||ink</a></p>",{kind:'link',value:'new'}),"<p><a class='v' href='new'>L||ink</a></p>");
  assert.throws(()=>edit('<p>|X|</p>',{kind:'link',value:'javascript:void(0)'}),/address/);
});
test('buttons, artwork, tables and rules insert precisely at the caret',()=>{
  const s='<main><!--x--><p>left||right</p></main>';
  assert.equal(edit(s,{kind:'element',value:'button'}),s.replace('||','<button type="button">|Button|</button>'));
  assert.equal(edit(s,{kind:'element',value:'image',url:'../art/x.svg',alt:'A&B'}),s.replace('||','<img src="../art/x.svg" alt="A&amp;B">||'));
  assert.equal(edit(s,{kind:'element',value:'hr'}),s.replace('||','</p><hr><p>||'));
  assert.equal(edit(s,{kind:'element',value:'table'}),s.replace('||','</p><table><tbody><tr><td>|Cell|</td><td>Cell</td></tr></tbody></table><p>'));
});
test('Backspace joins adjacent simple paragraphs and preserves neighboring comments',()=>{
  assert.equal(edit('<body><!--x--><p id="first">Hi</p>\n<p>|| there</p></body>',{kind:'join',forward:false}),
    '<body><!--x--><p id="first">Hi|| there</p></body>');
  const original='<body><p>Hi</p><!-- keep --><p>|| there</p></body>';
  assert.equal(edit(original,{kind:'join',forward:false}),original);
});
test('unsupported selections and attributed structures leave original markup available',()=>{
  assert.throws(()=>edit('<p><em>|One</em> two|</p>',{kind:'bold'}),/crosses/);
  assert.throws(()=>edit('<p>one|<!--keep-->|two</p>',{kind:'text',value:'X'}),/comment/);
});
test('plain-text cells and containers can start a new editable paragraph',()=>{
  assert.equal(edit('<td>Head||tail</td>',{kind:'paragraph'},'td'),'<td><p>Head</p><p>||tail</p></td>');
});

test('replacing visible words across inline markup preserves the unselected style and attributes',()=>{
  assert.equal(edit('<p><em>A|B</em> and <span id="z">C|D</span></p>',{kind:'text',value:'X'}),
    '<p><em>AX||</em><span id="z">D</span></p>');
});
