const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const w = require('../Resources/workflows.js');
const source = require('../Resources/source.js');

const page = "\uFEFF<!doctype html>\r\n<html><head><!-- old -->\r\n<script src='../site.js'></script></head>\r\n<body><button class='go' onclick='hook()'>Go</button><p>Idle</p><p>Second</p>\r\n</body></html>";
const nodes = source.index(page).nodes;
const trigger = nodes.find(n => n.tag === 'button').id;
const target = nodes.find(n => n.tag === 'p').id;
const action = (kind, value = '', detail = '', id = target) => ({kind, value, detail, target:id});
const request = {key:'one', existing:false, event:'click', preventDefault:true, trigger, steps:[action('text','Done')]};
const edit = (s, r) => w.editWorkflow(s,r).text;
function reopen(s,key='one') { return {...w.workflows(s).flows.find(f=>f.key===key), existing:true}; }

test('only referenced tags and one script change; BOM, CRLF and handwritten handlers survive', () => {
  assert.equal(w.workflows(page).flows.length,0);
  const s = edit(page,request), managed = source.index(s).nodes.find(n=>n.attrs['data-webbench-workflow']);
  const bare = s.slice(0,managed.start) + s.slice(managed.end);
  assert.equal(bare,page.replace('<button ','<button id="wb-button-1" ').replace('<p>','<p id="wb-p-1">'));
  assert(!/(?<!\r)\n/.test(s));
  assert.equal(edit(s,reopen(s)),s);
  assert.equal(edit(s,{...reopen(s),remove:true}),bare);
});
test('two same-tag targets get distinct stable IDs and survive reordered source', () => {
  const s=edit(page,{...request,steps:[action('text','A'),action('show','','',target+1),action('color','#11cc88')]});
  assert.deepEqual(reopen(s).steps.map(step=>step.target),[target,target+1,target]);
  const shifted=s.replace('<button ','<h2>Title</h2><button ');
  assert.equal(reopen(shifted).trigger,trigger+1);
  assert.equal(edit(shifted,reopen(shifted)),shifted);
});
test('missing or duplicate target never silently refers to a different element', () => {
  const s=edit(page,request).replace('id="wb-p-1"','id="changed"');
  assert.equal(reopen(s).steps[0].target,-1);
  assert.throws(()=>edit(s,reopen(s)),/Choose an element/);
  const dup=page.replace('<p>Idle','<p id="ok">Idle').replace('<p>Second','<p id="&#111;k">Second');
  assert.throws(()=>edit(dup,request),/unique/);
});
test('hand changes, duplicate ownership, stale edit/delete and unknown steps are protected', () => {
  const s=edit(page,request);
  const altered=s.replace('async event =>','event =>');
  assert.throws(()=>w.workflows(altered),/kept it intact/);
  assert.throws(()=>edit(altered,{...request,existing:true,remove:true}),/kept it intact/);
  assert.throws(()=>edit(s,request),/changed/);
  assert.throws(()=>edit(page,{...request,existing:true,remove:true}),/changed/);
  assert.throws(()=>edit(s,{...request,key:'another'}),/already has/);
  assert.throws(()=>edit(page,{...request,steps:[action('eval','evil()')]}),/Invalid action/);
});
test('changing one flow leaves sibling script, whitespace and other event bindings intact', () => {
  const a=edit(page,request);
  const both=edit(a,{...request,key:'two',event:'input',steps:[action('dialog','Selected','OK')]});
  const b=edit(both,{...reopen(both),steps:[action('toggle')],event:'change'});
  const script = (s,key) => {const n=source.index(s).nodes.find(n=>n.attrs['data-webbench-workflow']?.value===key);return s.slice(n.start,n.end);};
  assert.equal(script(b,'two'),script(both,'two'));
  assert.equal(reopen(b).event,'change');
  assert.equal(w.workflows(b).flows.length,2);
});
test('literal HTML and script terminators remain inert even in action metadata', () => {
  const str='</ScRiPt><!--\u2028\u2029\u0000<script>exploit()</script> & "𝄞"';
  const s=edit(page,{...request,steps:[action('dialog',str,str),action('text',str)]});
  assert.equal(source.index(s).nodes.filter(n=>n.tag==='script').length,2);
  assert.equal(reopen(s).steps[0].detail,str);
  assert(!s.includes('>exploit()'));
  assert.equal(edit(s,reopen(s)),s);
});
test('file actions reject invalid destinations, fields and file names', () => {
  for(const url of ['javascript:alert(1)','//attacker.test','/\\attacker','data:text/plain,yo','https://name@host/upload','file:///private']) {
    assert.throws(()=>edit(page,{...request,steps:[action('upload',url,'file')]}));
  }
  for(const url of ['/global','https://outside.test/report','\\server','']) {
    assert.throws(()=>edit(page,{...request,steps:[action('download',url)]}));
  }
  assert.throws(()=>edit(page,{...request,steps:[action('upload','/submit',' ')]}));
  assert.throws(()=>edit(page,{...request,steps:[action('downloadText','../a','b')]}));
  for (const url of ['../api/upload','/api','https://uploads.example.org/files']) {
    const s=edit(page,{...request,steps:[action('upload',url,'attachment')]});
    assert.equal(reopen(s).steps[0].value,url);
  }
});
test('bundled Signal check is standalone and both examples reopen byte-for-byte', () => {
  const s=fs.readFileSync(path.join(__dirname,'../Fixtures/Signal-check.html'),'utf8');
  const flows=w.workflows(s).flows;
  assert.equal(flows.length,2);
  for(const f of flows) assert.equal(edit(s,{...f,existing:true}),s);
});
test('damaged second script is revealed at its own exact range, including a removed marker', () => {
  const first=edit(page,request);
  const both=edit(first,{...request,key:'two',event:'change'});
  const damaged=both.replace('data-webbench-workflow="two"','data-manual="two"');
  const start=damaged.indexOf('<script data-manual');
  assert.deepEqual(w.workflowIssueRange(damaged),[start,damaged.indexOf('</script>',start)+9-start]);
  assert.throws(()=>w.workflows(damaged),/kept it intact/);
});
test('the standard source handler navigator can recognize generated click listeners', () => {
  const s = edit(page, request);
  assert.match(s, /document\.getElementById\("wb-button-1"\)\.addEventListener\("click"/);
});
