"""Exercise the actual empty-canvas overlay and first placement in Chromium."""
from pathlib import Path
import json
import os
import shutil
import subprocess

from playwright.sync_api import sync_playwright, expect

root = Path(__file__).resolve().parents[1]
resources = root / "Resources"
source = (resources / "canvas-page.html").read_text()
marker = "data-test-wb-node"

def engine(method, args):
    script = "const e=require('./Resources/source.js');const [m,a]=JSON.parse(require('fs').readFileSync(0));process.stdout.write(JSON.stringify(e[m](...a)));"
    return json.loads(subprocess.check_output(["node", "-e", script], cwd=root,
                                               input=json.dumps([method, args]).encode()))

def render(page, html):
    indexed = engine("info", [html, marker])
    page.goto("about:blank")
    page.set_content(indexed["html"])
    # Capture the injected shadow for assertions while retaining closed-shadow event behavior.
    page.evaluate("""() => {
        window.roots = []; window.events = [];
        const attach = Element.prototype.attachShadow;
        Element.prototype.attachShadow = function(options) {
          const shadow = attach.call(this, options); window.roots.push(shadow); return shadow;
        };
        window.webkit = {messageHandlers:{design:{postMessage:e=>window.events.push(e)}}};
    }""")
    config = {"token": "test", "tree": indexed["nodes"], "marker": marker}
    scripts = ["source", "appearance", "layout-drop", "arrange", "canvas"]
    page.add_script_tag(content="const WB=" + json.dumps(config) + ";\n" +
                        "\n".join((resources / (name + ".js")).read_text() for name in scripts))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=os.environ.get("CHROMIUM") or shutil.which("chromium"),
                                 args=["--no-sandbox"])
    page = browser.new_page(viewport={"width": 880, "height": 570})
    render(page, source)
    guide = "() => window.roots[0].querySelector('.blank-guide')"
    assert page.evaluate("() => getComputedStyle((" + guide + ")()).display") == "grid"
    assert page.evaluate("() => document.elementFromPoint(440,285) === document.body")
    if os.environ.get("WEBBENCH_GUIDE_SCREENSHOT"):
        page.screenshot(path=os.environ["WEBBENCH_GUIDE_SCREENSHOT"])
    page.evaluate("webBenchPaletteDrag('Button','hover',0.5,0.5,false,false)")
    assert page.evaluate("() => getComputedStyle((" + guide + ")()).display") == "none"
    page.evaluate("webBenchPaletteDrag('Button','cancel',0.5,0.5,false,false)")
    assert page.evaluate("() => getComputedStyle((" + guide + ")()).display") == "grid"
    page.evaluate("webBenchTools('Heading',false)")
    assert page.evaluate("() => getComputedStyle((" + guide + ")()).display") == "none"
    page.mouse.click(440, 285)
    msg = page.evaluate("() => events.find(e => e.item === 'Heading' && e.point)")
    assert msg and msg["point"] == {"x": 440, "y": 285}, msg
    edited = engine("run", [source, msg["id"], {"kind":"insert", "item":"Heading", "point":msg["point"]}])["text"]
    assert "blank-guide" not in edited and "sample-pieces" not in edited and marker not in edited
    render(page, edited)
    expect(page.locator("h2")).to_have_text("Heading")
    assert page.evaluate(guide) is None
    page.set_viewport_size({"width": 390, "height": 844})
    render(page, source.replace("</body>", "Existing page text</body>"))
    assert page.evaluate(guide) is None
    page.set_content(edited)
    assert page.locator("body").inner_text() == "Heading"
    print("PASS empty-board guide, hover/cancel, click-through placement, source-only output and existing page. Chromium", browser.version)
    browser.close()
