// WebBench device support v1
(() => {
  "use strict";
  const simulated = location.protocol === "webbench:";
  const sessions = new Map();
  const labels = {serial:"Serial port", usb:"USB device", camera:"Camera", mic:"Microphone"};
  let notice, noticeText, noticeTimer;
  function report(text, failure = false) {
    if (!notice?.isConnected) {
      notice = document.createElement("aside");
      notice.setAttribute("aria-label", "Device status");
      notice.style.cssText = "position:fixed;bottom:12px;right:12px;z-index:2147483646;max-width:min(32rem,90vw);padding:10px 14px;background:#193c31;color:white;border-radius:6px;font:14px/1.4 system-ui;box-shadow:0 2px 12px #0004";
      noticeText = document.createElement("span");
      noticeText.setAttribute("role","status");
      const dismiss = document.createElement("button");
      dismiss.type = "button";
      dismiss.textContent = "×";
      dismiss.setAttribute("aria-label","Dismiss device status");
      dismiss.style.marginLeft = "0.75em";
      dismiss.onclick = () => notice.remove();
      notice.append(noticeText,dismiss);
      document.body.append(notice);
    }
    noticeText.textContent = (simulated ? "Simulated device · " : "") + text;
    clearTimeout(noticeTimer);
    if (!failure) noticeTimer = setTimeout(() => notice?.remove(), 4500);
  }
  function check(session) {
    if (session.stopped || sessions.get(session.kind) !== session) throw new DOMException("Operation canceled.", "WebBenchCancellation");
  }
  function active(kind) {
    const session = sessions.get(kind);
    if (!session?.ready || session.stopped) throw new Error("Start the " + labels[kind].toLowerCase() + " first.");
    return session;
  }
  function output(node, text) {
    if (node.matches("input,textarea,output")) node.value = text;
    else if (node.matches("meter,progress")) node.value = node.max * Number(text) / 100;
    else node.textContent = text;
  }
  function release(s) {
    if (s.cleanup) return s.cleanup;
    s.stopped = true;
    s.cleanup = (async () => {
      try {
        s.events.abort();
        clearInterval(s.timer);
        s.stream?.getTracks().forEach(track => track.stop());
        if (s.video && s.stream && s.video.srcObject === s.stream) {
          s.video.srcObject = s.previousStream;
          s.video.muted = s.wasMuted;
          s.video.playsInline = s.wasInline;
        }
        if (s.frame && s.video?.getAttribute("poster") === s.frame) {
          if (s.poster != null) s.video.setAttribute("poster",s.poster);
          else s.video.removeAttribute("poster");
        }
        if (s.meter) output(s.meter,"0");
        s.source?.disconnect();
        if (s.context && s.context.state !== "closed") await s.context.close();
        if (s.reader) await s.reader.cancel().catch(() => {});
        if (s.writer) await s.writer.abort().catch(() => {});
        // Closing a USB device aborts pending transfers, including a read with no data.
        if (s.usbOpened && s.device.opened) await s.device.close();
        await Promise.allSettled([s.readJob,s.writeJob]);
        if (s.portOpened) await s.port.close();
      } finally {
        if (sessions.get(s.kind) === s) sessions.delete(s.kind);
      }
    })();
    return s.cleanup;
  }
  async function stop(kind) {
    const s = sessions.get(kind);
    if (!s) return;
    s.stopped = true;
    if (s.ready || s.stream) await release(s);
    else if (s.context && s.context.state !== "closed") await s.context.close();
    // A browser chooser cannot be canceled by a page. start() disposes a late grant.
  }
  async function start(kind, connect) {
    if (sessions.has(kind)) throw new Error(labels[kind] + " is active or has a pending request.");
    if (!simulated && !window.isSecureContext) throw new Error("Open this site on HTTPS or localhost to use devices.");
    if (!simulated && navigator.userActivation?.isActive === false) throw new Error("Connect from a visitor click or key press.");
    const s = {kind, events:new AbortController(), ready:false, stopped:false};
    sessions.set(kind,s);
    try {
      await connect(s);
      check(s);
      s.ready = true;
    } catch (error) {
      const canceled = s.stopped;
      await release(s);
      if (canceled) throw new DOMException("Operation canceled.", "WebBenchCancellation");
      throw error;
    }
  }
  function unplug(s) {
    if (s.stopped || sessions.get(s.kind) !== s) return;
    stop(s.kind).catch(error => report(error.message,true));
    report(labels[s.kind] + " disconnected.",true);
  }
  function trackEnds(s) {
    for (const track of s.stream.getTracks()) track.addEventListener("ended", () => unplug(s), {signal:s.events.signal});
  }
  function captureAPI() {
    if (!navigator.mediaDevices?.getUserMedia) throw new Error("Media capture is unavailable. Open the site in a browser on HTTPS or localhost.");
    return navigator.mediaDevices;
  }
  function sampleFrame() {
    const canvas = document.createElement("canvas");
    canvas.width = 640; canvas.height = 360;
    const ctx = canvas.getContext("2d");
    ["#e1cc76","#77ab96","#498397","#a76979","#55547b","#233c33"].forEach((color,i) => {
      ctx.fillStyle = color; ctx.fillRect(i*107,0,107,360);
    });
    ctx.fillStyle = "#16352e"; ctx.fillRect(0,268,640,92);
    ctx.fillStyle = "white"; ctx.font = "24px system-ui";
    ctx.fillText("WebBench · Simulated camera",24,321);
    return canvas.toDataURL("image/png");
  }
  async function camera(s, video) {
    if (simulated) {
      s.video = video;
      s.poster = video.getAttribute("poster");
      s.frame = sampleFrame();
      video.poster = s.frame;
      return;
    }
    s.stream = await captureAPI().getUserMedia({video:true, audio:false});
    check(s); trackEnds(s);
    s.video = video;
    s.wasMuted = video.muted; s.wasInline = video.playsInline; s.previousStream = video.srcObject;
    video.muted = true; video.playsInline = true; video.srcObject = s.stream;
    await video.play();
  }
  function snapshot(target) {
    const s = active("camera");
    if (simulated) { target.src = s.frame; return; }
    const v = s.video;
    if (!v.videoWidth || v.readyState < 2) throw new Error("Wait for a camera frame and try again.");
    const canvas = document.createElement("canvas");
    canvas.width = v.videoWidth; canvas.height = v.videoHeight;
    canvas.getContext("2d").drawImage(v,0,0);
    target.src = canvas.toDataURL("image/png");
  }
  async function microphone(s, meter) {
    s.meter = meter;
    if (simulated) {
      let phase=0;
      const update = () => output(meter,String(Math.round(42+20*Math.sin(phase+=0.25))));
      update(); s.timer = setInterval(update,120); return;
    }
    const api = captureAPI();
    if (!window.AudioContext) throw new Error("This browser cannot measure microphone level.");
    s.context = new AudioContext();
    // Request audio activation and media permission during the same visitor action.
    const resumed = s.context.resume();
    resumed.catch(() => {});
    s.stream = await api.getUserMedia({audio:true,video:false});
    check(s); trackEnds(s);
    await resumed; check(s);
    const analyser = s.context.createAnalyser();
    analyser.fftSize = 1024;
    s.source = s.context.createMediaStreamSource(s.stream);
    s.source.connect(analyser);
    const samples = new Float32Array(analyser.fftSize);
    const measure = () => {
      analyser.getFloatTimeDomainData(samples);
      let sum = 0;
      for (const v of samples) sum += v*v;
      output(meter,String(Math.min(100,Math.round(100*Math.sqrt(sum/samples.length)))));
    };
    measure(); s.timer = setInterval(measure,100);
  }
  async function serial(s, baud) {
    s.buffer = ""; s.decoder = new TextDecoder(); s.queue = [];
    if (simulated) return;
    if (!navigator.serial?.requestPort) throw new Error("Web Serial is unavailable here. Open the exported site in a compatible desktop browser.");
    s.port = await navigator.serial.requestPort(); check(s);
    navigator.serial.addEventListener("disconnect", event => {
      if (event.target === s.port || event.port === s.port) unplug(s);
    }, {signal:s.events.signal});
    await s.port.open({baudRate:baud}); s.portOpened = true;
  }
  async function readLine(s) {
    if (simulated) return s.queue.shift() ?? "TEMP=23.4";
    if (!s.port.readable) throw new Error("This port has no readable stream.");
    s.reader = s.port.readable.getReader();
    try {
      for (;;) {
        check(s);
        const end = s.buffer.indexOf("\n");
        if (end >= 0) {
          const line = s.buffer.slice(0,end).replace(/\r$/,"");
          s.buffer = s.buffer.slice(end+1); return line;
        }
        const {value,done} = await s.reader.read();
        check(s);
        if (done) throw new Error("The serial input stream ended. Disconnect and reconnect.");
        s.buffer += s.decoder.decode(value,{stream:true});
        if (s.buffer.length > 65536) { s.buffer=""; s.decoder=new TextDecoder(); throw new Error("Serial input exceeded the 65,536-character buffer."); }
      }
    } finally { s.reader.releaseLock(); s.reader = null; }
  }
  async function writeSerial(s,text,ending) {
    if (text.length > 65536) throw new Error("Send up to 65,536 characters at a time.");
    if (simulated) { if (s.queue.length>=32) s.queue.shift(); s.queue.push(text); return; }
    if (!s.port.writable) throw new Error("This port has no writable stream.");
    s.writer = s.port.writable.getWriter();
    try { await s.writer.write(new TextEncoder().encode(text + ({none:"",lf:"\n",crlf:"\r\n"})[ending])); }
    finally { s.writer.releaseLock(); s.writer=null; }
  }
  async function usb(s, options) {
    s.bytes = new Uint8Array([0x57,0x42]);
    if (simulated) return;
    if (!navigator.usb?.requestDevice) throw new Error("WebUSB is unavailable here. Open the exported site in a compatible desktop browser.");
    const filter = {};
    if (options.vendor) filter.vendorId = parseInt(options.vendor,16);
    if (options.product) filter.productId = parseInt(options.product,16);
    s.device = await navigator.usb.requestDevice({filters:options.vendor ? [filter] : []}); check(s);
    navigator.usb.addEventListener("disconnect",e => { if (e.device===s.device) unplug(s); },{signal:s.events.signal});
    if (s.device.opened) throw new Error("The USB device is already open on this page.");
    await s.device.open(); s.usbOpened = true; check(s);
    const config = Number(options.configuration);
    if (s.device.configuration?.configurationValue !== config) await s.device.selectConfiguration(config);
    check(s);
    s.interfaceNumber = Number(options.interface);
    await s.device.claimInterface(s.interfaceNumber); check(s);
    const iface = s.device.configuration.interfaces.find(i=>i.interfaceNumber===s.interfaceNumber);
    if (!iface) throw new Error("The selected device has no matching interface.");
    if (iface.alternate.alternateSetting !== Number(options.alternate)) await s.device.selectAlternateInterface(s.interfaceNumber,Number(options.alternate));
  }
  function endpoint(s, number, direction) {
    const iface = s.device.configuration?.interfaces.find(i=>i.interfaceNumber===s.interfaceNumber);
    if (!iface?.alternate.endpoints.some(ep=>ep.endpointNumber===number && ep.direction===direction && ["bulk","interrupt"].includes(ep.type))) {
      throw new Error("No bulk or interrupt " + direction.toUpperCase() + " endpoint " + number + " on the claimed interface.");
    }
  }
  function bytes(text) {
    const clean = text.trim();
    if (!clean || clean.length>16384 || !/^(?:[0-9a-f]{2}\s*)+$/i.test(clean)) throw new Error("Enter hex byte pairs, for example 01 0A FF.");
    return Uint8Array.from(clean.match(/[0-9a-f]{2}/gi), pair=>parseInt(pair,16));
  }
  async function transfer(s, direction, perform) {
    const slot = direction + "Job";
    if (s[slot]) throw new Error("Another " + direction + " is pending.");
    s[slot] = perform();
    try { const result = await s[slot]; check(s); return result; }
    catch (error) { check(s); throw error; }
    finally { s[slot] = null; }
  }
  async function operate(kind, target, value, detail, options, source) {
    const text = source ? ("value" in source ? String(source.value) : source.textContent) : value;
    switch (kind) {
      case "cameraStart": await start("camera",s=>camera(s,target)); return "Camera started.";
      case "cameraStop": await stop("camera"); return "Camera stopped.";
      case "cameraSnapshot": snapshot(target); return "Frame captured.";
      case "micStart": await start("mic",s=>microphone(s,target)); return "Microphone level active.";
      case "micStop": await stop("mic"); return "Microphone stopped.";
      case "serialOpen": await start("serial",s=>serial(s,Number(value))); return "Serial port connected.";
      case "serialClose": await stop("serial"); return "Serial connection stopped.";
      case "serialRead": {
        const s = active("serial"); report("Waiting for a newline from the serial device…");
        output(target,await transfer(s,"read",()=>readLine(s))); return "Serial line received.";
      }
      case "serialWrite": {
        const s = active("serial");
        await transfer(s,"write",()=>writeSerial(s,text,detail)); return "Serial text sent.";
      }
      case "usbOpen": await start("usb",s=>usb(s,options)); return "USB device connected.";
      case "usbClose": await stop("usb"); return "USB connection stopped.";
      case "usbRead": {
        const s=active("usb"), ep=Number(value), size=Number(detail);
        report("Waiting for USB input…");
        const received=await transfer(s,"read",async () => {
          if (simulated) return s.bytes.slice(0,size);
          endpoint(s,ep,"in");
          const result=await s.device.transferIn(ep,size);
          if (result.status !== "ok" || !result.data) throw new Error("USB read returned " + result.status + ".");
          return new Uint8Array(result.data.buffer,result.data.byteOffset,result.data.byteLength);
        });
        output(target,Array.from(received,b=>b.toString(16).padStart(2,"0").toUpperCase()).join(" "));
        return "USB bytes received.";
      }
      case "usbWrite": {
        const s=active("usb"), ep=Number(value), payload=bytes(source ? text : detail);
        await transfer(s,"write",async () => {
          if (simulated) { s.bytes=payload; return; }
          endpoint(s,ep,"out");
          const result=await s.device.transferOut(ep,payload);
          if (result.status !== "ok" || result.bytesWritten !== payload.length) throw new Error("USB write was incomplete (" + result.status + ").");
        });
        return "USB bytes sent.";
      }
    }
    throw new Error("Unknown device action.");
  }
  const key = Symbol.for("org.greenshoegarage.webbench.devices.v1");
  window[key] = async (...args) => {
    try { report(await operate(...args)); return true; }
    catch (error) {
      if (error.name === "WebBenchCancellation") return false;
      const reason = error.name === "NotAllowedError" ? "Permission was denied. Check the site’s device permissions and try again."
        : error.name === "NotFoundError" ? "No device was selected or available." : error.message;
      report(reason || "Device action failed.",true);
      return false;
    }
  };
  addEventListener("pagehide",() => {
    for (const kind of sessions.keys()) stop(kind).catch(() => {});
  });
})();
