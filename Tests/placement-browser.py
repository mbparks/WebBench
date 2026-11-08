"""Exercise free-canvas placement and persistence using the production Design scripts."""
import json
import os
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[1]
resources = Path(os.environ.get("WEBBENCH_RESOURCES", root / "Resources"))
marker = "data-wb-placement-check"
scripts = "\n".join((resources / f"{name}.js").read_text()
                    for name in ("source", "appearance", "layout-drop", "arrange", "canvas"))


def check(browser, storage, folder):
    engine = browser.new_page()
    engine.evaluate("() => {" + (resources / "source.js").read_text() + ";window.engine=WebBench}")
    def call(name, *args):
        return engine.evaluate("([n,args]) => engine[n](...args)", [name, args])

    # Match the viewport size used by the native editor at the selected page zoom.
    zoom = float(os.environ.get("WB_TEST_PAGE_ZOOM", "1"))
    page = browser.new_page(viewport={"width": round(800 * zoom), "height": round(560 * zoom)})
    def render(source):
        info = call("info", source, marker)
        assert not info["error"]
        page.goto("about:blank")
        page.set_content(info["html"])
        options = {"tree": info["nodes"], "marker": marker, "token": "placement"}
        page.evaluate("() => {const WB=" + json.dumps(options) + ";window.messages=[];"
                      "window.webkit={messageHandlers:{design:{postMessage:m=>messages.push(m)}}};" + scripts + "}")
    def last(kind):
        return page.evaluate("k=>messages.filter(m=>m.kind===k).at(-1)", kind)
    def palette(item, phase, x, y):
        page.evaluate("([i,p,x,y])=>webBenchPaletteDrag(i,p,x/innerWidth,y/innerHeight,false,false)",
                      [item, phase, x, y])
    def assert_insert(kind, item, parent, point):
        m = last(kind)
        assert m and m["item"] == item and m["id"] == int(page.locator(parent).get_attribute(marker)), (kind, m)
        assert m["point"] == point, m
        return m
    def insert(source, m):
        return call("run", source, m["id"], {"kind": "insert", "item": m["item"],
                    "before": m["before"], "point": m["point"]})["text"]
    def position(locator):
        return page.locator(locator).evaluate("e=>[e.offsetLeft,e.offsetTop]")

    original = (resources / "canvas-page.html").read_text().replace(
        "</body>", "<!-- keep Ω --></body>").replace("\n", "\r\n")
    render(original)
    palette("Star", "hover", 90, 80)
    assert page.locator("body > [inert]").count() == 1
    palette("Star", "drop", 90, 80)
    draft = insert(original, assert_insert("paletteDrop", "Star", "body", {"x": 90, "y": 80}))
    render(draft)
    star = page.locator(".shape-star")
    page.mouse.click(145, 130)
    assert last("select")["id"] == int(star.get_attribute(marker))
    page.evaluate("webBenchTools('Button',false)")
    page.mouse.move(148, 136)
    assert page.locator("body > button[inert]").count() == 1, "The free-page ghost nested in the shape"
    page.mouse.click(148, 136)
    draft = insert(draft, assert_insert("place", "Button", "body", {"x": 148, "y": 136}))
    render(draft)
    assert position("body > button") == [148, 136]
    page.evaluate("webBenchTools('',false)")
    page.mouse.move(184, 152)
    page.mouse.down()
    page.mouse.move(406, 336, steps=9)
    page.mouse.up()
    frame = last("frame")
    assert frame and frame["values"] == {"left": 370, "top": 320}, frame
    draft = call("run", draft, frame["id"], {"kind": "frame", "values": frame["values"]})["text"]

    # Keep document scroll out of the local box calculation and leave canceled previews out of source.
    render(draft)
    page.evaluate("scrollTo(0,220)")
    palette("Heading", "hover", 260, 240)
    palette("Heading", "cancel", 260, 240)
    assert page.locator("[inert]").count() == 0 and not last("paletteDrop")
    palette("Heading", "drop", 260, 240)
    draft = insert(draft, assert_insert("paletteDrop", "Heading", "body", {"x": 260, "y": 460}))
    assert marker not in draft and "<!-- keep Ω -->" in draft

    # Explicit Container mode keeps Flexbox insertion inside the author’s chosen section.
    nested = draft.replace("</body>", '<section id="row" style="position:absolute;left:30px;top:250px;'
                           'width:210px;height:70px;display:flex"><button>First</button></section></body>')
    render(nested)
    page.evaluate("webBenchDropOnPage(false)")
    palette("Button", "drop", 186, 282)
    nested = insert(nested, assert_insert("paletteDrop", "Button", "#row", None))
    render(nested)
    assert page.locator("#row > button").count() == 2

    # A positioned child inside a static wrapper moves in its actual containing block.
    # A previously selected ancestor must not take the child's drag.
    legacy = """<!doctype html><html><body style="margin:0">
    <main id="stage" style="position:relative;height:500px"><section id="panel" style="position:absolute;left:30px;top:40px;width:400px;height:300px">
    <div id="wrapper"><button id="control" style="position:absolute;left:70px;top:60px;width:100px;height:50px">Run</button></div></section></main></body></html>"""
    render(legacy)
    page.evaluate("webBenchTools('',false)")
    page.mouse.click(300, 240)
    assert last("select")["label"] == "section#panel"
    page.mouse.move(140, 126)
    page.mouse.down()
    page.mouse.move(206, 208, steps=5)
    page.mouse.up()
    moved = last("frame")
    assert moved and moved["id"] == int(page.locator("#control").get_attribute(marker)), moved
    assert moved["values"] == {"left": 136, "top": 142}, moved
    edited = call("run", legacy, moved["id"], {"kind": "frame", "values": moved["values"]})["text"]
    assert edited == legacy.replace("left:70px;top:60px", "left:136px;top:142px")
    render(edited)
    assert position("#control") == [136, 142]

    # The v0.15 iframe placeholder sits over an unrelated container. Hit its own
    # source parent even though Design shields its browsing context from input.
    frames = original.replace("</body>", '<div id="under" style="position:absolute;left:100px;top:80px;width:240px;height:160px"></div>'
                              '<section id="holder" style="position:absolute;left:100px;top:80px;width:0;height:0">'
                              '<iframe title="Scope" width="200" height="120"></iframe></section></body>')
    render(frames)
    page.evaluate("webBenchDropOnPage(false)")
    palette("Button", "hover", 142, 112)
    assert page.locator("#holder > button[inert]").count() == 1
    palette("Button", "drop", 142, 112)
    assert_insert("paletteDrop", "Button", "#holder", {"x": 42, "y": 32})
    page.evaluate("webBenchTools('Button',false)")
    page.mouse.click(142, 112)
    assert_insert("place", "Button", "#holder", {"x": 42, "y": 32})

    # Compare the saved file independently of the editor. The production Swift store retains BOM and CRLF.
    site = folder / "site"
    site.mkdir()
    entry = site / "index.html"
    entry.write_bytes(original.encode("utf-8-sig"))
    staged = folder / "draft.html"
    staged.write_bytes(nested.encode())
    subprocess.run([storage, site, "index.html", staged], check=True)
    subprocess.run([storage, site], check=True)
    assert entry.read_bytes() == nested.encode("utf-8-sig")
    page.goto(entry.as_uri())
    assert position("body > button") == [370, 320]
    assert position("body > h2,body > h1") == [260, 460]
    assert position(".shape-star") == [90, 80]
    page.close()
    engine.close()


if __name__ == "__main__":
    with TemporaryDirectory() as tmp, sync_playwright() as browsers:
        folder = Path(tmp)
        storage = folder / "storage"
        subprocess.run(["swiftc", root / "Sources/Project.swift", root / "Tests/StorageProbe.swift",
                        "-o", storage], check=True)
        for name in os.environ.get("WB_BROWSERS", "chromium").split(","):
            kind = getattr(browsers, name)
            exe = os.environ.get(name.upper())
            browser = kind.launch(executable_path=exe)
            subset = folder / name
            subset.mkdir()
            try:
                check(browser, storage, subset)
                print(f"{name} {browser.version}: placement, movement, nested layout, save and reopen passed")
            finally:
                browser.close()
