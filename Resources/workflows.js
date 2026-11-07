// Source-side compiler. Only the handler for the chosen actions is written into the page.
function interactionEngine(source) {
  'use strict';
  const marker = 'data-webbench-workflow';
  const prefix = '// WebBench interaction ';
  const targeted = new Set(['text', 'color', 'background', 'show', 'hide', 'toggle']);
  const kinds = new Set([...targeted, 'dialog', 'download', 'downloadText', 'upload', 'chooseFile']);
  const events = ['click', 'change', 'input'];
  const excluded = new Set(['html', 'head', 'body', 'base', 'link', 'style', 'script', 'meta', 'title',
    'template', 'noscript', 'svg', 'math', 'iframe', 'option', 'source', 'track']);
  const fail = message => { throw new Error(message); };
  const literal = value => JSON.stringify(value).replace(/[<>&\u2028\u2029]/g,
    char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0'));
  const nlOf = s => s.match(/\r\n|\n|\r/)?.[0] || '\n';
  function checkLocation(value, local) {
    if (!value || value.trim() !== value || /[\\\x00-\x20\x7f]/.test(value) || value.startsWith('//') ||
        value.startsWith('#') || value.startsWith('?')) fail('Choose a project file or enter a valid path using %20 for spaces.');
    if (/^[a-z][\w+.\-]*:/i.test(value)) {
      if (local || !/^https?:\/\/[^/?#\s@]+(?=\/|\?|#|$)/i.test(value)) {
        fail(local ? 'Choose a relative project file for the download.' : 'Enter an HTTP(S) upload address or a site-relative path.');
      }
    }
    if (local && value.startsWith('/')) fail('Choose a relative project file for a portable download.');
  }
  const modalHelper = `  function panel(title) {
    const dialog = document.createElement("dialog");
    const heading = document.createElement("h2");
    heading.textContent = title;
    dialog.setAttribute("aria-label", title);
    dialog.append(heading);
    document.body.append(dialog);
    dialog.addEventListener("close", () => dialog.remove(), { once: true });
    return dialog;
  }
  function control(label) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;
    return button;
  }
  function message(title, text) {
    const dialog = panel(title);
    const body = document.createElement("p");
    body.textContent = text;
    const close = control("Close");
    close.addEventListener("click", () => dialog.close());
    dialog.append(body, close);
    return new Promise(resolve => {
      dialog.addEventListener("close", resolve, { once: true });
      dialog.showModal();
    });
  }`;
  const fileHelper = `  async function selectFile(endpoint, field) {
    const preview = location.protocol === "webbench:";
    const dialog = panel(endpoint ? "Upload a file" : "Choose a file");
    const input = document.createElement("input");
    input.type = "file";
    input.setAttribute("aria-label", "Choose a file");
    const status = document.createElement("p");
    status.setAttribute("role", "status");
    status.textContent = endpoint ? (preview ? "Preview only. Your file stays on this Mac." : "Send to " + new URL(endpoint, document.baseURI).href) : "";
    const send = control(endpoint ? (preview ? "Test upload" : "Upload") : "Use file");
    const cancel = control("Cancel");
    send.disabled = true;
    input.addEventListener("change", () => { send.disabled = !input.files.length; });
    cancel.addEventListener("click", () => dialog.close());
    dialog.append(input, status, send, cancel);
    let selected = null;
    let pending = false;
    dialog.addEventListener("cancel", event => { if (pending) event.preventDefault(); });
    send.addEventListener("click", async () => {
      const file = input.files[0];
      if (!file || pending) return;
      pending = true;
      input.disabled = send.disabled = cancel.disabled = true;
      try {
        if (endpoint && !preview) {
          const data = new FormData();
          data.append(field, file, file.name);
          status.textContent = "Uploading…";
          const response = await fetch(endpoint, { method: "POST", body: data });
          if (!response.ok) throw new Error("Server returned " + response.status);
        }
        selected = file;
        dialog.close();
      } catch (error) {
        status.textContent = "Upload failed. " + error.message + ". Retry or cancel.";
      } finally {
        pending = false;
        input.disabled = send.disabled = cancel.disabled = false;
      }
    });
    await new Promise(resolve => {
      dialog.addEventListener("close", resolve, { once: true });
      dialog.showModal();
    });
    return selected;
  }`;
  const downloadHelper = `  async function download(path, filename) {
    if (location.protocol === "webbench:") {
      await message("Download preview", "The published page downloads " + (filename || path) + (path.startsWith("blob:") ? "." : " from " + path + "."));
      return;
    }
    const link = document.createElement("a");
    link.href = path;
    link.download = filename;
    if (navigator.userActivation?.isActive) {
      document.body.append(link);
      link.click();
      link.remove();
      return;
    }
    const dialog = panel("Download file");
    link.textContent = filename || path;
    link.addEventListener("click", () => dialog.close());
    const close = control("Close");
    close.addEventListener("click", () => dialog.close());
    dialog.append(link, close);
    await new Promise(resolve => {
      dialog.addEventListener("close", resolve, { once: true });
      dialog.showModal();
    });
  }`;
  const visibilityHelper = `  function visible(element, show) {
    const saved = Symbol.for("webbench.visibility.display");
    if (show == null) show = element.hidden || getComputedStyle(element).display === "none";
    element.hidden = !show;
    if (!show) {
      if (!element[saved]) element[saved] = [element.style.display, element.style.getPropertyPriority("display")];
      element.style.setProperty("display", "none", "important");
    } else {
      if (element[saved]) {
        element.style.setProperty("display", ...element[saved]);
        delete element[saved];
      }
      if (getComputedStyle(element).display === "none") element.style.setProperty("display", "revert", "important");
    }
  }`;
  function statement(step) {
    const el = 'element(' + literal(step.target) + ')', v = literal(step.value), detail = literal(step.detail);
    switch (step.kind) {
      case 'text': return 'setText(' + el + ', ' + v + ');';
      case 'color': case 'background': return el + '.style.setProperty(' + literal(step.kind === 'color' ? 'color' : 'background-color') + ', ' + v + ', "important");';
      case 'show': case 'hide': case 'toggle': return 'visible(' + el + ', ' + ({show:'true', hide:'false', toggle:'null'})[step.kind] + ');';
      case 'dialog': return 'await message(' + v + ', ' + detail + ');';
      case 'downloadText': return 'const url = URL.createObjectURL(new Blob([' + detail + '], { type: "text/plain;charset=utf-8" }));\ntry { await download(url, ' + v + '); } finally { setTimeout(() => URL.revokeObjectURL(url), 60000); }';
      case 'download': return 'await download(' + v + ', ' + detail + ');';
      case 'chooseFile': return 'const file = await selectFile("", "");\nif (!file) return;\nsetText(' + el + ', file.name);';
      case 'upload': return 'if (!await selectFile(' + v + ', ' + detail + ')) return;\nawait message(location.protocol === "webbench:" ? "Upload preview" : "Upload complete", location.protocol === "webbench:" ? "Test completed. No file was sent." : "The server accepted the file.");';
      default: fail('Unknown interaction action. Open Code to inspect this workflow.');
    }
  }
  function block(key, spec, nl) {
    const types = new Set(spec.steps.map(step => step.kind));
    const has = (...names) => names.some(name => types.has(name));
    const parts = ['<script ' + marker + '="' + key + '">', prefix + literal(spec), '(() => {'];
    if ([...targeted, 'chooseFile'].some(kind => types.has(kind))) parts.push('  function element(id) {\n    const node = document.getElementById(id);\n    if (!node) throw new Error("Missing interaction element #" + id);\n    return node;\n  }');
    if (has('text','chooseFile')) parts.push('  function setText(node, text) {\n    if (node.matches("input, textarea, output")) node.value = text;\n    else node.textContent = text;\n  }');
    if (has('show','hide','toggle')) parts.push(visibilityHelper);
    if (has('dialog','upload','download','downloadText','chooseFile')) parts.push(modalHelper);
    if (has('upload','chooseFile')) parts.push(fileHelper);
    if (has('download','downloadText')) parts.push(downloadHelper);
    const trigger = 'document.getElementById(' + literal(spec.trigger) + ')';
    parts.push('  if (!' + trigger + ') return;',
      '  ' + trigger + '.addEventListener(' + literal(spec.event) + ', async event => {');
    if (spec.preventDefault && spec.event === 'click') parts.push('    event.preventDefault();');
    parts.push('    try {');
    for (const step of spec.steps) {
      const lines = statement(step).split('\n');
      if (lines.length === 1) parts.push('      ' + lines[0]);
      else parts.push('      {', ...lines.map(line => '        ' + line), '      }');
    }
    parts.push('    } catch (error) {', '      console.error("WebBench interaction", error);', '    }', '  });', '})();', '</script>');
    return parts.join('\n').replace(/\n/g,nl);
  }
  function inspect(s) {
    const ix = source.index(s);
    if (ix.error) fail(ix.error);
    const byID = new Map(), eligible = new Set(), flows = [];
    for (const n of ix.nodes) {
      const id = n.attrs.id?.value;
      if (id) {
        const decoded = id.replace(/&#(?:x([0-9a-f]+)|(\d+));?/gi, (_,hex,dec) => {
          const cp = parseInt(hex || dec, hex ? 16 : 10);
          return cp > 0 && cp <= 0x10ffff ? String.fromCodePoint(cp) : '\ufffd';
        }).replace(/&lowbar;/g,'_').replace(/&period;/g,'.').replace(/&colon;/g,':');
        byID.set(decoded, byID.has(decoded) ? -1 : n.id);
      }
      if (!excluded.has(n.tag) && (ix.nodes[n.parent]?.tag === 'body' || eligible.has(n.parent))) eligible.add(n.id);
      if (n.tag !== 'script') continue;
      if (!n.attrs[marker] && !s.slice(n.open, n.open + prefix.length + 8).trimStart().startsWith(prefix)) continue;
      const key = n.attrs[marker]?.value || '';
      const content = s.slice(n.start,n.end), nl = nlOf(content);
      try {
        if (!/^[a-z0-9-]{1,64}$/.test(key) || flows.some(f=>f.key===key)) throw Error();
        const line = content.split(nl)[1];
        if (!line.startsWith(prefix)) throw Error();
        const spec = JSON.parse(line.slice(prefix.length));
        if (spec.version !== 1 || !events.includes(spec.event) || typeof spec.preventDefault !== 'boolean' ||
          !Array.isArray(spec.steps) || !spec.steps.length || block(key,spec,nl) !== content) throw Error();
        flows.push({key,n,spec});
      } catch {
        const error = new Error('This interaction script was changed in Code or uses a different version. WebBench has kept it intact.');
        error.range = [n.start, n.end - n.start];
        throw error;
      }
    }
    return {ix,byID,eligible,flows};
  }
  function workflows(s) {
    const {byID,eligible,flows} = inspect(s);
    const ref = id => eligible.has(byID.get(id)) ? byID.get(id) : -1;
    return {elements:[...eligible], flows:flows.map(({key,spec})=>({
      key, trigger:ref(spec.trigger), label:spec.trigger, event:spec.event, preventDefault:spec.preventDefault,
      steps:spec.steps.map(a=>({...a,target:ref(a.target)}))
    }))};
  }
  function editWorkflow(s, request) {
    const {ix,byID,eligible,flows} = inspect(s), {key, remove} = request;
    if (!/^[a-z0-9-]{1,64}$/.test(key)) fail('Invalid interaction identifier.');
    const old = flows.find(f=>f.key===key);
    if (!!old !== request.existing) fail('This workflow changed. Reopen Interactions.');
    if (remove) {
      if (!old) fail('This workflow is missing.');
      return {text:s.slice(0,old.n.start)+s.slice(old.n.end),focus:ix.nodes[byID.get(old.spec.trigger)]?.start??0};
    }
    const body = ix.nodes.filter(n=>n.tag==='body');
    if (body.length !== 1) fail('An explicit body is needed to place the interaction. Open Code to add one.');
    const refs = new Map(), patches = [];
    function ensure(i) {
      if (!eligible.has(i)) fail('Choose an element on this page for every target and trigger.');
      if (refs.has(i)) return refs.get(i);
      const n = ix.nodes[i];
      let id = n.attrs.id?.value;
      if (n.attrs.id) {
        if (!id || /[&\s\x00]/.test(id) || byID.get(id)!==i) fail('This element needs a unique, unambiguous HTML id. Choose another element or update its id in Code.');
      } else {
        let number = 1;
        do { id = 'wb-' + n.tag + '-' + number++; } while (s.includes(id) || byID.has(id));
        byID.set(id,i);
        const at = n.start + 1 + n.tag.length;
        patches.push({start:at,end:at,text:' id="'+id+'"'});
      }
      refs.set(i,id);
      return id;
    }
    if (!events.includes(request.event) || !Array.isArray(request.steps) || !request.steps.length || request.steps.length>64) fail('Use between 1 and 64 actions.');
    const trigger = ensure(request.trigger);
    if (flows.some(f=>f!==old && f.spec.trigger===trigger && f.spec.event===request.event)) fail('This element already has a workflow for this event. Open it from Page workflows.');
    const steps = request.steps.map(a=>{
      if (!kinds.has(a.kind) || typeof a.value!=='string' || typeof a.detail!=='string') fail('Invalid action.');
      const targetedAction = targeted.has(a.kind) || a.kind==='chooseFile';
      const target = targetedAction ? ensure(a.target) : '';
      if ((a.kind==='text' || a.kind==='chooseFile') && (['img','br','hr','select','video','audio','canvas','picture','embed','object','meter','progress'].includes(ix.nodes[a.target].tag) ||
        (ix.nodes[a.target].tag==='input' && /^(file|checkbox|radio|image|hidden|color)$/i.test(ix.nodes[a.target].attrs.type?.value)))) fail('Choose a text element, result display, or text field to show the result.');
      if (['color','background'].includes(a.kind) && !/^#[0-9a-f]{6}$/i.test(a.value)) fail('Choose a six-digit color.');
      if (a.kind==='downloadText' && (!a.value.trim() || /[\/\\\x00-\x1f]/.test(a.value))) fail('Enter a file name without folder separators.');
      if (a.kind==='dialog' && !a.value.trim()) fail('Give the dialog a title.');
      if (a.kind==='download' || a.kind==='upload') checkLocation(a.value,a.kind==='download');
      if (a.kind==='upload' && !a.detail.trim()) fail('Enter the file field name expected by your server.');
      return {kind:a.kind,target,value:a.value,detail:a.detail};
    });
    const spec={version:1,trigger,event:request.event,preventDefault:!!request.preventDefault,steps};
    const at=old ? old.n.start : body[0].close;
    patches.push({start:at,end:old ? old.n.end : at,text:block(key,spec,old?nlOf(s.slice(at,old.n.end)):nlOf(s))});
    let text=s, focus=ix.nodes[request.trigger].start;
    for (const p of patches.sort((a,b)=>b.start-a.start)) {
      text=text.slice(0,p.start)+p.text+text.slice(p.end);
      if(p.start<ix.nodes[request.trigger].start) focus+=p.text.length-(p.end-p.start);
    }
    return {text,focus};
  }
  function workflowIssueRange(s) {
    try { inspect(s); return []; }
    catch (error) { return error.range || []; }
  }
  return {workflows, editWorkflow, workflowIssueRange};
}
if (typeof module !== 'undefined') module.exports = interactionEngine(require('./source.js'));
else Object.assign(WebBench, interactionEngine(WebBench));
