const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {workflows,editWorkflow,workflowIssueRange} = require('../Resources/workflows');
const {index} = require('../Resources/source');
const page = '<!DOCTYPE html>\r\n<html><body><!-- π --><button id="go">Go</button><button id="off">Off</button><output id="out">0</output><video id="cam"></video><img id="still"><input id="cmd"><script>/* untouched */</script>\r\n</body></html>\r\n';
const ids = Object.fromEntries(index(page).nodes.filter(n=>n.attrs.id).map(n=>[n.attrs.id.value,n.id]));
const step = (kind,value='',detail='',target=-1) => ({kind,value,detail,target});
const req = (steps,extra={})=>({key:'demo',existing:false,trigger:ids.go,event:'click',preventDefault:true,steps,...extra});
const apply = (html,request)=>editWorkflow(html,request).text;
const marker = '<script data-webbench-devices="1">';
const device = req([step('serialOpen','115200')]);
const usb = {vendor:'1234',product:'0001',configuration:'1',interface:'0',alternate:'0'};
test('the shipped page contains all 13 editable actions and one shared device script',()=>{
  const html=fs.readFileSync(require.resolve('../Fixtures/Device-workbench.html'),'utf8');
  const flows=workflows(html).flows;
  assert.equal(new Set(flows.map(f=>f.steps[0].kind)).size,13);
  assert.equal(html.split(marker).length,2);
  for (const flow of flows) assert.equal(apply(html,{...flow,existing:true}),html);
});
test('one device block shared across branches and handlers, removed on conversion or deletion',()=>{
  const one=apply(page,device);
  assert(!/(?<!\r)\n/.test(one));
  const two=apply(one,req([step('text','done','',ids.out)],{key:'branch',trigger:ids.off,
    condition:{source:ids.cmd,test:'filled',value:''},otherwise:[step('serialRead','','',ids.out)]}));
  assert.equal(two.split(marker).length,2);
  const stripped=apply(two,{key:'demo',remove:true,existing:true});
  assert.equal(stripped.split(marker).length,2);
  const classic=req([step('text','done','',ids.out)],{trigger:ids.off,key:'branch'});
  assert.equal(apply(stripped,{...classic,existing:true}),apply(page,classic));
  assert.equal(apply(one,{key:'demo',remove:true,existing:true}),page);
});
test('device support hand edits, missing support and duplicate blocks give a Code range',()=>{
  const html=apply(page,device);
  const start=html.indexOf(marker), end=html.indexOf('</script>',start)+9;
  const block=html.slice(start,end);
  for(const changed of [html.replace('Camera started.', 'custom'),html.replace(block,''),html.replace(block,block+block)]) {
    assert.throws(()=>workflows(changed),/device support/i);
    const [offset,length]=workflowIssueRange(changed);
    assert(changed.slice(offset,offset+length).startsWith('<script'));
    assert.throws(()=>apply(changed,{...device,existing:true}));
  }
});
test('settings, readouts and send sources are validated and survive reopening',()=>{
  const valid=apply(page,req([{...step('usbOpen'),settings:usb},{...step('usbWrite','2'),input:ids.cmd},step('usbRead','1','64',ids.out)]));
  const restored=workflows(valid).flows[0];
  assert.deepEqual(restored.steps[0].settings,usb);
  assert.equal(restored.steps[1].input,ids.cmd);
  for (const invalid of [step('serialOpen','0'),step('serialWrite','HI','bad'),step('usbRead','16','2',ids.out),
    step('usbRead','1','4097',ids.out),step('usbWrite','1','GG'),{...step('usbOpen'),settings:{...usb,vendor:''}},
    {...step('usbOpen'),settings:{...usb,interface:'-1'}},step('micStart','','',ids.cam),step('cameraStart','','',ids.still),
    step('cameraSnapshot','','',ids.out),step('serialRead','','',ids.cam),{...step('serialWrite','','lf'),input:-1}]) {
    assert.throws(()=>apply(page,req([invalid])));
  }
});
test('existing example workflows regenerate without device support or format upgrades',()=>{
  for (const name of ['Power-meter','Signal-check']) {
    const html=fs.readFileSync(require.resolve('../Fixtures/'+name+'.html'),'utf8');
    assert(!html.includes(marker));
    for (const f of workflows(html).flows) assert.equal(apply(html,{...f,existing:true}),html);
  }
});
