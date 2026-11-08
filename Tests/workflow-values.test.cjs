const {test} = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {index} = require('../Resources/source.js');
const {editWorkflow, workflows} = require('../Resources/workflows.js');
const sample = "\uFEFF<!doctype html>\r\n<html><body><form class='meter'><input type=number><input type=number><button>Test</button></form>\r\n<output>Idle</output><details><summary>Help</summary></details><input type=checkbox><audio></audio><!-- preserve -->\r\n</body></html>";
const tag = (name, n=0) => index(sample).nodes.filter(row => row.tag === name)[n].id;
const step = (kind, target, value='', detail='') => ({kind,target,value,detail});
const flow = {key:'meter', existing:false, trigger:tag('button'), event:'click', preventDefault:true,
  steps:[{...step('calculate',tag('output'),'multiply',' W'),input:tag('input'),operand:tag('input',1),digits:2,invalid:'Bad reading'}],
  condition:{source:tag('form'),test:'valid',value:''},
  otherwise:[step('text',tag('output'),'Check the fields')]};
const apply = (s, f) => editWorkflow(s,f).text;
function reopen(s) {return {...workflows(s).flows[0], existing:true};}

test('expanded workflow patches only targeted tags, preserves CRLF and reopens with all references', () => {
  const s=apply(sample,flow);
  const old=s.slice(0,s.indexOf('<script data-webbench-workflow')) + s.slice(s.indexOf('</script>')+9);
  assert.equal(old.replace(/ id="wb-[a-z]+-\d+"/g,''),sample);
  assert.equal((old.match(/ id="/g)||[]).length,5);
  assert(!/(?<!\r)\n/.test(s));
  const record=reopen(s);
  assert.deepEqual(record.steps, flow.steps);
  assert.deepEqual(record.condition,flow.condition);
  assert.deepEqual(record.otherwise,flow.otherwise);
  assert.equal(apply(s,record),s);
  const shifted=s.replace('<form ','<aside>Note</aside><form ');
  const mapped=reopen(shifted);
  assert.equal(mapped.condition.source,tag('form')+1);
  assert.equal(mapped.steps[0].operand,tag('input',1)+1);
  assert.equal(mapped.otherwise[0].target,tag('output')+1);
  assert.equal(apply(shifted,mapped),shifted);
});
test('condition and operand references never silently retarget when a field disappears', () => {
  const s=apply(sample,flow);
  const broken=s.replace('id="wb-input-2"', 'id="retired"');
  assert.equal(reopen(broken).steps[0].operand,-1);
  assert.throws(()=>apply(broken,reopen(broken)),/Choose an element/);
  const form=s.replace('id="wb-form-1"', 'id="retired"');
  assert.equal(reopen(form).condition.source,-1);
  assert.throws(()=>apply(form,reopen(form)),/Choose an element/);
});
test('both branches and arithmetic settings are validated before any patch is returned', () => {
  const calc=flow.steps[0];
  const invalid=[
    {...flow,condition:null}, {...flow,otherwise:[step('resetForm',tag('output'))]},
    {...flow,condition:{source:tag('output'),test:'checked',value:''}},
    {...flow,condition:{source:tag('input'),test:'greater',value:'1e500'}},
    {...flow,steps:[{...calc,constant:'0xF'}]}, {...flow,steps:[{...calc,constant:'  '}]},
    {...flow,steps:[{...calc,value:'eval'}]}, {...flow,steps:[{...calc,digits:9}]},
    {...flow,event:'submit'}, {...flow,steps:[step('classChange',tag('output'),'toggle','two classes')]},
    {...flow,otherwise:Array(64).fill(step('show',tag('output')))}
  ];
  for(const request of invalid) assert.throws(()=>apply(sample,request));
});
test('eligible chooser lists reflect form roles and classes found on the current page', () => {
  const {choices,classes}=workflows(sample);
  assert.deepEqual(choices.form,[tag('form')]);
  assert.deepEqual(choices.checked,[tag('input',2)]);
  assert.deepEqual(choices.media,[tag('audio')]);
  assert.deepEqual(choices.details,[tag('details')]);
  assert.deepEqual(classes,['meter']);
});
test('constant operands, both branches and literal fallback messages remain safe and editable', () => {
  const payload='</script><script>unwanted()</script>\u2028';
  const request={...flow, steps:[{...flow.steps[0],constant:'-2.5e1',detail:payload,invalid:payload}],
    otherwise:[{...step('copyValue',tag('output'),payload),input:tag('input')}]};
  const s=apply(sample,request);
  assert.equal(index(s).nodes.filter(n=>n.tag==='script').length,1);
  const r=reopen(s);
  assert.equal(r.steps[0].constant,'-2.5e1');
  assert.equal(r.steps[0].operand,undefined);
  assert.equal(r.otherwise[0].value,payload);
  assert.equal(apply(s,r),s);
});
test('any manual change inside an expanded handler is surfaced at its source range', () => {
  const s=apply(sample,flow).replace('first * second','first + second');
  assert.throws(()=>workflows(s),/kept it intact/);
  assert.throws(()=>apply(s,{...flow,existing:true}),/kept it intact/);
});
test('v0.11 byte signature covers all eleven original action kinds', () => {
  const out=tag('output');
  const steps=[
    step('text',out,'ready'),step('color',out,'#ddaa66'),step('background',out,'#005533'),
    step('show',out),step('hide',out),step('toggle',out),step('dialog',-1,'Title','Body'),
    step('download',-1,'doc.pdf','report.pdf'),step('downloadText',-1,'note.txt','note'),
    step('chooseFile',out),step('upload',-1,'/receive','file')
  ];
  const s=apply(sample,{...flow,steps,condition:null,otherwise:[]});
  assert.equal(crypto.createHash('sha256').update(s).digest('hex'),'3252c7a70572ed9cf442183a8f7961c5d52fa25d848a7c5df3b1f1476b7dd94e');
  assert.equal(apply(s,reopen(s)),s);
});
