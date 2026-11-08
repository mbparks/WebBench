// Source-side compiler. Only the handler for the chosen actions is written into the page.
function interactionEngine(source, deviceCode) {
  'use strict';
  const marker = 'data-webbench-workflow';
  const prefix = '// WebBench interaction ';
  const targeted = new Set(['text', 'color', 'background', 'show', 'hide', 'toggle']);
  const kinds = new Set([...targeted, 'dialog', 'download', 'downloadText', 'upload', 'chooseFile']);
  const newActions = new Set(['copyValue', 'calculate', 'classChange', 'enabled', 'checked', 'focus', 'scroll', 'resetForm', 'disclosure', 'mediaControl']);
  const deviceActions = new Set(['serialOpen','serialRead','serialWrite','serialClose','usbOpen','usbRead','usbWrite','usbClose','cameraStart','cameraSnapshot','cameraStop','micStart','micStop']);
  const deviceTargets = new Set(['serialRead','usbRead','cameraStart','cameraSnapshot','micStart']);
  const deviceMarker = 'data-webbench-devices';
  function supportBlock(nl) {
    if (!deviceCode) fail('The device support resource is missing.');
    return ('<script ' + deviceMarker + '="1">\n' + deviceCode.replace(/\r\n?/g,'\n').trimEnd() + '\n</script>').replace(/\n/g,nl);
  }
  function hardware(spec) {
    return [...spec.steps, ...(spec.otherwise || [])].some(step => deviceActions.has(step.kind));
  }
  function checkNumber(text, min, max, label) {
    if (typeof text !== 'string' || !/^\d+$/.test(text) || Number(text)<min || Number(text)>max) fail(label + ' must be a whole number from ' + min + ' to ' + max + '.');
  }
  const classicEvents = ['click', 'change', 'input'];
  const events = [...classicEvents, 'dblclick', 'submit', 'focus', 'blur', 'pointerenter', 'pointerleave', 'enterKey', 'escapeKey'];
  const tests = new Set(['empty', 'filled', 'equals', 'contains', 'greater', 'less', 'checked', 'valid']);
  const operations = new Map([['add','+'], ['subtract','-'], ['multiply','*'], ['divide','/']]);
  const numeric = value => typeof value === 'string' && value.trim() !== '' &&
    /^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i.test(value.trim()) && Number.isFinite(Number(value));
  const valueHelper = `  function readValue(node) {
    if (node.matches('input[type="file"]')) return node.files[0]?.name || "";
    if (node.matches('input[type="checkbox"], input[type="radio"]')) return node.checked ? node.value : "";
    return node.matches("input, select, textarea, output") ? node.value : node.textContent;
  }`;
  const numberHelper = `  function readNumber(value) {
    const text = String(value).trim();
    const number = Number(text);
    return Number.isFinite(number) && /^[+-]?(?:\\d+\\.?\\d*|\\.\\d+)(?:e[+-]?\\d+)?$/i.test(text) ? number : NaN;
  }`;
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
  function conditionExpression(condition) {
    const node = 'element(' + literal(condition.source) + ')';
    const read = 'readValue(' + node + ')';
    switch (condition.test) {
      case 'empty': return read + '.trim() === ""';
      case 'filled': return read + '.trim() !== ""';
      case 'equals': return read + ' === ' + literal(condition.value);
      case 'contains': return read + '.includes(' + literal(condition.value) + ')';
      case 'less': case 'greater':
        return 'readNumber(' + read + ') ' + (condition.test === 'less' ? '<' : '>') + ' ' + literal(Number(condition.value));
      case 'checked': return node + '.checked';
      case 'valid': return node + '.matches(":valid")';
      default: fail('Unknown workflow condition.');
    }
  }
  function calculation(step, destination) {
    const operand = step.constant == null ? 'readNumber(readValue(element(' + literal(step.operand) + ')))' : literal(Number(step.constant));
    const operation = operations.get(step.value);
    if (!operation || !Number.isInteger(step.digits) || step.digits < -1 || step.digits > 8) fail('Invalid calculation settings.');
    const formatted = step.digits < 0 ? 'String(result)' : 'result.toFixed(' + step.digits + ')';
    return [
      'const first = readNumber(readValue(element(' + literal(step.input) + ')));',
      'const second = ' + operand + ';',
      'const result = first ' + operation + ' second;',
      'if (![first, second, result].every(Number.isFinite)) {',
      '  setText(' + destination + ', ' + literal(step.invalid) + ');',
      '  return;', '}',
      'setText(' + destination + ', ' + formatted + ' + ' + literal(step.detail) + ');'
    ].join('\n');
  }
  function statement(step) {
    const el = 'element(' + literal(step.target) + ')', v = literal(step.value), detail = literal(step.detail);
    if (deviceActions.has(step.kind)) {
      const node = deviceTargets.has(step.kind) ? el : 'null';
      const input = step.input ? 'element(' + literal(step.input) + ')' : 'null';
      const args = [literal(step.kind), node, v, detail, literal(step.settings || {}), input];
      return 'if (!await window[Symbol.for("org.greenshoegarage.webbench.devices.v1")](' + args.join(', ') + ')) return;';
    }
    switch (step.kind) {
      case 'copyValue': return 'setText(' + el + ', ' + v + ' + readValue(element(' + literal(step.input) + ')) + ' + detail + ');';
      case 'calculate': return calculation(step, el);
      case 'classChange':
        if (!['add','remove','toggle'].includes(step.value)) fail('Unknown class action.');
        return el + '.classList.' + step.value + '(' + detail + ');';
      case 'enabled': return el + '.disabled = ' + (step.value === 'enable' ? 'false' : 'true') + ';';
      case 'checked': case 'disclosure': {
        const prop = step.kind === 'checked' ? '.checked' : '.open';
        const state = step.value === 'toggle' ? '!' + el + prop : String(['check','open'].includes(step.value));
        return el + prop + ' = ' + state + ';';
      }
      case 'resetForm': return 'HTMLFormElement.prototype.reset.call(' + el + ');';
      case 'focus': return el + '.focus();';
      case 'scroll': return el + '.scrollIntoView({block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth"});';
      case 'mediaControl': return step.value === 'play' ? 'await ' + el + '.play();' : el + '.pause();';
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
    const condition = spec.condition, alternate = spec.otherwise || [];
    const types = new Set([...spec.steps, ...alternate].map(step => step.kind));
    const has = (...names) => names.some(name => types.has(name));
    const parts = ['<script ' + marker + '="' + key + '">', prefix + literal(spec), '(() => {'];
    if (condition || [...targeted, ...newActions, ...deviceTargets, 'serialWrite', 'usbWrite', 'chooseFile'].some(kind => types.has(kind))) parts.push('  function element(id) {\n    const node = document.getElementById(id);\n    if (!node) throw new Error("Missing interaction element #" + id);\n    return node;\n  }');
    if ((condition && !['checked','valid'].includes(condition.test)) || has('copyValue','calculate')) parts.push(valueHelper);
    if (has('calculate') || ['less','greater'].includes(condition?.test)) parts.push(numberHelper);
    if (has('text','chooseFile','calculate','copyValue')) parts.push('  function setText(node, text) {\n    if (node.matches("input, textarea, output")) node.value = text;\n    else node.textContent = text;\n  }');
    if (has('show','hide','toggle')) parts.push(visibilityHelper);
    if (has('dialog','upload','download','downloadText','chooseFile')) parts.push(modalHelper);
    if (has('upload','chooseFile')) parts.push(fileHelper);
    if (has('download','downloadText')) parts.push(downloadHelper);
    const trigger = 'document.getElementById(' + literal(spec.trigger) + ')';
    const keyName = spec.event === 'enterKey' ? 'Enter' : spec.event === 'escapeKey' ? 'Escape' : null;
    const eventName = keyName ? 'keydown' : spec.event;
    parts.push('  if (!' + trigger + ') return;',
      '  ' + trigger + '.addEventListener(' + literal(eventName) + ', async event => {');
    if (keyName) parts.push('    if (event.key !== ' + literal(keyName) + ' || event.repeat || event.isComposing) return;');
    if (spec.preventDefault && ['click','submit'].includes(spec.event)) parts.push('    event.preventDefault();');
    parts.push('    try {');
    function emit(steps, indent) {
      for (const step of steps) {
        const lines = statement(step).split('\n');
        if (lines.length === 1) parts.push(indent + lines[0]);
        else parts.push(indent + '{', ...lines.map(line => indent + '  ' + line), indent + '}');
      }
    }
    if (condition) {
      parts.push('      if (' + conditionExpression(condition) + ') {');
      emit(spec.steps, '        ');
      if (alternate.length) {
        parts.push('      } else {');
        emit(alternate, '        ');
      }
      parts.push('      }');
    } else emit(spec.steps, '      ');
    parts.push('    } catch (error) {', '      console.error("WebBench interaction", error);', '    }', '  });', '})();', '</script>');
    return parts.join('\n').replace(/\n/g,nl);
  }
  function inspect(s) {
    const ix = source.index(s);
    if (ix.error) fail(ix.error);
    const byID = new Map(), eligible = new Set(), flows = [];
    let support;
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
      if (n.attrs[deviceMarker] || s.slice(n.open,n.open+48).trimStart().startsWith('// WebBench device support v1')) {
        const fragment = s.slice(n.start,n.end);
        if (support || fragment !== supportBlock(nlOf(fragment))) {
          const issue = new Error('Device support was changed in Code or duplicated. WebBench has kept it intact.');
          issue.range = [n.start,n.end-n.start]; throw issue;
        }
        support = n; continue;
      }
      if (!n.attrs[marker] && !s.slice(n.open, n.open + prefix.length + 8).trimStart().startsWith(prefix)) continue;
      const key = n.attrs[marker]?.value || '';
      const content = s.slice(n.start,n.end), nl = nlOf(content);
      try {
        if (!/^[a-z0-9-]{1,64}$/.test(key) || flows.some(f=>f.key===key)) throw Error();
        const line = content.split(nl)[1];
        if (!line.startsWith(prefix)) throw Error();
        const spec = JSON.parse(line.slice(prefix.length));
        if (![1,2,3].includes(spec.version) || (hardware(spec) !== (spec.version === 3)) || (spec.version === 1 && (spec.condition || spec.otherwise || !classicEvents.includes(spec.event) || spec.steps.some(step => !kinds.has(step.kind))))) throw Error();
        if (!events.includes(spec.event) || typeof spec.preventDefault !== 'boolean' ||
          !Array.isArray(spec.steps) || !spec.steps.length || block(key,spec,nl) !== content) throw Error();
        flows.push({key,n,spec});
      } catch {
        const error = new Error('This interaction script was changed in Code or uses a different version. WebBench has kept it intact.');
        error.range = [n.start, n.end - n.start];
        throw error;
      }
    }
    const missing = !support && flows.find(f => hardware(f.spec));
    if (missing) {
      const issue = new Error('This workflow’s device support is missing. Restore the support script in Code.');
      issue.range = [missing.n.start,missing.n.end-missing.n.start]; throw issue;
    }
    return {ix,byID,eligible,flows,support};
  }
  const targetKinds = {
    form: n => n.tag === 'form',
    valid: n => ['form','input','select','textarea'].includes(n.tag),
    control: n => ['button','input','textarea','select','fieldset'].includes(n.tag),
    checked: n => n.tag === 'input' && ['checkbox','radio'].includes((n.attrs.type?.value || '').toLowerCase()),
    details: n => n.tag === 'details',
    media: n => ['audio','video'].includes(n.tag),
    video: n => n.tag === 'video',
    image: n => n.tag === 'img',
    reading: n => ['p','span','pre','output','code','div','textarea','samp'].includes(n.tag),
    level: n => ['p','span','output','div','meter','progress'].includes(n.tag)
  };
  function workflows(s) {
    const {ix,byID,eligible,flows} = inspect(s);
    const choices = {}, classes = new Set();
    for (const i of eligible) {
      const node = ix.nodes[i];
      for (const [kind, match] of Object.entries(targetKinds)) {
        if (match(node)) (choices[kind] ||= []).push(i);
      }
      for (const name of (node.attrs.class?.value || '').split(/\s+/)) {
        if (name && !name.includes('&')) classes.add(name);
      }
    }
    const ref = id => eligible.has(byID.get(id)) ? byID.get(id) : -1;
    function restore(a) {
      const step = {...a, target:ref(a.target)};
      if ('input' in a) step.input = ref(a.input);
      if ('operand' in a) step.operand = ref(a.operand);
      return step;
    }
    return {elements:[...eligible], choices, classes:[...classes].sort(), flows:flows.map(({key,spec})=>({
      key, trigger:ref(spec.trigger), label:spec.trigger, event:spec.event, preventDefault:spec.preventDefault,
      steps:spec.steps.map(restore),
      condition:spec.condition ? {...spec.condition,source:ref(spec.condition.source)} : null,
      otherwise:(spec.otherwise || []).map(restore)
    }))};
  }
  function editWorkflow(s, request) {
    const {ix,byID,eligible,flows,support} = inspect(s), {key, remove} = request;
    if (!/^[a-z0-9-]{1,64}$/.test(key)) fail('Invalid interaction identifier.');
    const old = flows.find(f=>f.key===key);
    if (!!old !== request.existing) fail('This workflow changed. Reopen Interactions.');
    const siblingsNeedDevice = flows.some(f => f !== old && hardware(f.spec));
    const patches = [];
    function patched(focus) {
      let text=s, offset=focus;
      for (const p of patches.sort((a,b)=>b.start-a.start)) {
        text=text.slice(0,p.start)+p.text+text.slice(p.end);
        if(p.start<focus) offset+=p.text.length-(p.end-p.start);
      }
      return {text,focus:offset};
    }
    function removeSupport() { patches.push({start:support.start,end:support.end,text:''}); }
    if (remove) {
      if (!old) fail('This workflow is missing.');
      patches.push({start:old.n.start,end:old.n.end,text:''});
      if (hardware(old.spec) && support && !siblingsNeedDevice) removeSupport();
      return patched(ix.nodes[byID.get(old.spec.trigger)]?.start ?? 0);
    }
    const body = ix.nodes.filter(n=>n.tag==='body');
    if (body.length !== 1) fail('An explicit body is needed to place the interaction. Open Code to add one.');
    const refs = new Map();
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
    const alternate = request.otherwise ?? [];
    if (!Array.isArray(alternate) || (!request.condition && alternate.length)) fail('Otherwise actions need an If condition.');
    if (!events.includes(request.event) || !Array.isArray(request.steps) || !request.steps.length || request.steps.length + alternate.length > 64) fail('Use between 1 and 64 actions.');
    const trigger = ensure(request.trigger);
    if (flows.some(f=>f!==old && f.spec.trigger===trigger && f.spec.event===request.event)) fail('This element already has a workflow for this event. Open it from Page workflows.');
    if (request.event === 'submit' && ix.nodes[request.trigger].tag !== 'form') fail('Choose a form as the submission trigger.');
    function guardChoice(value, allowed) {
      if (!allowed.includes(value)) fail('Choose a supported option for this action.');
    }
    let condition;
    if (request.condition) {
      const c = request.condition;
      const sourceID = ensure(c.source), row = ix.nodes[c.source];
      if (!tests.has(c.test) || typeof c.value !== 'string') fail('Choose a condition from the list.');
      if (c.test === 'checked' && !targetKinds.checked(row)) fail('Choose a checkbox or radio button for this condition.');
      if (c.test === 'valid' && !targetKinds.valid(row)) fail('Choose a form or input field to check validity.');
      if (['less','greater'].includes(c.test) && !numeric(c.value)) fail('Enter a finite number for the comparison.');
      condition = {source:sourceID, test:c.test, value:c.value};
    }
    function compileStep(a) {
      if ((!kinds.has(a.kind) && !newActions.has(a.kind) && !deviceActions.has(a.kind)) || typeof a.value!=='string' || typeof a.detail!=='string') fail('Invalid action.');
      const targetedAction = targeted.has(a.kind) || newActions.has(a.kind) || deviceTargets.has(a.kind) || a.kind==='chooseFile';
      const target = targetedAction ? ensure(a.target) : '';
      if (['text','chooseFile','calculate','copyValue'].includes(a.kind) && (['img','br','hr','select','video','audio','canvas','picture','embed','object','meter','progress'].includes(ix.nodes[a.target].tag) ||
        (ix.nodes[a.target].tag==='input' && /^(file|checkbox|radio|image|hidden|color)$/i.test(ix.nodes[a.target].attrs.type?.value)))) fail('Choose a text element, result display, or text field to show the result.');
      if (['color','background'].includes(a.kind) && !/^#[0-9a-f]{6}$/i.test(a.value)) fail('Choose a six-digit color.');
      if (a.kind==='downloadText' && (!a.value.trim() || /[\/\\\x00-\x1f]/.test(a.value))) fail('Enter a file name without folder separators.');
      if (a.kind==='dialog' && !a.value.trim()) fail('Give the dialog a title.');
      if (a.kind==='download' || a.kind==='upload') checkLocation(a.value,a.kind==='download');
      if (a.kind==='upload' && !a.detail.trim()) fail('Enter the file field name expected by your server.');
      const result = {kind:a.kind, target, value:a.value, detail:a.detail};
      const row = ix.nodes[a.target];
      switch (a.kind) {
        case 'cameraStart': if (!targetKinds.video(row)) fail('Choose a video element for the camera preview.'); break;
        case 'cameraSnapshot': if (!targetKinds.image(row)) fail('Choose an image element for the snapshot.'); break;
        case 'micStart': if (!targetKinds.level(row)) fail('Choose a meter, progress bar or readout for the microphone level.'); break;
        case 'serialOpen': checkNumber(a.value,1,4000000,'Baud rate'); break;
        case 'serialRead': if (!targetKinds.reading(row)) fail('Choose a text readout for the serial line.'); break;
        case 'serialWrite':
          guardChoice(a.detail,['none','lf','crlf']);
          if (a.input != null) result.input = ensure(a.input);
          else if (!a.value.length && a.detail==='none') fail('Enter text or choose a line ending to send.');
          break;
        case 'usbOpen': {
          const opts=a.settings || {};
          const settings={vendor:opts.vendor, product:opts.product, configuration:opts.configuration, interface:opts.interface, alternate:opts.alternate};
          for (const key of ['vendor','product']) {
            if (typeof settings[key] !== 'string' || (settings[key] && !/^[0-9a-f]{4}$/i.test(settings[key]))) fail('Enter four hexadecimal digits for the USB '+key+' ID or leave it empty.');
          }
          if (settings.product && !settings.vendor) fail('A USB product filter also needs a vendor ID.');
          checkNumber(settings.configuration,1,255,'USB configuration');
          checkNumber(settings.interface,0,255,'Interface number');
          checkNumber(settings.alternate,0,255,'Alternate setting');
          result.settings=settings; break;
        }
        case 'usbRead':
          if (!targetKinds.reading(row)) fail('Choose a text readout for incoming USB bytes.');
          checkNumber(a.value,1,15,'IN endpoint'); checkNumber(a.detail,1,4096,'Read length'); break;
        case 'usbWrite':
          checkNumber(a.value,1,15,'OUT endpoint');
          if (a.input != null) result.input=ensure(a.input);
          else if (a.detail.length>16384 || !/^(?:[0-9a-f]{2}\s*)+$/i.test(a.detail.trim())) fail('Enter hex byte pairs, for example 01 0A FF.');
          break;
        case 'copyValue': result.input = ensure(a.input); break;
        case 'calculate':
          result.input = ensure(a.input);
          if (!operations.has(a.value)) fail('Choose a calculation operation.');
          if (a.constant == null) result.operand = ensure(a.operand);
          else {
            if (!numeric(a.constant)) fail('Enter a finite number for the constant.');
            result.constant = a.constant;
          }
          if (!Number.isInteger(a.digits) || a.digits < -1 || a.digits > 8) fail('Choose automatic precision or 0 to 8 decimal places.');
          if (typeof a.invalid !== 'string' || !a.invalid.trim()) fail('Enter a message for an invalid calculation.');
          result.digits = a.digits;
          result.invalid = a.invalid;
          break;
        case 'classChange':
          guardChoice(a.value, ['add','remove','toggle']);
          if (!a.detail || /[\s\x00]/.test(a.detail)) fail('Enter one CSS class name without spaces.');
          break;
        case 'checked':
          if (!targetKinds.checked(row)) fail('Choose a checkbox or radio button.');
          guardChoice(a.value, ['check','uncheck','toggle']); break;
        case 'enabled':
          if (!targetKinds.control(row)) fail('Choose a form control to enable or disable.');
          guardChoice(a.value, ['enable','disable']); break;
        case 'resetForm': if (!targetKinds.form(row)) fail('Choose a form to reset.'); break;
        case 'disclosure':
          if (!targetKinds.details(row)) fail('Choose a details element to open or close.');
          guardChoice(a.value, ['open','close','toggle']); break;
        case 'mediaControl':
          if (!targetKinds.media(row)) fail('Choose an audio or video element.');
          guardChoice(a.value, ['play','pause']); break;
        case 'focus':
          if (!['input','button','textarea','select','summary','a','audio','video'].includes(row.tag) &&
              !row.attrs.tabindex && !row.attrs.contenteditable) fail('Choose a focusable field, link, control, or element with tabindex.');
          break;
      }
      return result;
    }
    const steps = request.steps.map(compileStep), otherSteps = alternate.map(compileStep);
    const extended = !!condition || !classicEvents.includes(request.event) || steps.some(a => newActions.has(a.kind));
    const spec={version:extended ? 2 : 1,trigger,event:request.event,preventDefault:!!request.preventDefault,steps};
    if (condition) { spec.condition=condition; spec.otherwise=otherSteps; }
    const devices = hardware(spec);
    if (devices) spec.version=3;
    const at=old ? old.n.start : body[0].close;
    const nl = old ? nlOf(s.slice(at,old.n.end)) : nlOf(s);
    const helper = devices && !support ? supportBlock(nl) : '';
    patches.push({start:at,end:old ? old.n.end : at,text:helper+block(key,spec,nl)});
    if (!devices && old && hardware(old.spec) && !siblingsNeedDevice && support) removeSupport();
    return patched(ix.nodes[request.trigger].start);
  }
  function workflowIssueRange(s) {
    try { inspect(s); return []; }
    catch (error) { return error.range || []; }
  }
  return {workflows, editWorkflow, workflowIssueRange};
}
if (typeof module !== 'undefined') module.exports = interactionEngine(require('./source.js'), require('node:fs').readFileSync(require.resolve('./device-runtime.js'),'utf8'));
else Object.assign(WebBench, interactionEngine(WebBench, WebBenchDeviceCode));
