// Run has one bounded, output-only channel. The original page is served as authored.
(() => {
  let budget=400;
  function send(level,args) {
    if(budget--<=0)return;
    const text=args.map(x=>{try{return typeof x==='string'?x:JSON.stringify(x)??String(x);}catch{return String(x);}}).join(' ').slice(0,3000);
    window.webkit.messageHandlers.output.postMessage(level+'  '+text);
  }
  for(const level of ['log','info','warn','error','debug']) {
    const previous=console[level].bind(console);console[level]=(...args)=>{previous(...args);send(level,args);};
  }
  addEventListener('error',e=>send('error',[e.message||'Resource failed',e.filename||'',e.lineno||'']),true);
  addEventListener('unhandledrejection',e=>send('rejection',[String(e.reason)]));
  addEventListener('click',e=>{if(e.altKey){e.preventDefault();e.stopImmediatePropagation();send('runtime DOM',[e.target.localName,e.target.id||'', 'Preview only']);}},true);
  // Weakly track elements introduced after the document parser has completed.
  addEventListener('DOMContentLoaded',()=>{
    const remote=Array.from(document.querySelectorAll('iframe[src]')).some(frame=>
      !frame.hasAttribute('srcdoc') && /^https?:/i.test(frame.src));
    if(remote) send('embed',['Online frames use File → Preview Website in Browser. This Preview stays offline.']);
    const added=new WeakSet();
    const observer=new MutationObserver(records=>{for(const r of records)for(const n of r.addedNodes)if(n.nodeType===1){added.add(n);for(const child of n.querySelectorAll('*'))added.add(child);}});
    observer.observe(document,{childList:true,subtree:true});
    addEventListener('pointerover',e=>{if(e.altKey&&added.has(e.target))send('runtime-created or reinserted',[e.target.localName,e.target.id||'']);},true);
  },{once:true});
})();
