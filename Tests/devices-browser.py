"""Run exported device workflows over localhost with Chromium test media and serial/USB doubles."""
import hashlib
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from threading import Thread

from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "Fixtures/Device-workbench.html"

class QuietHTTP(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

def observe(page, substring):
    expect(page.locator('aside[aria-label="Device status"] [role="status"]')).to_contain_text(substring)

def click(page, identifier):
    page.locator("#" + identifier).click()

def variants(html):
    # Build a second page through the production compiler, with a follow-up step that
    # only successful device operations should reach.
    js = """
    const fs=require('node:fs'), compiler=require(process.argv[1]), src=require(process.argv[2]);
    let html=fs.readFileSync(0,'utf8');
    const ids=Object.fromEntries(src.index(html).nodes.filter(n=>n.attrs.id).map(n=>[n.attrs.id.value,n.id]));
    for (const key of ['test','usb-on','serial-send']) {
      const flow=compiler.workflows(html).flows.find(f=>f.key===key);
      if(key==='usb-on') flow.steps[0].settings={vendor:'2341',product:'0043',configuration:'2',interface:'3',alternate:'1'};
      if(key==='serial-send') {flow.steps[0].detail='crlf';flow.steps[0].input=null;flow.steps[0].value='HELLO';}
      flow.steps.push({kind:'text',target:ids['serial-result'],value:'Done',detail:''});
      html=compiler.editWorkflow(html,{...flow,existing:true}).text;
    }
    process.stdout.write(html);
    """
    return subprocess.check_output(["node","-e",js,str(ROOT/"Resources/workflows.js"),str(ROOT/"Resources/source.js")],input=html)

def exercise_settings(page):
    page.evaluate("probe.deny=true")
    click(page,"test")
    observe(page,"Permission was denied")
    expect(page.locator("#serial-result")).to_have_text("Waiting for a line")
    page.evaluate("probe.deny=false")
    click(page,"test")
    expect(page.locator("#serial-result")).to_have_text("Done")
    click(page,"serial-send")
    observe(page,"Serial text sent")
    assert page.evaluate("probe.serialWrites") == ["HELLO\r\n"]
    click(page,"serial-off")
    page.evaluate("probe.interface=3")
    click(page,"usb-on")
    observe(page,"USB device connected")
    assert page.evaluate("probe.filters") == [{"vendorId":0x2341,"productId":0x0043}]
    assert page.evaluate("[probe.claim,probe.device.configuration.configurationValue,probe.usedAlternate]") == [3,2,[3,1]]
    click(page,"usb-off")
    observe(page,"connection stopped")
    # Browser activation expires after a navigation. Invoke the handler without visitor input.
    page.reload()
    cdp = page.context.new_cdp_session(page)
    cdp.send("Runtime.evaluate",{"expression":"document.getElementById('test').click()","userGesture":False})
    cdp.detach()
    observe(page,"visitor click or key press")
    assert page.evaluate("probe.serialRequests || 0") == 0

def exercise_serial(page):
    click(page,"test")
    observe(page,"Serial port connected")
    assert page.evaluate("probe.baud") == 115200
    click(page,"test")
    observe(page,"active or has a pending request")
    assert page.evaluate("probe.serialRequests") == 1
    page.locator("#command").fill("PING µ")
    click(page,"serial-send")
    observe(page,"Serial text sent")
    assert page.evaluate("probe.serialWrites") == ["PING µ\n"]
    click(page,"serial-read")
    observe(page,"Waiting for a newline")
    page.evaluate("""() => {
      const data = new TextEncoder().encode("µ=2.5\\r\\nSECOND\\n");
      probe.rx.enqueue(data.slice(0,1)); probe.rx.enqueue(data.slice(1));
    }""")
    expect(page.locator("#serial-result")).to_have_text("µ=2.5")
    click(page,"serial-read")
    expect(page.locator("#serial-result")).to_have_text("SECOND")
    click(page,"serial-read")
    observe(page,"Waiting for a newline")
    click(page,"serial-off")
    observe(page,"connection stopped")
    assert page.evaluate("probe.serialCloses") == 1
    click(page,"test")
    observe(page,"Serial port connected")
    page.evaluate("navigator.serial.dispatchEvent(Object.assign(new Event('disconnect'),{port:probe.port}))")
    observe(page,"disconnected")
    page.wait_for_function("probe.serialCloses === 2")
    page.evaluate("probe.delay=true")
    click(page,"test")
    page.wait_for_function("!!probe.grant")
    click(page,"serial-off")
    page.evaluate("probe.grant(); probe.delay=false")
    click(page,"test")
    observe(page,"Serial port connected")
    click(page,"serial-off")
    observe(page,"connection stopped")

def exercise_usb(page):
    page.evaluate("probe.claimFails=true")
    click(page,"usb-on")
    observe(page,"Interface busy")
    assert page.evaluate("probe.usbCloses") == 1
    page.evaluate("probe.claimFails=false")
    click(page,"usb-on")
    observe(page,"USB device connected")
    assert page.evaluate("[probe.filters,probe.claim]") == [[],0]
    click(page,"usb-send")
    observe(page,"USB bytes sent")
    assert page.evaluate("probe.usbWrites[0]") == [1,1,10,255]
    page.locator("#packet").fill("GG")
    click(page,"usb-send")
    observe(page,"hex byte pairs")
    assert page.evaluate("probe.usbWrites.length") == 1
    page.locator("#packet").fill("AB")
    page.evaluate("probe.short=true")
    click(page,"usb-send")
    observe(page,"incomplete")
    click(page,"usb-read")
    expect(page.locator("#usb-result")).to_have_text("BE EF")
    assert page.evaluate("probe.read") == [1,64]
    page.evaluate("probe.stall=true")
    click(page,"usb-read")
    observe(page,"stall")
    page.evaluate("probe.waitUSB=true")
    click(page,"usb-read")
    page.wait_for_function("!!probe.rejectUSB")
    click(page,"usb-off")
    observe(page,"connection stopped")
    assert page.evaluate("probe.usbCloses") == 2
    click(page,"usb-on")
    observe(page,"USB device connected")
    page.evaluate("navigator.usb.dispatchEvent(Object.assign(new Event('disconnect'),{device:probe.device}))")
    observe(page,"disconnected")
    page.wait_for_function("probe.usbCloses === 3")

def exercise_media(page):
    page.evaluate("probe.deny=true")
    for button in ("camera-on","mic-on","test"):
        click(page,button)
        observe(page,"Permission was denied")
    page.evaluate("probe.deny=false")
    click(page,"camera-on")
    observe(page,"Camera started")
    page.wait_for_function("document.querySelector('video').videoWidth > 0")
    click(page,"snap")
    page.wait_for_function("document.querySelector('#still').naturalWidth > 1")
    assert page.locator("#still").get_attribute("src").startswith("data:image/png;base64,")
    click(page,"mic-on")
    observe(page,"Microphone level active")
    page.wait_for_function("document.querySelector('#level').value > 0")
    assert page.evaluate("probe.streams.flatMap(s=>s.getTracks().map(t=>[t.kind,t.readyState]))") == [["video","live"],["audio","live"]]
    click(page,"camera-off")
    observe(page,"Camera stopped")
    assert page.evaluate("probe.streams[0].getVideoTracks()[0].readyState") == "ended"
    assert page.evaluate("document.querySelector('#feed').srcObject === null")
    click(page,"mic-off")
    observe(page,"Microphone stopped")
    assert page.evaluate("probe.streams[1].getAudioTracks()[0].readyState") == "ended"
    assert page.locator("#level").evaluate("el=>el.value") == 0
    click(page,"mic-on")
    observe(page,"Microphone level active")
    page.evaluate("dispatchEvent(new PageTransitionEvent('pagehide'))")
    page.wait_for_function("probe.streams.every(s=>s.getTracks().every(t=>t.readyState==='ended'))")

def rehearsal(page):
    click(page,"test")
    observe(page,"Simulated device")
    click(page,"serial-read")
    expect(page.locator("#serial-result")).to_have_text("TEMP=23.4")
    click(page,"serial-send")
    click(page,"serial-read")
    expect(page.locator("#serial-result")).to_have_text("PING")
    click(page,"usb-on")
    click(page,"usb-send")
    click(page,"usb-read")
    expect(page.locator("#usb-result")).to_have_text("01 0A FF")
    click(page,"camera-on")
    click(page,"snap")
    page.wait_for_function("document.querySelector('#still').naturalWidth === 640")
    click(page,"mic-on")
    page.wait_for_function("document.querySelector('#level').value > 0")
    for button in ["mic-off","camera-off","serial-off","usb-off"]:
        click(page,button)
        observe(page,"stopped")
    assert page.evaluate("[probe.streams.length,probe.serialRequests||0,probe.device||null]") == [0,0,None]

with TemporaryDirectory() as work:
    folder = Path(work)
    store = folder / "probe"
    subprocess.run(["swiftc",str(ROOT/"Sources/Project.swift"),str(ROOT/"Tests/StorageProbe.swift"),"-o",store],check=True)
    site, exported = folder/"site", folder/"exported"
    site.mkdir()
    original = b"\xef\xbb\xbf" + DEMO.read_bytes().replace(b"\n",b"\r\n")
    (site/"index.html").write_bytes(original)
    staged = folder/"staged.html"
    staged.write_bytes(original[3:])
    subprocess.run([store,site],check=True)
    subprocess.run([store,"--snapshot",site,"index.html",staged,exported],check=True)
    published = exported / "index.html"
    assert published.read_bytes() == original
    # Exercise the exact preview branch in Chromium. Native WKWebView uses the custom scheme.
    rehearsal_bytes = published.read_bytes().replace(b'const simulated = location.protocol === "webbench:";',
                                                     b'const simulated = true;')
    assert rehearsal_bytes != original
    (exported/"preview.html").write_bytes(rehearsal_bytes)
    (exported/"settings.html").write_bytes(variants(DEMO.read_bytes()))
    server = ThreadingHTTPServer(("127.0.0.1",0),partial(QuietHTTP,directory=exported))
    Thread(target=server.serve_forever,daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/"
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(executable_path=os.environ.get("CHROMIUM"),args=[
                "--no-sandbox","--use-fake-ui-for-media-stream","--use-fake-device-for-media-stream",
                "--autoplay-policy=no-user-gesture-required"])
            context = browser.new_context(permissions=["camera","microphone"])
            context.add_init_script(path=ROOT/"Tests/devices-api-double.js")
            page = context.new_page()
            errors = []
            page.on("pageerror",lambda exc: errors.append(str(exc)))
            page.goto(url)
            assert page.evaluate("isSecureContext")
            exercise_serial(page)
            exercise_usb(page)
            exercise_media(page)
            page.evaluate("delete navigator.serial; Object.defineProperty(navigator,'serial',{value:undefined})")
            click(page,"test")
            observe(page,"Web Serial is unavailable")
            page.goto(url+"settings.html")
            exercise_settings(page)
            page.goto(url+"preview.html")
            rehearsal(page)
            assert not errors, errors
            print("Chromium",browser.version,"passed serial and USB doubles, synthetic camera and mic, disposal, preview simulation and byte-exact export.")
            browser.close()
    finally:
        server.shutdown()
    assert hashlib.sha256(published.read_bytes()).digest()==hashlib.sha256(original).digest()
