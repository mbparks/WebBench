"""Exercise authored JavaScript after the production Swift store saves and exports a site."""
import functools
import http.server
import json
import os
import shutil
import subprocess
import tempfile
import threading
from email.parser import BytesParser
from email.policy import default
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Resources"

def call(resource, method, *args):
    script = "const api=require(process.argv[1]);const [m,a]=JSON.parse(require('fs').readFileSync(0));process.stdout.write(JSON.stringify(api[m](...a)));"
    return json.loads(subprocess.check_output(["node", "-e", script, str(RES / (resource + ".js"))],
                                             input=json.dumps([method, args]).encode()))

def step(kind, value="", detail="", target=-1):
    return dict(kind=kind, value=value, detail=detail, target=target)

class SiteHandler(http.server.SimpleHTTPRequestHandler):
    received = []

    def do_POST(self):
        assert self.path == "/receive"
        data = self.rfile.read(int(self.headers["Content-Length"]))
        msg = BytesParser(policy=default).parsebytes(
            ("Content-Type: " + self.headers["Content-Type"] + "\r\n\r\n").encode() + data)
        part, = msg.iter_parts()
        self.received.append((part.get_param("name", header="content-disposition"),
                              part.get_filename(), part.get_payload(decode=True)))
        self.send_response(503 if len(self.received) == 1 else 201)
        self.end_headers()

    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory() as temp, sync_playwright() as pw:
    tmp = Path(temp)
    site = tmp / "site"
    site.mkdir()
    base = """<!doctype html><html><head><meta charset="utf-8"><style>
    #display{display:flex}button{margin:4px}body{font:16px system-ui}
    </style></head><body><form><button id="run" onclick="window.presses++">Run</button></form>
    <p id="display">Standby</p><output id="out">Idle</output><input id="number">
    <button id="show">Show</button><button id="choose">Choose</button><button id="send">Send</button>
    <button id="zip">Download</button><button id="note">Note</button><script>window.presses=0;</script>
    </body></html>""".replace("\n", "\r\n")
    (site / "index.html").write_bytes(b"\xef\xbb\xbf" + base.encode())
    (site / "guide.pdf").write_bytes(b"%PDF-1.4\nFixture bytes\n")
    output = tmp / "export"
    html = base
    nodes = call("source", "index", base)["nodes"]
    ids = {n["attrs"]["id"]["value"]: n["id"] for n in nodes if "id" in n["attrs"]}
    def add(trigger, steps, event="click"):
        global html
        html = call("workflows", "editWorkflow", html, dict(
            key=trigger, existing=False, trigger=ids[trigger], event=event, preventDefault=True, steps=steps))["text"]

    add("run", [step("text", "<b>ready</b>", target=ids["out"]), step("color", "#3344aa", target=ids["out"]),
                step("background", "#f0eecc", target=ids["out"]), step("hide", target=ids["display"]),
                step("dialog", "Signal acquired", "Close to continue."),
                step("text", "Complete", target=ids["display"])])
    add("show", [step("toggle", target=ids["display"])])
    add("number", [step("show", target=ids["display"])], "input")
    add("choose", [step("chooseFile", target=ids["out"])])
    add("send", [step("upload", "/receive", "measurement"), step("text", "Uploaded", target=ids["out"])])
    add("zip", [step("download", "guide.pdf", "manual.pdf")])
    add("note", [step("downloadText", "result.txt", "Signal Δ = 4\n")])
    staged = tmp / "staged"
    staged.write_bytes(html.encode())
    probe = tmp / "store"
    subprocess.run(["swiftc", ROOT / "Sources/Project.swift", ROOT / "Tests/StorageProbe.swift", "-o", probe], check=True)
    subprocess.run([probe, site, "index.html", staged], check=True)
    saved = (site / "index.html").read_bytes()
    assert saved == b"\xef\xbb\xbf" + html.encode()
    subprocess.run([probe, site], check=True)
    assert (site / "index.html").read_bytes() == saved
    subprocess.run([probe, "--snapshot", site, "index.html", staged, output], check=True)
    assert (output / "index.html").read_bytes() == saved
    assert (output / "guide.pdf").read_bytes() == (site / "guide.pdf").read_bytes()
    for flow in call("workflows", "workflows", html)["flows"]:
        assert call("workflows", "editWorkflow", html, {**flow, "existing": True})["text"] == html

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(SiteHandler, directory=str(output)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        browser = pw.chromium.launch(executable_path=os.environ.get("CHROMIUM") or shutil.which("chromium"),
                                     args=["--no-sandbox"])
        p = browser.new_page()
        p.set_default_timeout(5000)
        errors = []
        p.on("pageerror", lambda err: errors.append(str(err)))
        p.goto(f"http://127.0.0.1:{server.server_port}/index.html")
        p.locator("#run").click()
        expect(p.locator("#out")).to_have_text("<b>ready</b>")
        expect(p.locator("#out")).to_have_css("color", "rgb(51, 68, 170)")
        expect(p.locator("#out")).to_have_css("background-color", "rgb(240, 238, 204)")
        expect(p.locator("#display")).to_be_hidden()
        expect(p.get_by_role("dialog", name="Signal acquired")).to_be_visible()
        expect(p.locator("#display")).to_have_text("Standby")
        p.get_by_role("button", name="Close").click()
        expect(p.locator("#display")).to_have_text("Complete")
        assert p.evaluate("window.presses") == 1
        p.locator("#show").click()
        expect(p.locator("#display")).to_have_css("display", "flex")
        p.locator("#show").click()
        expect(p.locator("#display")).to_be_hidden()
        p.locator("#number").fill("12")
        expect(p.locator("#display")).to_be_visible()

        payload = dict(name="reading.txt", mimeType="text/plain", buffer=b"V=2.5\n")
        p.locator("#choose").click()
        p.locator('dialog input').set_input_files(payload)
        p.get_by_role("button", name="Use file").click()
        expect(p.locator("#out")).to_have_text("reading.txt")
        p.locator("#send").click()
        p.locator("dialog input").set_input_files(payload)
        p.get_by_role("button", name="Cancel", exact=True).click()
        expect(p.locator("#out")).to_have_text("reading.txt")
        assert not SiteHandler.received
        p.locator("#send").click()
        p.locator("dialog input").set_input_files(payload)
        send = p.get_by_role("button", name="Upload", exact=True)
        send.click()
        expect(p.locator("dialog [role=status]")).to_contain_text("503")
        send.click()
        expect(p.get_by_role("dialog", name="Upload complete")).to_be_visible()
        p.get_by_role("button", name="Close").click()
        expect(p.locator("#out")).to_have_text("Uploaded")
        assert SiteHandler.received == [("measurement", "reading.txt", b"V=2.5\n")] * 2

        for trigger, name, content in [("zip","manual.pdf",(site/"guide.pdf").read_bytes()),
                                      ("note","result.txt","Signal Δ = 4\n".encode())]:
            with p.expect_download() as event:
                p.locator("#" + trigger).click()
            assert event.value.suggested_filename == name
            assert event.value.path().read_bytes() == content
        assert not errors, errors
        assert (output / "index.html").read_bytes() == saved
        print("PASS exported site: ordered text/color/visibility/dialog, input trigger, handwritten handler, file picker, download bytes, multipart server failure/retry/cancel/success.")

        # Run the same emitted JS with the preview scheme injected as a lexical location.
        # Chromium does not implement the app's WKURLSchemeHandler.
        p.goto("about:blank")
        p.set_content(base)
        p.evaluate("""code => {
          const parsed = new DOMParser().parseFromString(code, 'text/html');
          for (const script of parsed.querySelectorAll('script[data-webbench-workflow]')) {
            Function('location', script.textContent)({protocol: 'webbench:'});
          }
          window.fetch = () => { throw Error("Unexpected preview network request"); };
        }""", html)
        p.locator("#send").click()
        p.locator("dialog input").set_input_files(payload)
        p.get_by_role("button", name="Test upload").click()
        expect(p.get_by_role("dialog", name="Upload preview")).to_be_visible()
        p.get_by_role("button", name="Close").click()
        expect(p.locator("#out")).to_have_text("Uploaded")
        p.locator("#zip").click()
        expect(p.get_by_role("dialog", name="Download preview")).to_contain_text("manual.pdf")
        assert len(SiteHandler.received) == 2
        print("PASS simulated WebBench scheme: upload and download rehearsal, no transport.")

        marker = "data-wb-pick-fixture"
        indexed = call("source", "info", base, marker)
        p.goto("about:blank")
        p.set_content(indexed["html"])
        p.evaluate("window.events=[]; window.webkit={messageHandlers:{design:{postMessage:e=>events.push(e)}}}")
        settings = dict(marker=marker, token="pick", tree=indexed["nodes"])
        p.add_script_tag(content="const WB=" + json.dumps(settings) + ";\n" + "\n".join(
            (RES / (n + ".js")).read_text() for n in ["source","appearance","layout-drop","arrange","canvas"]))
        p.evaluate("webBenchWorkflowMode(true); events.length=0")
        p.locator("#run").click()
        p.locator("#out").click()
        p.keyboard.press("Escape")
        assert p.evaluate("events.map(e=>[e.kind,e.id??null])") == [
            ["workflowPick",ids["run"]],["workflowPick",ids["out"]],["workflowCancelPick",None]]
        assert p.evaluate("window.presses") == 0
        p.evaluate("webBenchWorkflowMode(false); events.length=0")
        p.locator("#out").click()
        assert p.evaluate("events.some(e => e.kind==='select' && e.id===WB.tree.find(n => n.tag==='output').id)")
        p.goto((ROOT / "Fixtures/Signal-check.html").as_uri())
        p.get_by_role("button", name="Test signal").click()
        expect(p.locator("output")).to_have_text("Signal acquired")
        print("PASS source-mapped canvas picks suppress editing, Escape cancels, normal selection resumes; standalone example runs by file URL.")
        browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
