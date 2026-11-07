// Source-coordinate operations shared by the isolated canvas and the portable tests.
// All positions and selections are UTF-16. Only the returned interval is replaced.
'use strict';
const Writing = (() => {
  const blocks = new Set('p h1 h2 h3 h4 h5 h6 li td th blockquote figcaption dt dd div main section article header footer aside body label button output a span strong em'.split(' '));
  const inline = new Set('a abbr b bdi bdo cite code del em i ins kbd mark q s samp small span strong sub sup time u var'.split(' '));
  const paragraphs = new Set('p h1 h2 h3 h4 h5 h6'.split(' '));
  const containers = new Set('div main section article header footer aside body blockquote td th'.split(' '));
  const esc = value => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const attr = value => esc(value).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  const refuse = reason => { throw Error(reason); };
  function boundaries(raw, rendered, decode) {
    // A rendered character can span an entity or CRLF. Keep the exact original spelling.
    const offsets = [0];
    let visible = '', pos = 0;
    while (pos < raw.length) {
      const start = pos;
      let value;
      if (raw[pos] === '&') {
        const match = /^(?:&#(?:x[\da-f]+|\d+);?|&[A-Za-z][\dA-Za-z]*;)/i.exec(raw.slice(pos));
        if (match) {
          value = decode(match[0]);
          pos += match[0].length;
        }
      }
      if (value == null) {
        if (raw[pos] === '\r') {
          value = '\n';
          pos += raw[pos + 1] === '\n' ? 2 : 1;
        } else {
          value = String.fromCodePoint(raw.codePointAt(pos));
          pos += value.length;
        }
      }
      visible += value;
      if (value === raw.slice(start, pos) && value.length > 1 && value[0] === '&') {
        for (let i = 1; i < value.length; i++) offsets.push(start + i);
      } else {
        for (let i = 1; i < value.length; i++) offsets.push(null);
      }
      offsets.push(pos);
    }
    if (visible !== rendered) refuse('The displayed text differs from its source. Edit this passage in Code.');
    return offsets;
  }
  function plan(source, rows, id, a, b, op) {
    const host = rows[id];
    if (!host || !blocks.has(host.tag) || a < host.open || b > host.close || a > b)
      refuse('Choose text within one editable paragraph or label.');
    function result(start, end, insert, caret, endCaret = caret, first = host, last = first) {
      return {start, end, insert, caret, endCaret, first: first.id, last: last.id};
    }
    const selected = source.slice(a, b);
    function ancestors(pos) {
      return rows.filter(n => n.id > host.id && n.start >= host.open && n.end <= host.close &&
        n.end > n.open && n.open <= pos && pos <= n.close);
    }
    const left = ancestors(a), right = ancestors(b);
    function safeSelection() {
      if (left.map(n => n.id).join() !== right.map(n => n.id).join() ||
          left.some(n => !inline.has(n.tag)) || /<!--/.test(selected) ||
          rows.some(n => n.start >= a && n.end <= b && !inline.has(n.tag) && n.tag !== 'br'))
        refuse('This selection crosses a structure with independent markup. Edit it in Code.');
    }
    function pair(tag, value) {
      const open = '<' + tag + '>', close = '</' + tag + '>';
      return result(a, b, open + value + close, a + open.length, a + open.length + value.length);
    }
    function splitBlock(middle, nextTag) {
      safeSelection();
      if (host.end === host.close) refuse('This paragraph has an implied closing tag. Split it in Code.');
      if (left.some(n => Object.keys(n.attrs).length))
        refuse('Splitting this inline element would duplicate its attributes. Place the caret just outside it.');
      const endInline = left.slice().reverse().map(n => '</' + n.tag + '>').join('');
      const startInline = left.map(n => '<' + n.tag + '>').join('');
      const line = source.slice(source.lastIndexOf('\n', host.start - 1) + 1, host.start);
      const gap = source.includes('\n') && /^\s*$/.test(line) ? (source.includes('\r\n') ? '\r\n' : '\n') + line : '';
      const addition = endInline + '</' + host.tag + '>' + gap + middle + '<' + nextTag + '>' + startInline;
      // When splitting a heading the old closing tag must close the new paragraph.
      if (host.tag === nextTag) return result(a,b,addition,a+addition.length);
      const closing = source.slice(host.close,host.end).replace(/^<\/[\w-]+/,'</'+nextTag);
      return result(a, host.end, addition + source.slice(b, host.close) + closing, a + addition.length);
    }
    switch (op.kind) {
    case 'paste': {
      const lines = op.value.split(/\r\n|\r|\n/);
      if (lines.length === 1 || !(paragraphs.has(host.tag) || host.tag === 'li'))
        return plan(source,rows,id,a,b,{kind:'text',value:op.value});
      const next = host.tag === 'li' ? 'li' : 'p';
      const split = splitBlock('',next);
      const cut = split.caret - a;
      const carry = left.map(n=> '<' + n.tag + '>').join('');
      const endCarry = left.slice().reverse().map(n=> '</' + n.tag + '>').join('');
      const line = source.slice(source.lastIndexOf('\n',host.start-1)+1,host.start);
      const gap = source.includes('\n') && /^\s*$/.test(line) ? (source.includes('\r\n') ? '\r\n' : '\n') + line : '';
      const rest = lines.slice(1).map(esc).join(endCarry+'</'+next+'>'+gap+'<'+next+'>'+carry);
      const prefix = esc(lines[0]) + split.insert.slice(0,cut) + rest;
      return result(a,split.end,prefix+split.insert.slice(cut),a+prefix.length);
    }
    case 'text': case 'break': {
      if ([...left,...right].some(n=>!inline.has(n.tag)) || /<!--/.test(selected) ||
          rows.some(n=>n.start>=a && n.end<=b && !inline.has(n.tag) && n.tag!=='br'))
        refuse('This selection includes an object or comment. Edit the passage in Code.');
      let common = 0;
      while (common<left.length && common<right.length && left[common].id===right[common].id) common++;
      // Keep the unselected prefixes and suffixes in their original inline wrappers.
      const closeLeft = left.slice(common).reverse().map(n=>source.slice(n.close,n.end)).join('');
      const openRight = right.slice(common).map(n=>source.slice(n.start,n.open)).join('');
      let value = op.kind === 'break' ? '<br>' : esc(op.value).replace(/\r\n?|\n/g, '<br>');
      let tail = '';
      if (op.kind === 'text' && value) {
        for (const tag of op.marks || []) {
          if (tag !== 'strong' && tag !== 'em') refuse('Unsupported text style.');
          value = '<' + tag + '>' + value;
          tail += '</' + tag + '>';
        }
      }
      return result(a, b, value + tail + closeLeft + openRight, a + value.length);
    }
    case 'paragraph': {
      if (host.tag === 'li' && host.open === host.close) {
        const list = rows[host.parent];
        const siblings = rows.filter(n => n.parent === list.id);
        if (!['ul','ol'].includes(list.tag) || siblings.at(-1)?.id !== id || Object.keys(host.attrs).length)
          refuse('Use Layout or Code to restructure this list item.');
        if (siblings.length === 1 && (Object.keys(list.attrs).length || /<!--/.test(source.slice(list.open,list.close))))
          refuse('This list has attributes or comments. Restructure it in Code.');
        if (/\S/.test(source.slice(host.end, list.close))) refuse('This list has trailing markup. Restructure it in Code.');
        const prefix = siblings.length === 1 ? '' : source.slice(host.end, list.end);
        const at = siblings.length === 1 ? list.start : host.start;
        return result(at, list.end, prefix + '<p></p>', at + prefix.length + 3, at + prefix.length + 3, list);
      }
      if (paragraphs.has(host.tag) || host.tag === 'li') return splitBlock('', host.tag === 'li' ? 'li' : 'p');
      if (containers.has(host.tag)) {
        safeSelection();
        if (left.length) refuse('Place the caret outside the inline style to start a paragraph.');
        return result(host.open,host.close,'<p>'+source.slice(host.open,a)+'</p><p>'+source.slice(b,host.close)+'</p>',a+10);
      }
      safeSelection();
      return result(a,b,'<br>',a+4);
    }
    case 'join': {
      if (!paragraphs.has(host.tag) && host.tag !== 'li') refuse('This block boundary needs Layout or Code.');
      const siblings = rows.filter(n => n.parent === host.parent);
      const pos = siblings.findIndex(n => n.id === id);
      const first = op.forward ? host : siblings[pos-1], last = op.forward ? siblings[pos+1] : host;
      if (!first || !last || (host.tag === 'li' ? first.tag !== 'li' || last.tag !== 'li' :
          !paragraphs.has(first.tag) || !paragraphs.has(last.tag)) ||
          Object.keys(last.attrs).length || !/^\s*$/.test(source.slice(first.end,last.start))) return null;
      return result(first.close,last.end,source.slice(last.open,last.close) + source.slice(first.close,first.end),
        first.close,first.close,first,last);
    }
    case 'block': {
      if (!paragraphs.has(host.tag) || !paragraphs.has(op.value) || host.close === host.end)
        refuse('Choose an explicitly closed paragraph or heading for this style.');
      if (host.tag === op.value) return null;
      const opening = source.slice(host.start,host.open).replace(/^<[\w-]+/,'<' + op.value);
      const closing = source.slice(host.close,host.end).replace(/^<\/[\w-]+/,'</' + op.value);
      const delta = op.value.length - host.tag.length;
      return result(host.start,host.end,opening + source.slice(host.open,host.close) + closing,a+delta,b+delta);
    }
    case 'list': {
      if (!['ul','ol'].includes(op.value)) refuse('Unknown list style.');
      if (host.tag === 'li') {
        const list = rows[host.parent];
        if (!list || !['ul','ol'].includes(list.tag) || list.close === list.end) refuse('Select a regular list item.');
        if (list.tag === op.value) {
          if (rows.filter(n => n.parent === list.id).length !== 1 || Object.keys(list.attrs).length ||
              /\S/.test(source.slice(list.open,host.start) + source.slice(host.end,list.close)))
            refuse('Use Layout or Code to remove the wrapper from this multi-item or attributed list.');
          const item = source.slice(host.start,host.end).replace(/^<li\b/i,'<p').replace(/<\/li\s*>$/i,'</p>');
          const delta = list.start-host.start-1;
          return result(list.start,list.end,item,a+delta,b+delta,list);
        }
        const value = source.slice(list.start,list.end).replace(/^<\w+/,'<'+op.value).replace(/<\/\w+(\s*>)$/,'</'+op.value+'$1');
        return result(list.start,list.end,value,a,b,list);
      }
      if (!paragraphs.has(host.tag) || host.close === host.end) refuse('Choose a paragraph or heading to make a list.');
      const opening = '<'+op.value+'>' + source.slice(host.start,host.open).replace(/^<[\w-]+/,'<li');
      const value = opening + source.slice(host.open,host.close) + '</li></'+op.value+'>';
      const delta = host.start+opening.length-host.open;
      return result(host.start,host.end,value,a+delta,b+delta);
    }
    case 'font-family': case 'font-size': case 'color': {
      const value=String(op.value).trim();
      const valid=op.kind==='color' ? /^#[a-f0-9]{6}([a-f0-9]{2})?$/i.test(value) :
        op.kind==='font-size' ? /^[1-9]\d{0,2}px$/.test(value) :
        value.length<=180 && value.split(',').every(name=>/^[a-z][a-z0-9 -]*$/i.test(name.trim()));
      if(!valid)refuse('Choose a valid font, pixel size or color.');
      const run=left.at(-1);
      const entireRun=run && run.tag==='span' && a===run.open && b===run.close;
      if((a===b || (a===host.open && b===host.close) || entireRun) && host.tag!=='body'){
        const target=entireRun?run:((a===b && run?.tag==='span')?run:host);
        const engine=typeof WebBench==='undefined'?require('./source.js'):WebBench;
        const changed=engine.run(source,target.id,{kind:'inline',prop:op.kind,value}).text;
        const delta=changed.length-source.length;
        const opening=changed.slice(target.start,target.open+delta);
        return result(target.start,target.open,opening,a+delta,b+delta);
      }
      safeSelection();
      if(a===b)refuse('Select the words to style in this unwrapped page.');
      const opening='<span style="'+op.kind+': '+attr(value)+';">';
      return result(a,b,opening+selected+'</span>',a+opening.length,b+opening.length);
    }
    case 'bold': case 'italic': {
      safeSelection();
      const tag = op.kind === 'bold' ? 'strong' : 'em';
      const active = left.slice().reverse().find(n => n.tag === tag || n.tag === (tag === 'strong' ? 'b' : 'i'));
      if (!active) return pair(tag,selected);
      if (a === active.open && b === active.close && !Object.keys(active.attrs).length)
        return result(active.start,active.end,selected,active.start,active.start+selected.length);
      if (left.at(-1) !== active || Object.keys(active.attrs).length)
        refuse('Select the complete unadorned style to remove it, or use Code.');
      const opening = source.slice(active.start,active.open), closing = source.slice(active.close,active.end);
      const prefix = a === active.open ? '' : opening + source.slice(active.open,a) + closing;
      const suffix = b === active.close ? '' : opening + source.slice(b,active.close) + closing;
      return result(active.start,active.end,prefix+selected+suffix,active.start+prefix.length,active.start+prefix.length+selected.length);
    }
    case 'link': {
      safeSelection();
      const url = op.value.trim();
      if (!url || /^(javascript|vbscript|data):/i.test(url.replace(/\s/g,''))) refuse('Enter a page address, relative path, or fragment.');
      const anchor = host.tag === 'a' ? host : left.find(n => n.tag === 'a');
      if (anchor) {
        const h = anchor.attrs.href;
        if (h && !h.quote) refuse('Edit this unquoted link address in Code.');
        const at = h ? h.start : anchor.start + 2, end = h ? h.end : at;
        const value = h ? attr(url) : ' href="'+attr(url)+'"';
        const delta = value.length-(end-at);
        return result(at,end,value,a+delta,b+delta);
      }
      if (host.tag === 'button' || /<a\b/i.test(selected)) refuse('Links cannot be nested inside this selection.');
      const open = '<a href="'+attr(url)+'">', label = selected || esc(url);
      return result(a,b,open+label+'</a>',a+open.length,a+open.length+label.length);
    }
    case 'element': {
      safeSelection();
      if (left.some(n => n.tag === 'a') || ['button','label','output'].includes(host.tag))
        refuse('Place the caret in a paragraph outside this interactive element.');
      if (op.value === 'button') {
        const label = selected || 'Button', prefix = '<button type="button">';
        return result(a,b,prefix+label+'</button>',a+prefix.length,a+prefix.length+label.length);
      }
      if (op.value === 'image') {
        const value = '<img src="'+attr(op.url)+'" alt="'+attr(op.alt || '')+'">';
        return result(a,b,value,a+value.length);
      }
      if (!['hr','table'].includes(op.value)) refuse('Unknown insertion.');
      const table = '<table><tbody><tr><td>Cell</td><td>Cell</td></tr></tbody></table>';
      const value = op.value === 'hr' ? '<hr>' : table;
      if (paragraphs.has(host.tag)) {
        const r = splitBlock(value,'p');
        if (op.value === 'table') {r.caret = a + r.insert.indexOf('<td>')+4; r.endCaret=r.caret+4;}
        return r;
      }
      if (!containers.has(host.tag) || left.length) refuse('Insert this element from a paragraph or an empty container.');
      const at = op.value === 'table' ? a+value.indexOf('<td>')+4 : a+value.length+3;
      return result(a,b,value+(op.value === 'hr' ? '<p></p>' : ''),at,op.value === 'table' ? at+4 : at);
    }
    default: refuse('This command requires Code.');
    }
  }
  return {blocks, inline, containers, boundaries, plan};
})();
if (typeof module !== 'undefined') module.exports = Writing;
