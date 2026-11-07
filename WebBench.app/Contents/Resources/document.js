// Runs only in the isolated Edit content world. Original source owns the document.
(() => {
  const {marker, token} = WB;
  const hostFlag = marker + '-write';
  const post = (kind, values = {}) => window.webkit.messageHandlers.design.postMessage({token,kind,...values});
  const key = e => e?.hasAttribute?.(marker) ? Number(e.getAttribute(marker)) : -1;
  const element = id => document.querySelector('[' + marker + '="' + id + '"]');
  const owner = node => (node?.nodeType === 1 ? node : node?.parentElement)?.closest('[' + hostFlag + ']');
  let source = WB.source, rows = WebBench.index(source).nodes, serial = 0;
  let bookmark = null, composing = null, pending = null, lastFocus = '';
  const blockSelector = [...Writing.blocks].join(',');
  const marks = new Set();
  const decoder = document.createElement('textarea');
  function decode(value) { decoder.innerHTML = value; return decoder.value; }
  function fail(message) { throw Error(message); }
  const duplicate = new Set(), seen = new Set();
  for (const e of document.querySelectorAll('['+marker+']')) {
    if (seen.has(key(e))) duplicate.add(key(e));
    seen.add(key(e));
  }
  function matches(e) {
    for (let node = e; node; node = node.parentElement?.closest('['+marker+']')) {
      const n = rows[key(node)];
      if (!n || duplicate.has(n.id) || n.tag !== node.localName || n.parent !== key(node.parentElement?.closest('['+marker+']'))) return false;
    }
    return true;
  }
  window.webBenchWritingMaps=matches;
  function isHost(e) {
    return key(e) >= 0 && Writing.blocks.has(e.localName) &&
      !e.closest('svg,math,template,noscript,pre,code[contenteditable=false],[inert]') &&
      [...e.children].every(child => Writing.inline.has(child.localName) ||
        ['br','img','button','input','wbr','output','label'].includes(child.localName)) && matches(e);
  }
  function enable(root) {
    const all = [...root.querySelectorAll(blockSelector)];
    if (root.matches?.(blockSelector)) all.unshift(root);
    for (const e of all) {
      if (!isHost(e) || (Writing.inline.has(e.localName) && e.parentElement?.closest('['+hostFlag+']'))) continue;
      e.setAttribute(hostFlag,'');
      e.setAttribute('contenteditable','true');
      e.setAttribute('spellcheck','true');
    }
  }
  const css = document.createElement('style');
  css.textContent = '['+hostFlag+']{cursor:text}['+hostFlag+']:focus{outline:1px dashed #348163;outline-offset:3px}['+hostFlag+']:empty{min-height:1em;min-width:0.35em}p['+hostFlag+']:empty:before{content:"Start writing…";color:#78837e;font-style:italic;pointer-events:none}';
  (document.head || document.documentElement).appendChild(css);
  enable(document.body);
  function positions(host) {
    const pieces = [], edges = new Map();
    function walk(e) {
      const n = rows[key(e)];
      if (!n || !matches(e)) fail('WebKit generated or repaired this text. Use Code for this passage.');
      const children = [...e.childNodes], points = [n.open];
      let pos = n.open;
      for (let i=0; i<children.length; i++) {
        const child = children[i];
        if (child.nodeType === Node.TEXT_NODE) {
          const next = children[i+1];
          const end = !next ? n.close : next.nodeType === Node.COMMENT_NODE ?
            source.indexOf('<!--',pos) : rows[key(next)]?.start;
          if (end == null || end < pos || end > n.close) fail('The text run has no exact source boundary.');
          const offsets = Writing.boundaries(source.slice(pos,end),child.data,decode);
          pieces.push({node:child,base:pos,offsets});
          pos = end;
        } else if (child.nodeType === Node.COMMENT_NODE && source.startsWith('<!--',pos)) {
          pos = source.indexOf('-->',pos+4)+3;
        } else if (child.nodeType === Node.ELEMENT_NODE) {
          const row = rows[key(child)];
          if (!row || row.start !== pos || row.parent !== n.id) fail('The rendered children differ from the original markup.');
          if (row.end > row.open) walk(child);
          pos = row.end;
        } else fail('This document node needs Code.');
        points.push(pos);
      }
      if (pos !== n.close) fail('The text block contains an unmapped source range.');
      edges.set(e,points);
    }
    walk(host);
    function offset(node, i) {
      const p = pieces.find(p => p.node === node);
      if (p && p.offsets[i] != null) return p.base+p.offsets[i];
      const value = edges.get(node)?.[i];
      if (value == null) fail('Place the caret between complete characters inside a paragraph.');
      return value;
    }
    function point(pos) {
      for (const p of pieces) {
        const i = p.offsets.indexOf(pos-p.base);
        if (i !== -1) return [p.node,i];
      }
      for (const [e,pts] of edges) {
        const i = pts.indexOf(pos);
        if (i !== -1) return [e,i];
      }
      return null;
    }
    return {offset,point};
  }
  function readRange(range) {
    const host = owner(range.startContainer);
    if (!host || host !== owner(range.endContainer)) fail('Choose text within one paragraph. Use Code for a selection spanning blocks.');
    const map = positions(host);
    return {id:key(host),a:map.offset(range.startContainer,range.startOffset),b:map.offset(range.endContainer,range.endOffset)};
  }
  function current() {
    const selection = getSelection();
    if (selection.rangeCount && owner(selection.anchorNode)) return readRange(selection.getRangeAt(0));
    if (bookmark) return bookmark;
    fail('Click where you want to write first.');
  }
  function locate(pos) {
    for (let i=rows.length-1; i>=0; i--) {
      const n = rows[i];
      if (pos < n.open || pos > n.close || !Writing.blocks.has(n.tag)) continue;
      const e = element(n.id);
      if (e?.hasAttribute(hostFlag)) {
        const p = positions(e).point(pos);
        if (p) return {e,p};
      }
    }
    return null;
  }
  function restore(a,b=a) {
    const s = locate(a), t = a === b ? s : locate(b);
    if (!s || !t) return false;
    s.e.focus({preventScroll:true});
    const range = document.createRange();
    range.setStart(...s.p); range.setEnd(...t.p);
    const selection = getSelection();
    selection.removeAllRanges(); selection.addRange(range);
    bookmark = {id:key(s.e),a,b};
    return true;
  }
  function markedPart(text,index,start,end) {
    const parts=[];
    let pos=start;
    for (const n of index) {
      if (n.start<start || n.start>=end) continue;
      const at=n.start+1+n.tag.length;
      parts.push(text.slice(pos,at),' '+marker+'="'+n.id+'"'); pos=at;
    }
    parts.push(text.slice(pos,end));
    return parts.join('');
  }
  function paint(edit,text,next) {
    const first=rows[edit.first], last=rows[edit.last];
    const lo=element(first.id), hi=element(last.id);
    if (!lo || !hi || !matches(lo) || !matches(hi) || lo.parentNode !== hi.parentNode)
      fail('This element has no stable source parent.');
    // Body itself must remain attached to its document.
    const body = lo === document.body && lo === hi;
    const range=document.createRange();
    if (body) range.selectNodeContents(lo);
    else {range.setStartBefore(lo);range.setEndAfter(hi);}
    const delta=text.length-source.length;
    const start=body ? first.open : first.start, end=(body ? last.close : last.end)+delta;
    const fragment=range.createContextualFragment(markedPart(text,next,start,end));
    const expected=next.filter(n=>n.start>=start && n.start<end);
    const nodes=[...fragment.querySelectorAll('*')];
    if (expected.length !== nodes.length || nodes.some((e,i)=>key(e)!==expected[i].id || e.localName!==expected[i].tag))
      fail('WebKit would repair this insertion. Use a different paragraph or edit it in Code.');
    const shift=next.length-rows.length;
    const nextSibling=body ? null : hi.nextSibling, parent=body ? lo : lo.parentNode;
    range.deleteContents();
    if (shift) {
      for (const e of document.querySelectorAll('['+marker+']')) {
        if (key(e)>first.id && rows[key(e)]?.start>=last.end) e.setAttribute(marker,String(key(e)+shift));
      }
    }
    const added=[...fragment.children];
    parent.insertBefore(fragment,nextSibling);
    source=text; rows=next;
    if (body) {lo.removeAttribute(hostFlag); lo.removeAttribute('contenteditable'); enable(lo);}
    else added.forEach(enable);
  }
  function reportError(error,code=true,id=bookmark?.id) {
    const message=error.message || String(error);
    post(code ? 'writeError' : 'notice',{id,message});
  }
  function apply(where,op) {
    const edit=Writing.plan(source,rows,where.id,where.a,where.b,op);
    if (!edit) return;
    const old=source.slice(edit.start,edit.end);
    if (old===edit.insert) {restore(edit.caret,edit.endCaret);return;}
    const text=source.slice(0,edit.start)+edit.insert+source.slice(edit.end);
    const next=WebBench.index(text);
    if (next.error) fail(next.error);
    // Most keystrokes touch one text node. Leave images, selection hosts and scroll intact.
    let quick=false;
    if (op.kind==='text' && !op.marks?.length && !/[\r\n]/.test(op.value)) {
      const host=element(where.id), map=positions(host);
      const a=map.point(where.a), b=map.point(where.b);
      if (a && b && a[0]===b[0] && a[0].nodeType===Node.TEXT_NODE) {
        a[0].replaceData(a[1],b[1]-a[1],op.value); quick=true; source=text; rows=next.nodes;
      }
    }
    if (!quick) paint(edit,text,next.nodes);
    // Emit each patch before changing the selection. A command barrier follows these in FIFO order.
    post('write',{seq:++serial,start:edit.start,old,value:edit.insert,was:where.a,caret:edit.caret,action:op.kind,typing:op.typing===true,asset:op.asset || ''});
    if (!restore(edit.caret,edit.endCaret)) {
      bookmark=null;
      post('notice',{message:'Edit applied. Click the next place to write.'});
    }
  }
  function remember() {
    if (composing || pending) return;
    const s=getSelection();
    if (!s.rangeCount || !owner(s.anchorNode)) return;
    try {
      const next=readRange(s.getRangeAt(0));
      if (bookmark && (bookmark.a!==next.a || bookmark.b!==next.b)) marks.clear();
      bookmark=next;
      const inline=rows.filter(n=>n.open<=next.a && next.a<=n.close);
      next.bold=marks.has('strong') || inline.some(n=>['b','strong'].includes(n.tag));
      next.italic=marks.has('em') || inline.some(n=>['i','em'].includes(n.tag));
      next.list=inline.findLast(n=>['ul','ol'].includes(n.tag))?.tag || '';
      next.block=rows[next.id].tag;
      next.href=inline.findLast(n=>n.tag==='a') ? (s.anchorNode.nodeType===1?s.anchorNode:s.anchorNode.parentElement)?.closest('a')?.getAttribute('href') || '' : '';
      const at=s.anchorNode.nodeType===1?s.anchorNode:s.anchorNode.parentElement;
      const style=at && window.getComputedStyle?.(at);
      next.fontFamily=style?.fontFamily||'';next.fontSize=style?.fontSize||'';next.ink=style?.color||'';
      const hostStyle=window.getComputedStyle?.(element(next.id));next.fill=hostStyle?.backgroundColor||'';
      next.hasImage=!!hostStyle?.backgroundImage && hostStyle.backgroundImage!=='none';
      const sig=[next.fill,next.hasImage,next.fontFamily,next.fontSize,next.ink,next.id,next.a,next.b,next.bold,next.italic,next.list,next.href].join('/');
      if (sig!==lastFocus) {lastFocus=sig;post('writeSelection',next);}
    } catch { /* A drag selection can temporarily cross independent blocks. */ }
  }
  document.addEventListener('selectionchange',remember);
  document.addEventListener('submit',e=>e.preventDefault(),true);
  document.addEventListener('pointerdown',e=>{
    if (!owner(e.target) || e.target.closest('input,select,textarea')) {
      bookmark=null; marks.clear(); getSelection().removeAllRanges();
    }
  },true);
  document.addEventListener('click',e=>{
    if (e.target.closest('a,button,input,select,textarea')) e.preventDefault();
    if (!owner(e.target) && e.target.closest('input,img,svg,select,textarea'))
      post('notice',{message:'Choose Layout to change this object’s properties or position.'});
  },true);
  document.addEventListener('dragover',e=>{
    if ([...(e.dataTransfer?.types||[])].includes('Files') && owner(e.target)) e.preventDefault();
  },true);
  document.addEventListener('drop',e=>{
    e.preventDefault();
    const file=e.dataTransfer?.files?.[0];
    if (!file) {post('notice',{message:'Use the Insert palette to place a page element.'});return;}
    try {
      const range=document.caretRangeFromPoint?.(e.clientX,e.clientY);
      if (!range || !owner(range.startContainer)) fail('Drop the photo in a paragraph, or use Layout to position it freely.');
      range.collapse(true);
      const where=readRange(range);
      if (!restore(where.a)) fail('Click a text position and choose Image… to insert here.');
      remember();
      const text=source;
      LayoutDrop.photo(file,{id:where.id,before:null,point:null},()=>source===text && bookmark?.a===where.a);
    } catch(error) {reportError(error,false);}
  },true);
  function command(kind,value='',extra={}) {
    if (composing) return;
    try {
      const where=current();
      if (['bold','italic'].includes(kind) && where.a===where.b) {
        const tag=kind==='bold'?'strong':'em';
        const active=rows.some(n=>[tag,kind==='bold'?'b':'i'].includes(n.tag) && n.open<=where.a && where.a<=n.close);
        if (!active) {
          if (marks.has(tag)) marks.delete(tag); else marks.add(tag);
          restore(where.a); remember(); post('notice',{message:kind+(marks.has(tag)?' on':' off')}); return;
        }
      }
      marks.clear();
      apply(where,{kind,value,...extra});
    } catch(e) {reportError(e,!!bookmark);}
  }
  window.webBenchWrite=command;
  window.webBenchBarrier=id=>{if (composing) document.activeElement?.blur();post('barrier',{id});};
  function resetHost(where) {
    const el=element(where.id), n=rows[where.id];
    if (!el || !n) fail('The writing host disappeared.');
    const r=document.createRange();r.selectNodeContents(el);
    const fragment=r.createContextualFragment(markedPart(source,rows,n.open,n.close));
    el.replaceChildren(fragment);enable(el);
    restore(where.a,where.b);
  }
  document.addEventListener('compositionstart',e=>{
    if (!owner(e.target) || e.target.closest('input,select,textarea')) return;
    try {composing=current();} catch(e) {reportError(e);}
  },true);
  document.addEventListener('compositionend',e=>{
    if (!composing) return;
    const where=composing; composing=null;
    try {resetHost(where); if (e.data) apply(where,{kind:'text',value:e.data,marks:[...marks]});marks.clear();}
    catch(err){reportError(err);}
  },true);
  function interpret(e,where) {
    const type=e.inputType;
    if (type==='insertParagraph') return {kind:'paragraph'};
    if (type==='insertLineBreak') return {kind:'break'};
    if (type==='formatBold' || type==='formatItalic') return {kind:type==='formatBold'?'bold':'italic'};
    if (type.startsWith('delete')) {
      if (where.a===where.b) {
        const host=rows[where.id], forward=type.endsWith('Forward');
        if ((forward && where.b===host.close) || (!forward && where.a===host.open)) return {kind:'join',forward};
        const sel=getSelection();
        if (typeof sel.modify!=='function') fail('This deletion has no source selection.');
        sel.modify('extend',forward?'forward':'backward',type.includes('Word')?'word':'character');
        if (!sel.rangeCount) return null;
        const extended=readRange(sel.getRangeAt(0));
        Object.assign(where,extended);
      }
      return {kind:'text',value:''};
    }
    if (['insertText','insertReplacementText','insertFromPaste','insertFromYank'].includes(type)) {
      const value=e.dataTransfer?.getData('text/plain') ?? e.data;
      if (typeof value!=='string') fail('Paste plain text into this paragraph.');
      return {kind:type==='insertFromPaste'?'paste':'text',value,marks:[...marks],typing:type==='insertText' && where.a===where.b && marks.size===0};
    }
    fail('This writing operation requires Code.');
  }
  document.addEventListener('beforeinput',e=>{
    if (composing || e.isComposing) return;
    if (!owner(e.target) || e.target.closest('input,select,textarea')) {
      if (e.cancelable) e.preventDefault();
      post('notice',{message:'Click a paragraph to write, or choose Run to use form controls.'});return;
    }
    if (e.inputType==='insertFromComposition' || e.inputType==='deleteCompositionText') {
      if (e.cancelable) e.preventDefault();return;
    }
    if (e.cancelable) e.preventDefault();
    try {
      const ranges=e.getTargetRanges?.();
      const where=ranges?.length ? readRange(ranges[0]) : current();
      if (e.inputType==='historyUndo' || e.inputType==='historyRedo') {post(e.inputType);return;}
      if (e.inputType==='formatBold' || e.inputType==='formatItalic') {command(e.inputType==='formatBold'?'bold':'italic');return;}
      const op=interpret(e,where);
      if (!op) return;
      if (!e.cancelable) {pending={where,op};return;}
      apply(where,op);marks.clear();
    } catch(err){reportError(err);}
  },true);
  document.addEventListener('input',e=>{
    if (composing || e.isComposing) return;
    try {
      if (pending) {
        const {where,op}=pending;pending=null;resetHost(where);apply(where,op);marks.clear();
      } else if (bookmark) {resetHost(bookmark);}
    } catch(err){reportError(err);}
  },true);
  document.addEventListener('paste',e=>{
    if (!owner(e.target) || e.target.closest('input,select,textarea')) return;
    e.preventDefault();
    const value=e.clipboardData?.getData('text/plain');
    if (typeof value==='string' && value) command('paste',value);
  },true);
  document.addEventListener('keydown',e=>{
    if (!composing && !e.metaKey && !e.ctrlKey && !e.altKey &&
        ['ArrowLeft','ArrowRight','Backspace','Delete','Tab'].includes(e.key) && getSelection().isCollapsed) {
      try {
        const w=current(), n=rows[w.id], forward=['ArrowRight','Delete'].includes(e.key);
        if (e.key==='Tab' && ['td','th'].includes(n.tag)) {
          const cell=element(n.id), cells=[...cell.closest('table').querySelectorAll('td,th')].filter(c=>c.hasAttribute(hostFlag));
          const target=cells[cells.indexOf(cell)+(e.shiftKey?-1:1)];
          if (target && restore(rows[key(target)].open)) {e.preventDefault();return;}
        } else if (!e.shiftKey && (forward ? w.b===n.close : w.a===n.open)) {
          if (['Backspace','Delete'].includes(e.key)) {
            e.preventDefault(); apply(w,{kind:'join',forward});return;
          }
          if (['ArrowLeft','ArrowRight'].includes(e.key)) {
            const hosts=[...document.querySelectorAll('['+hostFlag+']')].filter(e=>e.getClientRects().length);
            const next=hosts[hosts.indexOf(element(w.id))+(forward?1:-1)];
            if (next && restore(forward?rows[key(next)].open:rows[key(next)].close)) {
              e.preventDefault();next.scrollIntoView({block:'nearest'});return;
            }
          }
        }
      } catch(error) {if (['Backspace','Delete'].includes(e.key)) {e.preventDefault();reportError(error);return;}}
    }
    if (e.key==='Escape' && !composing && !e.isComposing) {
      e.preventDefault();post('returnToLayout');return;
    }
    if ((e.metaKey || e.ctrlKey) && !e.altKey && ['b','i','k'].includes(e.key.toLowerCase())) {
      e.preventDefault();
      if (e.key.toLowerCase()==='k') post('requestLink');
      else command(e.key.toLowerCase()==='b'?'bold':'italic');
    }
  },true);
  window.webBenchResume=pos=>restore(pos);
  post('ready');
  if (Array.isArray(WB.writeTarget)) {
    const [id,offset]=WB.writeTarget, target=element(id);
    if (target) {
      const walk=document.createTreeWalker(target,NodeFilter.SHOW_TEXT);
      let remaining=offset,found=false;
      for(let n=walk.nextNode();n;n=walk.nextNode()) {
        if(remaining>n.length){remaining-=n.length;continue;}
        const host=owner(n);if(!host)break;
        host.focus({preventScroll:true});
        const r=document.createRange();r.setStart(n,remaining);r.collapse(true);
        const selection=getSelection();selection.removeAllRanges();selection.addRange(r);
        target.scrollIntoView({block:'nearest'});remember();found=true;break;
      }
      if(!found && !target.childNodes.length && owner(target)){
        const host=owner(target);host.focus({preventScroll:true});
        const range=document.createRange();range.setStart(target,0);range.collapse(true);
        getSelection().removeAllRanges();getSelection().addRange(range);remember();found=true;
      }
      if(!found)post('writeError',{id,message:'This text has no editable source block. Continue in Code.'});
    }
  } else if (Number.isInteger(WB.caret)) restore(WB.caret);
})();
