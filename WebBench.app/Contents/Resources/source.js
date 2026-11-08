// Source offsets use UTF-16, the coordinate system shared by JS and NSTextView.
'use strict';
const WebBench = (() => {
  const voids = new Set('area base br col embed hr img input link meta param source track wbr'.split(' '));
  const optional = new Set(['html','head','body','p','li','dt','dd','option','optgroup','thead','tbody','tfoot','tr','td','th','colgroup']);
  const paragraphBreaks = new Set('address article aside blockquote div dl fieldset footer form h1 h2 h3 h4 h5 h6 header hgroup hr main menu nav ol p pre section table ul'.split(' '));
  function closesBefore(tag,next) {
    if(tag==='p')return paragraphBreaks.has(next);
    if(tag==='head')return next==='body';
    if(tag==='li')return next==='li';
    if(tag==='dt'||tag==='dd')return next==='dt'||next==='dd';
    if(tag==='option')return next==='option'||next==='optgroup';
    if(tag==='optgroup')return next==='optgroup';
    if(tag==='td'||tag==='th')return ['td','th','tr','tbody','thead','tfoot'].includes(next);
    if(tag==='tr')return ['tr','tbody','thead','tfoot'].includes(next);
    if(tag==='thead'||tag==='tbody')return ['tbody','tfoot'].includes(next);
    return false;
  }
  const raw = new Set('script style textarea title xmp iframe noembed noframes noscript'.split(' '));
  
  const panelStyle = 'box-sizing: border-box; min-width: min(240px, 100%); min-height: 96px; padding: 16px;';
  // The parts drawer and the exported CSS use the same dimensions and silhouette.
  const shapeNames = new Map();
  function shape(title, width, height, color, geometry = {}, id = title) {
    const {points, radius, ellipse} = geometry;
    const style = ['width: ' + width + 'px', 'height: ' + height + 'px'];
    if (ellipse) style.push('border-radius: 50%');
    if (radius) style.push('border-radius: ' + radius + 'px');
    style.push('background-color: ' + color);
    if (points) style.push('clip-path: polygon(' + points.map(([x,y]) => x + '% ' + y + '%').join(', ') + ')');
    let attributes = '';
    if (!['Box','Circle','Line'].includes(id)) {
      const name = 'shape-' + title.toLowerCase().replaceAll(' ', '-');
      shapeNames.set(name,title);
      attributes = ' class="' + name + '"';
    }
    const html = '<div' + attributes + ' style="' + style.join('; ') + ';"></div>';
    const symbol = {Box:'square',Circle:'circle',Line:'minus'}[id] || 'square.on.circle';
    return [id,title,symbol,html,{width,height,...geometry}];
  }
  const clay = '#bb754e', green = '#698a76', blue = '#678999', gold = '#bb984e', plum = '#976a84';
  const arrow = [[0,30],[58,30],[58,0],[100,50],[58,100],[58,70],[0,70]];
  const shapes = [
    shape('Rectangle',160,96,'#d8e6dc',{},'Box'),
    shape('Circle',96,96,clay,{ellipse:true}),
    shape('Line',180,3,'#28483e'),
    shape('Square',96,96,blue),
    shape('Rounded rectangle',144,96,green,{radius:18}),
    shape('Oval',144,88,plum,{ellipse:true}),
    shape('Pill',144,64,gold,{radius:9999}),
    shape('Triangle',112,96,clay,{points:[[50,0],[100,100],[0,100]]}),
    shape('Right triangle',104,96,green,{points:[[0,0],[100,100],[0,100]]}),
    shape('Diamond',112,96,blue,{points:[[50,0],[100,50],[50,100],[0,50]]}),
    shape('Parallelogram',144,88,plum,{points:[[22,0],[100,0],[78,100],[0,100]]}),
    shape('Trapezoid',144,88,gold,{points:[[22,0],[78,0],[100,100],[0,100]]}),
    shape('Pentagon',104,100,green,{points:[[50,0],[100,38],[81,100],[19,100],[0,38]]}),
    shape('Hexagon',112,96,blue,{points:[[25,0],[75,0],[100,50],[75,100],[25,100],[0,50]]}),
    shape('Octagon',96,96,clay,{points:[[29,0],[71,0],[100,29],[100,71],[71,100],[29,100],[0,71],[0,29]]}),
    shape('Star',110,104,gold,{points:[[50,0],[62,36],[100,38],[70,62],[81,100],[50,78],[19,100],[30,62],[0,38],[38,36]]}),
    shape('Heart',108,96,plum,{points:[[50,19],[58,7],[67,2],[77,0],[86,3],[94,9],[99,19],[100,30],[97,42],[91,54],[79,69],[50,100],[21,69],[9,54],[3,42],[0,30],[1,19],[6,9],[14,3],[23,0],[33,2],[42,7]]}),
    shape('Plus',96,96,green,{points:[[34,0],[66,0],[66,34],[100,34],[100,66],[66,66],[66,100],[34,100],[34,66],[0,66],[0,34],[34,34]]}),
    shape('Right arrow',144,80,blue,{points:arrow}),
    shape('Left arrow',144,80,blue,{points:arrow.map(([x,y]) => [100-x,y])}),
    shape('Up arrow',80,144,blue,{points:arrow.map(([x,y]) => [y,100-x])}),
    shape('Down arrow',80,144,blue,{points:arrow.map(([x,y]) => [100-y,x])}),
    shape('Chevron',104,96,clay,{points:[[0,0],[50,0],[100,50],[50,100],[0,100],[50,50]]}),
    shape('Speech bubble',144,112,green,{points:[[0,0],[100,0],[100,76],[42,76],[19,100],[19,76],[0,76]]})
  ];
  const groups = {
    Essentials: [
      ['Text box','Text','text.alignleft','<p style="margin: 0;">Text box</p>'],
      ['Heading','Heading 2','textformat.size.larger','<h2>Heading</h2>'],
      ['Paragraph','Paragraph','paragraphsign','<p>Paragraph</p>'],
      ['Button','Button','rectangle.and.hand.point.up.left','<button type="button">Button</button>'],
      ['Image','Image','photo','<img src="" alt="Artwork">'],
      ['Link','Link','link','<a href="#target">Link</a>']
    ],
    Layout: [
      ['Section','Section','rectangle.split.3x1','<section style="'+panelStyle+'"><h2>Section</h2></section>'],
      ['Container','Container','rectangle.inset.filled','<div style="'+panelStyle+'"></div>'],
      ['Flex row','Flex row','rectangle.split.3x1','<div style="display: flex; flex-wrap: wrap; align-items: center; gap: 16px; '+panelStyle+'"></div>'],
      ['Grid','Responsive grid','square.grid.2x2','<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(160px, 100%), 1fr)); gap: 16px; '+panelStyle+'"></div>'],
      ['Design area','Free-position area','rectangle.dashed','<section data-design-canvas aria-label="Design area" style="position: relative; min-width: min(320px, 100%); min-height: 320px; isolation: isolate;"></section>'],
      ['Card','Project card','rectangle.on.rectangle','<article style="width: 264px; padding: 24px; border-radius: 12px; background-color: #f2efe6; color: #223e33;"><h2>Project title</h2><p>Add your project description.</p></article>'],
      ...shapes
    ],
    'Code & embeds': [
      ['Code snippet','Code snippet','chevron.left.forwardslash.chevron.right','<pre><code>Code snippet</code></pre>'],
      ['Custom HTML','Custom HTML','curlybraces','<div data-html-snippet>Custom HTML</div>'],
      ['Iframe embed','Iframe embed','rectangle.on.rectangle','<iframe width="480" height="270" title="Iframe embed"></iframe>']
    ],
    Landmarks: [
      ['Header','Header','rectangle.topthird.inset.filled','<header><h2>Page header</h2></header>'],
      ['Navigation','Navigation','list.bullet','<nav aria-label="Navigation"><ul><li><a href="./">Home</a></li></ul></nav>'],
      ['Main','Main content','rectangle.inset.filled','<main style="'+panelStyle+'"></main>'],
      ['Article','Article','doc.richtext','<article><p>Article</p></article>'],
      ['Aside','Aside','sidebar.right','<aside><p>Related information</p></aside>'],
      ['Footer','Footer','rectangle.bottomthird.inset.filled','<footer><p>Footer</p></footer>']
    ],
    'Text & lists': [
      ...[1,3,4,5,6].map(n=>['Heading '+n,'Heading '+n,'textformat','<h'+n+'>Heading</h'+n+'>']),
      ['Bulleted list','Bulleted list','list.bullet','<ul><li>First item</li><li>Second item</li></ul>'],
      ['Numbered list','Numbered list','list.number','<ol><li>First item</li><li>Second item</li></ol>'],
      ['List item','List item','list.bullet.indent','<li>List item</li>'],
      ['Quote','Block quote','text.quote','<blockquote><p>Quotation</p></blockquote>'],
      ['Code block','Code block','chevron.left.forwardslash.chevron.right','<pre><code>Example code</code></pre>'],
      ['Divider','Divider','minus','<hr>'],
      ['Details','Disclosure','chevron.down.square','<details open><summary>Details</summary><p>Additional information.</p></details>']
    ],
    'Media & data': [
      ['Figure','Figure with caption','photo.on.rectangle','<figure><p>Figure content</p><figcaption>Caption</figcaption></figure>'],
      ['Audio','Audio player','speaker.wave.2','<audio controls preload="none" aria-label="Audio"></audio>'],
      ['Video','Video player','film','<video controls playsinline preload="metadata" width="320" height="180" aria-label="Video"></video>'],
      ['Table','Table','tablecells','<table><caption>Table title</caption><thead><tr><th scope="col">Name</th><th scope="col">Value</th></tr></thead><tbody><tr><td>Item</td><td>Value</td></tr></tbody></table>'],
      ['Table row','Table row','rectangle.split.1x2','<tr><td>Item</td><td>Value</td></tr>'],
      ['Table cell','Table cell','square','<td>Value</td>'],
      ['Progress','Progress bar','chart.bar','<progress aria-label="Progress" value="50" max="100">50%</progress>'],
      ['Meter','Meter','gauge.medium','<meter aria-label="Level" min="0" max="100" value="65">65%</meter>']
    ],
    Forms: [
      ['Form','Form','list.bullet.rectangle','<form style="'+panelStyle+'"></form>'],
      ['Fieldset','Field group','rectangle.dashed','<fieldset><legend>Field group</legend></fieldset>'],
      ['Label','Label','tag','<label>Label</label>'],
      ['Text input','Text field','character.cursor.ibeam','<input type="text" aria-label="Text">'],
      ['Number input','Number field','number','<input type="number" aria-label="Value" value="0">'],
      ['Email','Email field','envelope','<input type="email" name="email" aria-label="Email">'],
      ['Date','Date field','calendar','<input type="date" name="date" aria-label="Date">'],
      ['Text area','Multiline text','text.justify','<textarea rows="3" aria-label="Message"></textarea>'],
      ['Dropdown','Dropdown','chevron.up.chevron.down','<select aria-label="Choice"><option>First choice</option><option>Second choice</option></select>'],
      ['Option','Dropdown option','list.bullet','<option>Choice</option>'],
      ['Checkbox','Checkbox','checkmark.square','<label><input type="checkbox"> Checkbox</label>'],
      ['Radio','Radio button','smallcircle.filled.circle','<label><input type="radio" name="choice"> Choice</label>'],
      ['Range','Range slider','slider.horizontal.3','<input type="range" min="0" max="100" value="50" aria-label="Value">'],
      ['Output','Result','equal.square','<output>0</output>'],
      ['Submit','Submit button','paperplane','<button type="submit">Submit</button>']
    ]
  };
  const items = Object.entries(groups).flatMap(([group, rows]) =>
    rows.map(([id,title,symbol,html,shape])=>({id,title,symbol,group,html,...(shape ? {shape} : {}),tag:/^<(\w+)/.exec(html)[1]})));
  const palette = Object.fromEntries(items.map(i=>[i.id,i.html]));
  const catalog = () => items.map(({html,...item})=>item);
  const flowParents = 'body main section div article aside nav header footer form li fieldset figure figcaption address blockquote td th details dialog dd'.split(' ');
  const rules = {
    '*':flowParents, li:['ul','ol','menu'], dt:['dl'], dd:['dl'], tr:['thead','tbody','tfoot'],
    th:['tr'], td:['tr'], option:['select','optgroup'], optgroup:['select'],
    summary:['details'], legend:['fieldset'], figcaption:['figure'],
    caption:[], thead:[], tbody:[], tfoot:[], col:[], colgroup:[], source:[], track:[],
    html:[], body:[], head:[], title:[], meta:[], base:[], link:[], style:[], script:[], template:[], noscript:[]
  };
  const parentsFor = tag => Object.hasOwn(rules,tag) ? rules[tag] : flowParents;
  const accepts = (parent,tag) => parentsFor(tag).includes(parent);
  const tagFor = item => items.find(entry=>entry.id===item)?.tag;
  const fail = msg => { throw Error(msg); };
  const escapeText = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  const escapeAttr = s => escapeText(s).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  const splice = (s, a, b, value) => s.slice(0,a) + value + s.slice(b);
  function index(s) {
    const nodes = [], stack = [], error = message => ({nodes, error:message});
    let i = 0;
    while ((i = s.indexOf('<',i)) >= 0) {
      if (s.startsWith('<!--',i)) {
        const end = s.indexOf('-->',i+4);
        if (end < 0) return error('Unclosed comment.');
        i = end + 3; continue;
      }
      if (/^<!doctype\s/i.test(s.slice(i,i+12))) {
        const end=s.indexOf('>',i); if(end<0)return error('Unclosed doctype.');
        i=end+1; continue;
      }
      if (/^<[!?%]/.test(s.slice(i,i+2))) return error('Processing instructions and embedded template syntax require Code.');
      const tag = /<(\/?)([a-zA-Z][\w:.-]*)/y; tag.lastIndex=i;
      const m=tag.exec(s); if (!m) { i++; continue; }
      let p=tag.lastIndex;
      const name=m[2].toLowerCase(), attrs={}; let slash=false;
      while (p<s.length) {
        if (/\s/.test(s[p])) { p++; continue; }
        if (s[p]==='>') break;
        if (s.startsWith('/>',p)) { slash=true; p++; break; }
        const attr=/[^\s"'<>\/=\x00]+/y; attr.lastIndex=p;
        const a=attr.exec(s); if (!a) return error('Incomplete or ambiguous start tag.');
        const key=a[0].toLowerCase(); if (Object.hasOwn(attrs,key) || key==='__proto__') return error('Duplicate or unsupported attribute.');
        p=attr.lastIndex; while (/\s/.test(s[p]||'!')) p++;
        let value='', start=p, end=p, quote='';
        if(s[p]==='=') {
          p++; while (/\s/.test(s[p]||'!')) p++;
          quote=s[p]==='"'||s[p]==="'"?s[p++]:'';
          start=p;
          if(quote) { p=s.indexOf(quote,p); if(p<0)return error('Unclosed attribute quote.'); }
          else { while(p<s.length && !/[\s>]/.test(s[p]))p++; }
          end=p; value=s.slice(start,end); if(quote)p++;
        }
        attrs[key]={value,start,end,quote};
      }
      if(p>=s.length)return error('Incomplete tag.');
      const next=p+1;
      function implicitEnd(offset){const top=stack.pop();top.close=offset;top.end=offset;}
      if(m[1]) {
        if(stack.some(x=>x.tag===name))while(stack.length && stack.at(-1).tag!==name && optional.has(stack.at(-1).tag))implicitEnd(i);
        const n=stack.pop();
        if (!n || n.tag!==name) return error('Implicit, mismatched, or incomplete closing tag.');
        n.close=i; n.end=next;
      } else {
        while(stack.length && closesBefore(stack.at(-1).tag,name))implicitEnd(i);
        const n={id:nodes.length,tag:name,start:i,open:next,close:next,end:next,parent:stack.length?stack[stack.length-1].id:-1,depth:stack.length,attrs};
        if(n.depth>512)return error('Deeply nested markup requires Code.');
        nodes.push(n);
        if(nodes.length>30000)return error('Page exceeds the visual index limit.');
        if(!voids.has(name) && !slash) {
          stack.push(n);
          if(raw.has(name)) {
            const rx=new RegExp('</'+name+'(?=[\\s>])','ig'); rx.lastIndex=next;
            const closing=rx.exec(s); if(!closing)return error('Unclosed '+name+' element.');
            i=closing.index; continue;
          }
        } else if(slash && !voids.has(name) && !stack.some(x=>x.tag==='svg'||x.tag==='math') && name!=='svg' && name!=='math') return error('Self-closing HTML requires Code.');
      }
      i=next;
    }
    while(stack.length && optional.has(stack.at(-1).tag)){const n=stack.pop();n.close=s.length;n.end=s.length;}
    return {nodes,error:stack.length?'Unclosed '+stack[stack.length-1].tag+' element.':''};
  }
  function mapped(s,id) {
    const ix=index(s); if(ix.error)fail(ix.error); const n=ix.nodes[id];
    if(!n)fail('No corresponding source element.');
    for(let a=n;a;a=ix.nodes[a.parent]) if(['svg','math','template','noscript'].includes(a.tag))fail('Edit embedded or conditional markup in Code.');
    return {n,ix};
  }
  const snippetKind = n => n.tag==='iframe' ? 'iframe' : n.tag==='pre' ? 'code'
    : n.tag==='div' && n.attrs['data-html-snippet'] ? 'html' : null;

  // Decode only text that can be mapped without a browser entity table.
  function plainValue(value, spans) {
    const named = {amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",nbsp:'\u00a0'};
    let delta=0;
    return value.replace(/&(#(?:x[\da-f]+|\d+)|[a-z][a-z\d]*)(;?)/gi,(raw,name,semi,at)=>{
      const record=decoded=>{
        if(spans) spans.push({raw:at,offset:at-delta,length:raw.length,decoded:decoded.length});
        delta+=raw.length-decoded.length;
        return decoded;
      };
      if (name[0]==='#') {
        const hex=name[1].toLowerCase()==='x';
        const cp=parseInt(name.slice(hex?2:1),hex?16:10);
        if (cp>0 && cp<=0x10ffff && !(cp>=0xd800 && cp<=0xdfff) && !(cp>=128 && cp<=159)) return record(String.fromCodePoint(cp));
        fail('This character reference needs Code view.');
      }
      if (semi && Object.hasOwn(named,name)) return record(named[name]);
      if (semi || Object.hasOwn(named,name)) fail('This character reference needs Code view.');
      return raw;
    });
  }
  function replaceLiteral(raw, text) {
    const spans=[], old=plainValue(raw,spans);
    let start=0, end=old.length, nextEnd=text.length;
    while(start<end && start<nextEnd && old[start]===text[start]) start++;
    while(end>start && nextEnd>start && old[end-1]===text[nextEnd-1]) { end--;nextEnd--; }
    // Keep a changed Unicode scalar together when a shared prefix or suffix split its pair.
    if(start>0 && /[\uDC00-\uDFFF]/.test(old.charAt(start))) start--;
    if(end<old.length && /[\uDC00-\uDFFF]/.test(old.charAt(end))) { end++;nextEnd++; }
    const rawOffset=offset=>{
      let pos=offset;
      for(const entity of spans) {
        if(entity.offset>=offset) break;
        pos+=entity.length-entity.decoded;
      }
      return pos;
    };
    return splice(raw,rawOffset(start),rawOffset(end),escapeText(text.slice(start,nextEnd)));
  }
  function codeNode(s,ix,n) {
    const children=ix.nodes.filter(child=>child.parent===n.id);
    if(children.length===1 && children[0].tag==='code' && !s.slice(n.open,children[0].start).trim() && !s.slice(children[0].end,n.close).trim()) return children[0];
    if(!children.length) return n;
    fail('This code block contains nested markup. Edit it in Code to preserve its formatting.');
  }
  function snippetDetails(s,id) {
    const {ix,n}=mapped(s,id), kind=snippetKind(n);
    if(kind==='iframe') {
      let url='',title='',fields=!n.attrs.srcdoc;
      try {url=plainValue(n.attrs.src?.value||'');title=plainValue(n.attrs.title?.value||'');}
      catch {fields=false;}
      return {kind,text:s.slice(n.start,n.end),url,title,fields};
    }
    if(kind==='html') return {kind,text:s.slice(n.open,n.close)};
    if(kind==='code') {
      const code=codeNode(s,ix,n), inner=s.slice(code.open,code.close);
      if(inner.includes('<')) fail('This code block contains markup. Edit it in Code to preserve its formatting.');
      return {kind,text:plainValue(inner)};
    }
    fail('Select an iframe, code block or custom HTML snippet.');
  }
  function checkedHTML(text,frame) {
    if(!text.trim()) fail(frame?'Paste the iframe embed code.':'Enter the HTML fragment.');
    const ix=index(text);
    if(ix.error) fail(ix.error);
    if(ix.nodes.some(n=>['html','head','body','base','plaintext','frameset','frame'].includes(n.tag))) fail('Use a body fragment here. Edit document structure in Code.');
    if(frame) {
      const node=ix.nodes[0];
      if(ix.nodes.length!==1 || node.tag!=='iframe' || text.slice(0,node.start).trim() || text.slice(node.end).trim())
        fail('Paste one complete iframe. For a provider snippet with extra elements or scripts, use Custom HTML.');
      if(!node.attrs.src && !node.attrs.srcdoc) fail('The iframe needs a src or srcdoc attribute.');
    }
  }
  function frameURL(value) {
    const u=value.trim();
    if (/^https?:/i.test(u) && !/^https?:\/\/[^/?#\s]+/i.test(u)) fail('Enter the full embed URL, including its host.');
    if (!u || /[\u0000-\u0020\\]/.test(u) || /^(?!https?:)[a-z][\w+.-]*:/i.test(u) || /^(?:https?:)?\/\/(?![^/?#\s]+)/i.test(u))
      fail('Enter an HTTP(S) embed address or a project-relative path. Encode spaces as %20.');
    return u;
  }
  function editSnippet(s,id,op) {
    const {ix,n}=mapped(s,id);
    const editing=op.existing===true, kind=op.type, text=op.text;
    if(typeof text!=='string' || !['code','html','iframe'].includes(kind)) fail('Unknown snippet type.');
    const current=editing ? snippetDetails(s,id) : null;
    if(editing && current.kind!==kind) fail('The selected snippet changed. Reopen it.');
    const unchanged=()=>({text:s,focus:n.start});
    let markup;
    if(kind==='code') {
      if(editing && text===current.text) return unchanged();
      if(!text.length) fail('Enter the code you want visitors to read.');
      if(editing) {
        const code=codeNode(s,ix,n);
        return {text:splice(s,code.open,code.close,replaceLiteral(s.slice(code.open,code.close),text)),focus:n.start};
      }
      markup='<pre style="max-width: 100%; overflow: auto;"><code>'+escapeText(text)+'</code></pre>';
    } else if(kind==='html') {
      if(editing && text===current.text) return unchanged();
      checkedHTML(text,false);
      if(editing) {
        checkParent(ix,n,'div',index(text).nodes);
        return verifyParent(splice(s,n.open,n.close,text),n.start,ix.nodes[n.parent]?.start);
      }
      markup='<div data-html-snippet>'+text+'</div>';
    } else if(op.fields) {
      if(editing && !current.fields) fail('Use Embed code to edit this iframe.');
      if(editing && op.url===current.url && op.title===current.title) return unchanged();
      const url=frameURL(op.url), title=op.title;
      if(typeof title!=='string' || !title.trim()) fail('Give the iframe an accessible title.');
      markup=editing ? current.text : '<iframe width="480" height="270" style="max-width: 100%; border: 0;"></iframe>';
      if(!editing || url!==current.url) markup=attribute(markup,index(markup).nodes[0],'src',url);
      if(!editing || title!==current.title) markup=attribute(markup,index(markup).nodes[0],'title',title);
    } else {
      if(editing && text===current.text) return unchanged();
      checkedHTML(text,true);
      markup=text;
    }
    if(editing) return verifyParent(splice(s,n.start,n.end,markup),n.start+index(markup).nodes[0].start,ix.nodes[n.parent]?.start);
    return insert(s,id,markup,op.before,op.point);
  }
  function designFrame(s,n,marker) {
    // Keep the real element for layout and selection. Only the preview gets the inert document.
    const keep=['class','id','title','aria-label','style','width','height','align','frameborder','hidden'];
    const attrs=keep.filter(key=>n.attrs[key]).map(key=>{
      const a=n.attrs[key], q=a.quote||'"';
      return ' '+key+'='+q+(a.quote?a.value:a.value.replace(/"/g,'&quot;'))+q;
    }).join('');
    // Mirror the original src for the attribute inspector without making it a loadable URL.
    const src=n.attrs.src;
    const sourceHint=src ? ' '+marker+'-src="'+src.value.replace(/"/g,'&quot;')+'"' : '';
    const label=n.attrs.title?.value || (n.attrs.srcdoc?'Inline document':n.attrs.src?.value || 'Embedded page');
    let caption;
    try {caption=escapeText(plainValue(label));} catch {caption=escapeText(label);}
    const card='<meta charset="utf-8"><style>*{box-sizing:border-box}html,body{height:100%;margin:0}body{display:grid;place-content:center;text-align:center;padding:8px;background:#ebf0e9;color:#244c3b;font:14px system-ui;overflow:hidden}b{font-size:17px}span{overflow-wrap:anywhere}</style><b>Iframe embed</b><span>'+caption+'</span>';
    return '<iframe '+marker+'="'+n.id+'"'+attrs+sourceHint+' tabindex="-1" sandbox srcdoc="'+escapeAttr(card)+'"></iframe>';
  }
  function info(s, marker) {
    const ix=index(s); let html=s;
    if(!ix.error && marker) {
      if(s.toLowerCase().includes(marker))fail('Preview marker collision.');
      const pieces=[];let pos=0;
      for(const n of ix.nodes) {
        if(n.tag==='iframe') {
          pieces.push(s.slice(pos,n.start),designFrame(s,n,marker)); pos=n.end; continue;
        }
        const at=n.start+1+n.tag.length;pieces.push(s.slice(pos,at),' '+marker+'="'+n.id+'"');pos=at;
      }
      pieces.push(s.slice(pos));html=pieces.join('');
    }
    return {html,error:ix.error,nodes:ix.nodes.map(n=>({id:n.id,parent:n.parent,depth:n.depth,tag:n.tag,
      label:n.tag+(n.attrs.id?'#'+n.attrs.id.value:'')+(n.attrs.class?'.'+n.attrs.class.value.trim().split(/\s+/).join('.'):''),
      name:(n.attrs['aria-label']?.value || n.attrs.alt?.value || n.attrs.id?.value ||
        (n.tag==='iframe' ? n.attrs.title?.value || 'Iframe embed' : n.attrs['data-html-snippet'] ? 'Custom HTML' : '') ||
        shapeNames.get(n.attrs.class?.value.trim().split(/\s+/).find(name => shapeNames.has(name))) ||
        (/^(h[1-6]|p|a|button|label|li|output)$/.test(n.tag) ? s.slice(n.open,Math.min(n.close,n.open+55)).split('<')[0].trim() : '') || n.tag),
      ...(snippetKind(n) ? {snippet:snippetKind(n)} : {}),start:n.start,length:n.open-n.start}))};
  }
  function attribute(s,n,key,value) {
    if(!/^(id|class|title|href|src|alt|type|sizes|value|for|aria-label|style)$/.test(key))fail('Edit this attribute in Code.');
    const a=n.attrs[key], v=escapeAttr(value);
    if(!a)return splice(s,n.start+1+n.tag.length,n.start+1+n.tag.length,' '+key+'="'+v+'"');
    if(!a.quote && !a.value)fail('Edit this valueless attribute in Code.');
    return splice(s,a.start,a.end,a.quote?v:'"'+v+'"');
  }
  function checkParent(ix, parent, child, descendants) {
    if (!accepts(parent.tag,child)) fail('This element requires a specific container. Choose a compatible parent.');
    const tags = new Set(descendants.map(row=>row.tag));
    for (let a=parent; a; a=ix.nodes[a.parent]) {
      if (a.tag==='form' && tags.has('form')) fail('A form cannot contain another form.');
      if (['article','aside','footer','header','nav'].includes(a.tag) && tags.has('main')) fail('Place main content outside this landmark.');
      if (['header','footer'].includes(a.tag) && (tags.has('header') || tags.has('footer'))) fail('A header or footer cannot contain another header or footer.');
      if (['a','button'].includes(a.tag) && ['a','button','input','select','textarea','details','audio','video'].some(t=>tags.has(t)))
        fail('Interactive controls cannot be nested here.');
    }
  }
  function slot(ix,parent,before,child,skip=-1) {
    let anchor = before==null ? null : ix.nodes[before];
    if(before!=null && (!anchor || anchor.parent!==parent.id)) fail('Insertion point changed.');
    const kids=ix.nodes.filter(n=>n.parent===parent.id && n.id!==skip);
    // Keep semantic captions and disclosures at their authored boundaries.
    if(parent.tag==='figure' && child!=='figcaption' && kids.length>1 && !anchor && kids.at(-1).tag==='figcaption') anchor=kids.at(-1);
    const order=kids.filter(n=>n.id!==anchor?.id).map(n=>n.tag);
    if(anchor)order.splice(kids.indexOf(anchor),0,child,anchor.tag);else order.push(child);
    const first={details:'summary',fieldset:'legend',figure:'figcaption'}[parent.tag];
    if(first && order.includes(first) && (order.filter(t=>t===first).length>1 || (order[0]!==first && !(parent.tag==='figure'&&order.at(-1)===first))))
      fail('Keep the caption, summary or legend at its required edge.');
    return anchor;
  }
  function verifyParent(text,focus,parentStart) {
    const result=index(text);
    const row=result.nodes.find(n=>n.start===focus);
    if(result.error || !row || result.nodes[row.parent]?.start!==parentStart)
      fail('The source has an implicit boundary here. Make the closing tag explicit in Code.');
    return {text,focus};
  }
  function insert(s,id,markup,before,atPoint) {
    const {n,ix}=mapped(s,id), parts=index(markup).nodes;
    checkParent(ix,n,parts[0].tag,parts);
    const anchor=slot(ix,n,before,parts[0].tag);
    const at=anchor?anchor.start:n.close;
    if(atPoint && Number.isFinite(atPoint.x) && Number.isFinite(atPoint.y)) {
      const child=index(markup).nodes[0];
      let style=declaration(child.attrs.style?.value || '', 'position','absolute');
      style=declaration(style,'left',Math.round(atPoint.x)+'px');
      style=declaration(style,'top',Math.round(atPoint.y)+'px');
      // All inserted values above are numeric positions. Preserve existing HTML entities in the style.
      const attr=child.attrs.style;
      markup=attr ? splice(markup,attr.start,attr.end,attr.quote ? style : '"'+style.replace(/"/g,'&quot;')+'"')
                  : attribute(markup,child,'style',style);
    }
    return verifyParent(splice(s,at,at,markup),at+parts[0].start,n.start);
  }
  // Scan CSS structural delimiters without interpreting strings, comments, URLs, or functions as syntax.
  function boundaries(s, delimiters) {
    const out=[];let quote='',paren=0,bracket=0;
    for(let i=0;i<s.length;i++) {
      const c=s[i];
      if(c==='\\'){i++;continue;}
      if(quote){if(c===quote)quote='';continue;}
      if(c==='"'||c==="'"){quote=c;continue;}
      if(s.startsWith('/*',i)){i=s.indexOf('*/',i+2);if(i<0)fail('Incomplete CSS comment.');i++;continue;}
      if(c==='(')paren++;if(c===')')paren--;if(c==='[')bracket++;if(c===']')bracket--;
      if(paren<0||bracket<0)fail('Unbalanced CSS.');
      if(!paren&&!bracket&&delimiters.includes(c))out.push(i);
    }
    if(quote||paren||bracket)fail('Incomplete CSS value.');
    return out;
  }
  function declaration(body,prop,value,important=false) {
    if(!/^[a-z][\w-]*$/.test(prop) || !value.trim() || boundaries(value,';{}').length || /<\/style/i.test(value))fail('Enter one CSS declaration value.');
    const points=boundaries(body,';{}'); if(points.some(i=>body[i]!==';'))fail('Nested CSS needs Code.');
    let from=0, hit;
    for(const to of [...points,body.length]) {
      const part=body.slice(from,to), m=/^(?:\s|\/\*[\s\S]*?\*\/)*([\w-]+)\s*:\s*/.exec(part);
      if(m&&m[1].toLowerCase()===prop){
        if(hit)fail('Multiple fallback declarations. Choose the intended one in Code.');
        const tail=part.slice(m[0].length);
        if(tail.includes('/*'))fail('This value contains a comment. Edit it in Code.');
        const end=tail.search(/(?:\s*!important)?\s*$/i);
        hit=[from+m[0].length,from+m[0].length+end,/^\s*!important/i.test(tail.slice(end))];
      }
      from=to+1;
    }
    if(hit)return splice(body,hit[0],hit[1],value.trim()+(important&&!hit[2]?' !important':''));
    const trailing=body.match(/\s*$/)[0],prefix=body.slice(0,body.length-trailing.length);
    return prefix+(prefix&&!prefix.endsWith(';')?';':'')+(prefix?' ':'')+prop+': '+value.trim()+(important?' !important':'')+';'+trailing;
  }
  function ruleList(css) {
    let depth=0, start=0, brace=-1;const rules=[];
    for(const i of boundaries(css,';{}')) {
      if(css[i]==='{'){if(depth++===0)brace=i;}
      else if(css[i]==='}') {
        if(--depth<0)fail('Unbalanced CSS block.');
        if(depth===0){rules.push({head:css.slice(start,brace).replace(/\/\*[\s\S]*?\*\//g,'').trim(),open:brace+1,close:i});start=i+1;}
      } else if(!depth){rules.push({head:css.slice(start,i).trim(),open:-1,close:i});start=i+1;}
    }
    if(depth || css.slice(start).replace(/\/\*[\s\S]*?\*\//g,'').trim())fail('Incomplete CSS rule.');
    return rules;
  }
  function locateRule(css,path,selector) {
    let offset=0, start=0, sub=css, r;
    for(const i of path) {
      r=ruleList(sub)[i]; if(!r||r.open<0)fail('CSS rule has no reliable source range.');
      start=offset+r.open-1;
      offset+=r.open;sub=sub.slice(r.open,r.close);
    }
    if(!r||r.head.replace(/\s+/g,' ').trim()!==selector.replace(/\s+/g,' ').trim())fail('Browser normalized this selector. Edit it in Code.');
    return {offset,sub,start};
  }
  function editRule(css,path,selector,prop,value) {
    const {offset,sub}=locateRule(css,path,selector);
    return splice(css,offset,offset+sub.length,declaration(sub,prop,value));
  }
  function ruleRange(source,o) {
    let base=0,css=source;
    if(o.styleIndex>=0) {
      const ix=index(source);if(ix.error)fail(ix.error);
      const n=ix.nodes.filter(n=>n.tag==='style')[o.styleIndex];if(!n)fail('Stylesheet moved.');
      base=n.open;css=source.slice(n.open,n.close);
    }
    const r=locateRule(css,o.path,o.selector);
    return [base+r.start,r.sub.length+2];
  }
  function deviceFrame(s,id,op,n,ix) {
    const queries={phone:'(max-width: 600px)',tablet:'(min-width: 601px) and (max-width: 1024px)',desktop:'(min-width: 1025px)'};
    if(!Object.hasOwn(queries,op.band))fail('Unknown layout breakpoint.');
    const tag=ix.nodes.filter(t=>t.tag==='style' && t.attrs.id?.value==='webbench-layout' && ix.nodes[t.parent]?.tag==='head');
    if(tag.length!==1 || !ix.nodes.some(t=>t.tag==='body' && t.attrs['data-free-page']))fail('This page has no free-canvas layout stylesheet.');
    const members=op.kind==='selectionFrames'?op.members:[{id,values:op.kind==='move'?{left:Math.round(op.x),top:Math.round(op.y)}:op.values}];
    if(!Array.isArray(members)||!members.length||members[0].id!==id||new Set(members.map(m=>m.id)).size!==members.length)
      fail('The layer selection changed.');
    const owner=tag[0],query='@media '+queries[op.band],nl=s.includes('\r\n')?'\r\n':'\n';
    let css=s.slice(owner.open,owner.close);
    function uniqueRule(body,head){
      const matches=ruleList(body).filter(rule=>rule.head===head);
      if(matches.length>1)fail('This layout has duplicate rules. Choose the intended one in Code.');
      return matches[0];
    }
    const media=uniqueRule(css,query);
    let body=media?css.slice(media.open,media.close):'', patches=[];
    const names=new Set(ix.nodes.map(row=>row.attrs.id?.value).filter(Boolean));
    const sequence={};
    for(const member of members){
      const row=ix.nodes[member.id];
      if(!row||row.parent!==n.parent||!member.values||typeof member.values!=='object')fail('Choose sibling objects in one container.');
      const values=Object.entries(member.values);
      if(!values.length)continue;
      if(op.kind==='selectionFrames' && values.some(([key])=>!['left','top'].includes(key)))fail('A group move changes only position.');
      let name=row.attrs.id?.value;
      if(row.attrs.id){if(!/^[A-Za-z_][\w-]*$/.test(name)||ix.nodes.filter(t=>t.attrs.id?.value===name).length!==1)fail('Give the layer a unique simple ID in Inspect.');}
      else {
        let i=sequence[row.tag]||1;while(names.has('wb-'+row.tag+'-'+i))i++;
        name='wb-'+row.tag+'-'+i;names.add(name);sequence[row.tag]=i+1;
        const at=row.start+1+row.tag.length;patches.push({a:at,b:at,text:' id="'+name+'"'});
      }
      const rule=uniqueRule(body,'#'+name);let decl=rule?body.slice(rule.open,rule.close):'';
      for(const [key,v] of values){
        if(!['left','top','width','height','z-index'].includes(key)||!Number.isFinite(v)||Math.abs(v)>1000000||
          (['width','height'].includes(key)&&v<1))fail('Invalid layer geometry.');
        decl=declaration(decl,key,String(v)+(key==='z-index'?'':'px'),true);
      }
      if(op.promote)decl=declaration(decl,'display','inline-block',true);
      body=rule?splice(body,rule.open,rule.close,decl):body+(body.endsWith(nl)?'':nl)+'  #'+name+' { '+decl+' }'+nl;
    }
    if(!members.some(member=>Object.keys(member.values).length))return {text:s,focus:n.start};
    css=media?splice(css,media.open,media.close,body):css+nl+query+' {'+body+'}'+nl;
    patches.push({a:owner.open,b:owner.close,text:css});
    let cursor=0,focus=n.start;const parts=[];
    for(const patch of patches.sort((a,b)=>a.a-b.a)){
      parts.push(s.slice(cursor,patch.a),patch.text);cursor=patch.b;
      if(patch.b<=n.start)focus+=patch.text.length-(patch.b-patch.a);
    }
    parts.push(s.slice(cursor));return {text:parts.join(''),focus};
  }
  function run(s,id,op) {
    const {n,ix}=mapped(s,id);
    if(op.band && ['frame','selectionFrames','move'].includes(op.kind))return deviceFrame(s,id,op,n,ix);
    switch(op.kind) {
      case 'snippet': return editSnippet(s,id,op);
      case 'pageTitle': {
        const titles=ix.nodes.filter(row=>row.tag==='title' && ix.nodes[row.parent]?.tag==='head');
        const head=ix.nodes.find(row=>row.tag==='head');
        if(!head||titles.length>1)fail('Choose the intended document title in Code.');
        const title=escapeText(op.value);
        return {text:titles.length?splice(s,titles[0].open,titles[0].close,title):splice(s,head.close,head.close,'<title>'+title+'</title>'),focus:n.start};
      }
      case 'text':
        if(voids.has(n.tag)||raw.has(n.tag)||s.slice(n.open,n.close).includes('<'))fail('This element contains markup or raw code. Edit its source directly.');
        return {text:splice(s,n.open,n.close,escapeText(op.value)),focus:n.start};
      case 'attr': return {text:attribute(s,n,op.key,op.value),focus:n.start};
      case 'insert': return insert(s,id,palette[op.item]||fail('Unknown palette item.'),op.before,op.point);
      case 'asset': return insert(s,id,'<img '+(op.point?'style="width: 192px; height: auto;" ':'')+'src="'+escapeAttr(op.url)+'" alt="'+escapeAttr(op.alt)+'">',op.before,op.point);
      case 'relocate': {
        const moving=mapped(s,op.child).n;
        if(!voids.has(moving.tag)&&moving.close===moving.end)fail('Move implicitly closed markup in Code.');
        if(['html','head','body','script','style','base','link','meta','title'].includes(moving.tag))fail('Move this document-level element in Code.');
        if(n.start>=moving.start && n.start<moving.end)fail('An element cannot contain itself.');
        checkParent(ix,n,moving.tag,ix.nodes.filter(k=>k.start>=moving.start && k.start<moving.end));
        if(op.before===moving.id && n.id===moving.parent && !op.point)return {text:s,focus:moving.start};
        const before=slot(ix,n,op.before,moving.tag,moving.id);
        if(!op.point && n.id===moving.parent) {
          const siblings=ix.nodes.filter(k=>k.parent===n.id);
          const next=siblings[siblings.findIndex(k=>k.id===moving.id)+1];
          if((next?.id??null)===(before?.id??null))return {text:s,focus:moving.start};
        }
        const at=before?before.start:n.close;
        let fragment=s.slice(moving.start,moving.end);
        if(op.point) {
          const {x,y}=op.point;
          if(![x,y].every(v=>Number.isFinite(v)&&Math.abs(v)<=1000000))fail('Invalid drop position.');
          const root=index(fragment).nodes[0], style=root.attrs.style;
          if(style && (!style.quote || style.value.includes('&')))fail('Edit this encoded or unquoted style in Code.');
          let css=declaration(style?.value || '', 'position','absolute');
          css=declaration(css,'left',Math.round(x)+'px');
          css=declaration(css,'top',Math.round(y)+'px');
          fragment=style ? splice(fragment,style.start,style.end,css) : attribute(fragment,root,'style',css);
        }
        if(at===moving.start||at===moving.end)
          return {text:splice(s,moving.start,moving.end,fragment),focus:moving.start};
        // Move the whole source line when both boundaries have their own indentation.
        const indentAt=pos=>s.slice(s.lastIndexOf('\n',pos-1)+1,pos);
        const oldIndent=indentAt(moving.start), destIndent=indentAt(at);
        const newline=/^(\r?\n)/.exec(s.slice(moving.end));
        if(!op.point && newline && /^[ \t]*$/.test(oldIndent) && /^[ \t]*$/.test(destIndent)) {
          const start=moving.start-oldIndent.length,end=moving.end+newline[0].length;
          let indent=destIndent;
          if(!before){
            const sibling=ix.nodes.find(row=>row.parent===n.id && row.id!==moving.id && /^[ \t]*$/.test(indentAt(row.start)));
            indent=sibling ? indentAt(sibling.start) : destIndent+(destIndent.includes('\t')?'\t':'  ');
          }
          const target=at-destIndent.length;
          const offset=target-(end<=target ? end-start : 0);
          const result=splice(splice(s,start,end,''),offset,offset,indent+fragment+newline[0]);
          return verifyParent(result,offset+indent.length,n.start-(end<=n.start?end-start:0));
        }
        const rest=splice(s,moving.start,moving.end,'');
        const offset=at>moving.start?at-(moving.end-moving.start):at;
        return verifyParent(splice(rest,offset,offset,fragment),offset,n.start-(moving.end<=n.start?moving.end-moving.start:0));
      }
      case 'reorder': {
        const siblings=ix.nodes.filter(x=>x.parent===n.parent), dest=siblings[siblings.findIndex(x=>x.id===id)+op.step];
        if(dest && [dest,n].some(x=>!voids.has(x.tag)&&x.close===x.end))fail('Reorder implicitly closed elements in Code.');
        if(!dest || n.parent<0)fail('Already at the edge of this container.');
        const left=n.start<dest.start?n:dest,right=n.start<dest.start?dest:n;
        const gap=s.slice(left.end,right.start); if(gap.trim())fail('Intervening text or comments need an explicit move in Code.');
        const text=s.slice(0,left.start)+s.slice(right.start,right.end)+gap+s.slice(left.start,left.end)+s.slice(right.end);
        return {text,focus:op.step===-1?left.start:left.start+right.end-right.start+gap.length};
      }
      case 'deleteLayers': {
        if(!Array.isArray(op.ids)||!op.ids.length||op.ids[0]!==id||new Set(op.ids).size!==op.ids.length)
          fail('Select the layers to delete.');
        const ranges=op.ids.map(k=>ix.nodes[k]);
        for(const row of ranges){
          if(!row||row.parent!==n.parent||row.parent<0||raw.has(row.tag)||
             ['html','body','head','meta','link','base','template'].includes(row.tag) ||
             (!voids.has(row.tag)&&row.close===row.end))fail('Remove this document structure in Code.');
        }
        let cursor=0;const parts=[];
        for(const row of ranges.sort((a,b)=>a.start-b.start)){parts.push(s.slice(cursor,row.start));cursor=row.end;}
        parts.push(s.slice(cursor));return {text:parts.join(''),focus:ix.nodes[n.parent].start};
      }
      case 'selectionFrames': {
        const members=op.members;
        if(!Array.isArray(members)||members.length<2||members[0].id!==id||n.parent<0)
          fail('Select sibling layers in the same container.');
        const seen=new Set(),patches=[];
        for(const member of members) {
          const row=ix.nodes[member.id];
          if(!Number.isInteger(member.id)||!row||row.parent!==n.parent||seen.has(row.id)||
              ['svg','math','template','noscript'].includes(row.tag))
            fail('The selection no longer maps to distinct sibling layers.');
          seen.add(row.id);
          const entries=Object.entries(member.values);
          if(!entries.length)continue;
          const a=row.attrs.style;
          if(a&&(!a.quote||a.value.includes('&')))fail('Open Code to edit this encoded or unquoted style.');
          let css=a?.value||'';
          for(const [key,value] of entries) {
            if(!['left','top'].includes(key)||!Number.isFinite(value)||Math.abs(value)>1000000)
              fail('Enter a valid layer position.');
            css=declaration(css,key,String(value)+'px');
          }
          const at=row.start+1+row.tag.length;
          patches.push(a?{a:a.start,b:a.end,text:css}:{a:at,b:at,text:' style="'+css+'"'});
        }
        const parts=[];
        let cursor=0,focus=n.start;
        for(const patch of patches.sort((a,b)=>a.a-b.a)) {
          if(patch.a<cursor)fail('Layer source ranges overlap.');
          parts.push(s.slice(cursor,patch.a),patch.text);
          if(patch.b<=n.start)focus+=patch.text.length-(patch.b-patch.a);
          cursor=patch.b;
        }
        parts.push(s.slice(cursor));return {text:parts.join(''),focus};
      }
      case 'free':
      case 'frame': {
        const a=n.attrs.style;
        if(a && (!a.quote || a.value.includes('&')))fail('Edit this encoded or unquoted style in Code.');
        const entries=Object.entries(op.values || {});
        if(!entries.length) return {text:s,focus:n.start};
        let css=a?.value || '';
        if(op.kind==='frame' && op.promote && entries.some(([k])=>['width','height'].includes(k)))css=declaration(css,'display','inline-block');
        if(op.kind==='free') {
          if(!['left','top','width'].every(k=>Object.hasOwn(op.values,k)) || entries.length!==3)
            fail('A free layer needs a measured position and width.');
          css=declaration(css,'position','absolute');
        }
        for(const [key,value] of entries) {
          if(!['left','top','width','height','z-index'].includes(key) || !Number.isInteger(value) ||
              Math.abs(value)>1000000 || (['width','height'].includes(key) && value<1))
            fail('Choose a valid pixel size, position or stacking level.');
          css=declaration(css,key,String(value)+(key==='z-index'?'':'px'));
        }
        return {text:a?splice(s,a.start,a.end,css):attribute(s,n,'style',css),focus:n.start};
      }
      case 'move':
      case 'inline': {
        const a=n.attrs.style;
        if(a && (a.value.includes('&')||!a.quote))fail('Use Code for encoded or unquoted inline CSS.');
        let css=a?a.value:'';
        const pairs=op.kind==='move'?[['left',Math.round(op.x)+'px'],['top',Math.round(op.y)+'px']]:[[op.prop,op.value]];
        if(op.kind==='move'){
          // Coordinates contain only numeric CSS tokens. All intervening CSS is already encoded as authored.
          if(!Number.isFinite(op.x)||!Number.isFinite(op.y))fail('Invalid position.');
          for(const [p,v] of pairs)css=declaration(css,p,v);
          return {text:a?splice(s,a.start,a.end,css):attribute(s,n,'style',css),focus:n.start};
        }
        css=declaration(css,op.prop,op.value,op.important===true);
        if(a){
          let first=0,oldEnd=a.value.length,newEnd=css.length;
          while(first<oldEnd && first<newEnd && a.value[first]===css[first])first++;
          while(oldEnd>first && newEnd>first && a.value[oldEnd-1]===css[newEnd-1]){oldEnd--;newEnd--;}
          const replacement=escapeAttr(css.slice(first,newEnd));
          return {text:splice(s,a.start+first,a.start+oldEnd,replacement),focus:n.start};
        }
        return {text:attribute(s,n,'style',css),focus:n.start};
      }
      case 'handler': {
        if(n.attrs.onclick)return {text:s,range:[n.attrs.onclick.start,n.attrs.onclick.end-n.attrs.onclick.start],focus:n.start};
        const body=ix.nodes.find(x=>x.tag==='body');if(!body)fail('Add an explicit body in Code first.');
        const uid=ensureID(s,n,ix), newline=s.includes('\r\n')?'\r\n':'\n';
        const js="document.getElementById('"+uid.id+"').addEventListener('click', () => {"+newline+'  // Write the click action here.'+newline+'});';
        let text=splice(s,body.close,body.close,newline+'<script>'+newline+js+newline+'</script>'+newline);
        if(!n.attrs.id)text=attribute(text,n,'id',uid.id);
        return {text,focus:n.start,range:[text.lastIndexOf('// Write the click action here.'),31]};
      }
      default: fail('Unknown source operation.');
    }
  }
  function ensureID(s,n,ix) {
    if(n.attrs.id) {
      const id=n.attrs.id.value;
      if(!/^[a-zA-Z_][\w-]*$/.test(id)||ix.nodes.filter(x=>x.attrs.id?.value===id).length!==1)fail('Use a unique simple ID or edit in Code.');
      return {id,text:s};
    }
    let i=1;while(s.includes('wb-'+n.tag+'-'+i))i++;
    const id='wb-'+n.tag+'-'+i;return {id,text:attribute(s,n,'id',id)};
  }
  function style(s,id,o) {
    const {n,ix}=mapped(s,id), nl=(o.external?o.css:s).includes('\r\n')?'\r\n':'\n';
    let selector=o.selector, base=s;
    if(!selector){const uid=ensureID(s,n,ix);selector='#'+uid.id;base=uid.text;}
    if(!/^[.#][\w-]+$/.test(selector))fail('Choose a simple ID or class.');
    const decl=declaration('',o.prop,o.value);
    let rule=selector+' { '+decl+' }';
    if(o.mobile){if(!Number.isInteger(o.width)||o.width<200||o.width>4000)fail('Breakpoint must be 200–4000 px.');rule='@media (max-width: '+o.width+'px) {'+nl+'  '+rule+nl+'}';}
    if(o.external)return {text:base,css:o.css+nl+rule+nl,focus:n.start};
    const nodes=index(base).nodes;
    const lastStyle=nodes.filter(x=>x.tag==='style' && !x.attrs.media && !x.attrs.type && nodes[x.parent]?.tag==='head').pop();
    if(lastStyle){const added=nl+rule+nl;return {text:splice(base,lastStyle.close,lastStyle.close,added),focus:n.start+(lastStyle.close<n.start?added.length:0)};}
    const head=nodes.find(x=>x.tag==='head');if(!head)fail('A local style rule needs an explicit head or a linked stylesheet.');
    const added='<style>'+nl+rule+nl+'</style>'+nl;return {text:splice(base,head.close,head.close,added),focus:n.start+(head.close<n.start?added.length:0)};
  }
  function headSlot(s, ix, markup) {
    const heads=ix.nodes.filter(n=>n.tag==='head' && (n.parent<0 || ix.nodes[n.parent]?.tag==='html'));
    if(heads.length>1)fail('Multiple document heads found. Choose the intended head in Code.');
    const nl=s.includes('\r\n')?'\r\n':'\n';
    if(heads.length){
      const at=heads[0].close, line=s.lastIndexOf('\n',at-1)+1;
      const indent=s.slice(line,at);
      const insertion=/^[ \t]*$/.test(indent)?'  '+markup+nl+indent:markup;
      return splice(s,at,at,insertion);
    }
    // HTML also permits implicit html and head tags. Metadata before body content belongs to that head.
    const html=ix.nodes.find(n=>n.tag==='html' && n.parent<0);
    const preamble=/^(?:\s|<!--[\s\S]*?-->|<!doctype\s[^>]*>)+/i.exec(s)?.[0].length||0;
    const at=html?html.open:preamble;
    return splice(s,at,at,nl+markup+nl);
  }
  function icons(s) {
    const ix=index(s);if(ix.error)fail(ix.error);
    function inHead(n) {
      if(ix.nodes[n.parent]?.tag==='head'){const head=ix.nodes[n.parent];return head.parent<0 || ix.nodes[head.parent]?.tag==='html' && ix.nodes[head.parent].parent<0;}
      const root=ix.nodes[n.parent];
      if(root && root.tag!=='html')return false;
      return !ix.nodes.some(p=>p.start<n.start && p.parent===n.parent && !['html','head','meta','link','title','script','style','base','noscript','template'].includes(p.tag));
    }
    const links=ix.nodes.filter(n=>n.tag==='link' && inHead(n) &&
      (n.attrs.rel?.value||'').toLowerCase().split(/\s+/).includes('icon'));
    const base=ix.nodes.find(n=>n.tag==='base' && inHead(n) && n.attrs.href);
    return {base:base?.attrs.href?.value||'',links:links.map(n=>({id:n.id,href:n.attrs.href?.value||'',sizes:n.attrs.sizes?.value||'',media:n.attrs.media?.value||''}))};
  }
  function setIcon(s,id,url,size,selectedID) {
    if(![16,32,48,64].includes(size)||typeof url!=='string'||
      !/^(?:data:image\/png;base64,[A-Za-z0-9+/]+=*|(?:\.\.\/)*(?:assets\/)?[A-Za-z0-9_.%-]+\.png)$/.test(url))
      fail('Choose a PNG favicon from the editor.');
    const meta=icons(s),ix=index(s);
    if(id===-1){
      if(meta.links.length)fail('Choose an existing favicon link.');
      const text=headSlot(s,ix,'<link rel="icon" type="image/png" sizes="'+size+'x'+size+'" href="'+url+'">');
      const inserted=icons(text).links[0], next=index(text);
      const focus=ix.nodes[selectedID]?next.nodes[selectedID+(selectedID>=inserted.id?1:0)].start:0;
      return {text,focus};
    }
    if(!meta.links.some(l=>l.id===id))fail('The favicon link changed. Reopen the editor.');
    const n=ix.nodes[id];let fragment=s.slice(n.start,n.open);
    for(const [key,value] of [['href',url],['type','image/png'],['sizes',size+'x'+size]]){
      const row=index(fragment).nodes[0];
      if(row.attrs[key]?.value!==value)fragment=attribute(fragment,row,key,value);
    }
    const anchor=ix.nodes[selectedID],delta=fragment.length-(n.open-n.start);
    return {text:splice(s,n.start,n.open,fragment),focus:anchor?anchor.start+(anchor.start>n.start?delta:0):n.start};
  }
  function paintCSS(style,prop,value,important) {
    // A later shorthand resets earlier longhands. Edit only the declarations after the last such reset.
    let from=0, start=0;
    for(const end of [...boundaries(style,';'),style.length]){
      const part=style.slice(start,end);
      if(/^(?:\s|\/\*[\s\S]*?\*\/)*(?:background|all)\s*:/i.test(part))from=Math.min(end+1,style.length);
      start=end+1;
    }
    if(!from)return declaration(style,prop,value,important);
    const before=style.slice(0,from),after=style.slice(from);
    const gap=before.trimEnd().endsWith(';')?' ':'; ';
    return before+(after.trim()?'':gap)+declaration(after,prop,value,important);
  }
  function backgrounds(s,scope,parts,focusID) {
    const ix=index(s);if(ix.error)fail(ix.error);
    if(!['page','element'].includes(scope)||!Array.isArray(parts)||parts.length>(scope==='page'?2:1))fail('Invalid paint target.');
    const applied=new Set(),patches=[],implicit=[];
    for(const p of parts){
      const node=p.id>=0?mapped(s,p.id).n:null;
      const tag=node?.tag||(p.id===-1?'html':p.id===-2?'body':'');
      if(applied.has(p.id)||!tag||scope==='page'&&!['html','body'].includes(tag)||
        scope==='element'&&(!node||['html','body','head','script','style','link','meta','title'].includes(tag)))fail('Select a page object to paint.');
      if(!node && ix.nodes.some(n=>n.tag===tag))fail('Page layout changed. Select it again.');
      applied.add(p.id);
      if(p.color!=null && !/^(?:transparent|#[\da-f]{6}(?:[\da-f]{2})?)$/i.test(p.color))fail('Invalid background color.');
      const attr=node?.attrs.style;
      if(attr&&(!attr.quote||attr.value.includes('&')))fail('Edit this encoded inline style in Code.');
      const paint=body=>{
        if(p.color!=null)body=paintCSS(body,'background-color',p.color,!!p.strongColor);
        if(p.image===true)body=paintCSS(body,'background-image','none',!!p.strongImage);
        return body;
      };
      if(!node){implicit.push({tag,paint});continue;}
      const css=paint(attr?.value||'');
      if(css===(attr?.value||''))continue;
      const at=node.start+1+node.tag.length;
      patches.push(attr?{a:attr.start,b:attr.end,text:css}:{a:at,b:at,text:' style="'+css+'"'});
    }
    let text=s;
    for(const p of patches.sort((a,b)=>b.a-a.a))text=splice(text,p.a,p.b,p.text);
    if(implicit.length){
      const tree=index(text);
      const sheets=tree.nodes.filter(n=>n.attrs.id?.value==='webbench-page-paint');
      if(sheets.length>1||(sheets.length && sheets[0].tag!=='style'))fail('The page paint stylesheet has a conflicting ID.');
      const sheet=sheets[0];let css=sheet?text.slice(sheet.open,sheet.close):'';
      for(const target of implicit){
        const selector=target.tag==='html'?':root':':root > body';
        const hits=ruleList(css).filter(r=>r.head===selector);
        if(hits.length>1)fail('Choose the matching paint rule in Code.');
        const r=hits[0];
        css=r?splice(css,r.open,r.close,target.paint(css.slice(r.open,r.close))):css+selector+' { '+target.paint('')+' } ';
      }
      text=sheet?splice(text,sheet.open,sheet.close,css):headSlot(text,tree,'<style id="webbench-page-paint">'+css+'</style>');
    }
    // An inserted metadata element shifts source IDs. Use the change in node count to retain content selection.
    const next=index(text), old=ix.nodes[focusID];
    const offset=old && !['html','head'].includes(old.tag)?next.nodes.length-ix.nodes.length:0;
    return {text,focus:next.nodes[focusID+offset]?.start??0};
  }

  function scripts(source){
    const ix=index(source);
    if(ix.error)fail(ix.error);
    return ix.nodes.filter(n=>n.tag==='script').map(n=>({
      src:n.attrs.src?.value||'', start:n.open,end:n.close,
      javascript:!n.attrs.type || /^(module|(?:text|application)\/(?:java|ecma)script)$/i.test(n.attrs.type.value)
    }));
  }
  function replaceRule(source,o) {
    if(o.styleIndex<0)return editRule(source,o.path,o.selector,o.prop,o.value);
    const ix=index(source);if(ix.error)fail(ix.error);
    const n=ix.nodes.filter(n=>n.tag==='style')[o.styleIndex];if(!n)fail('Stylesheet moved.');
    return splice(source,n.open,n.close,editRule(source.slice(n.open,n.close),o.path,o.selector,o.prop,o.value));
  }
  return {index,snippetDetails,rows:s=>{const result=info(s);if(result.error)fail(result.error);return result.nodes;},info,run,style,replaceRule,ruleRange,scripts,palette,catalog,accepts,tagFor,parentRules:()=>rules,icons,setIcon,backgrounds,paintCSS};
})();
if(typeof module!=='undefined')module.exports=WebBench;
