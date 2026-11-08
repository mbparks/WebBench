const test = require('node:test');
const assert = require('node:assert/strict');
const engine = require('../Resources/source.js');

const original = '<!doctype html>\r\n<html><head><style>/* untouched */ .art {display:flex}</style></head>\r\n' +
  '<body><section class="art"><!-- keep Ω --></section><script>window.keep = 1</script></body></html>\r\n';
const parent = engine.index(original).nodes.find(n => n.tag === 'section').id;
const parts = engine.catalog().filter(item => item.shape);
const legacy = {
  Box: '<div style="width: 160px; height: 96px; background-color: #d8e6dc;"></div>',
  Circle: '<div style="width: 96px; height: 96px; border-radius: 50%; background-color: #bb754e;"></div>',
  Line: '<div style="width: 180px; height: 3px; background-color: #28483e;"></div>'
};

test('Layout includes the original and new shapes, with unique searchable names and valid silhouettes', () => {
  const titles = new Set(parts.map(p => p.title));
  for (const title of ['Rectangle','Circle','Line','Square','Rounded rectangle','Pill','Oval','Right triangle','Triangle',
    'Diamond','Trapezoid','Parallelogram','Pentagon','Hexagon','Octagon','Plus','Star','Heart','Chevron',
    'Left arrow','Right arrow','Up arrow','Down arrow','Speech bubble']) assert(titles.has(title),title);
  assert.equal(parts.length,titles.size);
  for (const {group,shape} of parts) {
    assert.equal(group,'Layout');
    assert(shape.width>0 && shape.height>0);
    if (shape.points) {
      assert(shape.points.length>=3);
      for (const xy of shape.points) {
        assert.equal(xy.length,2);
        assert(xy.every(n=>Number.isFinite(n) && n>=0 && n<=100));
      }
    }
  }
  for (const [id,markup] of Object.entries(legacy)) assert.equal(engine.palette[id],markup);
});

test('each shape inserts as one portable element, retains its silhouette through edits, and deletes cleanly', () => {
  for (const part of parts) {
    const {id,title} = part;
    const added = engine.run(original,parent,{kind:'insert',item:id});
    assert.equal(added.text,original.replace('</section>',engine.palette[id]+'</section>'),title);
    const row = engine.info(added.text).nodes.find(n=>n.start===added.focus);
    if (!(id in legacy)) assert.equal(row.name,title);
    let free = engine.run(original,parent,{kind:'insert',item:id,point:{x:22,y:32}});
    assert.match(free.text,/position: absolute; left: 22px; top: 32px;/);
    const colored = engine.backgrounds(free.text,'element',[{id:row.id,color:'#12607a'}],row.id);
    const resized = engine.run(colored.text,row.id,{kind:'frame',values:{width:185,height:110}});
    const fragment = engine.index(resized.text).nodes[row.id];
    assert.match(fragment.attrs.style.value,/width: 185px; height: 110px;/);
    assert.match(fragment.attrs.style.value,/background-color: #12607a;/);
    const stripped = engine.run(resized.text,row.id,{kind:'deleteLayers',ids:[row.id]}).text;
    assert.equal(stripped,original,title);
    for (const key of ['clip-path','border-radius']) {
      const re = new RegExp(key+': [^;]+;');
      assert.equal(fragment.attrs.style.value.match(re)?.[0],engine.palette[id].match(re)?.[0],title);
    }
  }
});
