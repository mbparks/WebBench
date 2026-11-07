"""Optional integration run. Requires Swift, Node, Python Playwright and Chromium."""
import contextlib
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Resources"
MARKER = "data-wb-fixture"
def engine(method, *args):
    code = """const w=require(process.argv[1]);let [method,args]=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(JSON.stringify(w[method](...args)))"""
    return json.loads(subprocess.check_output(["node","-e",code,str(RES/"source.js")],input=json.dumps([method,args]).encode()))
def hashes(directory):
    return {str(f.relative_to(directory)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(directory.rglob("*")) if f.is_file()}
class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control","no-store")
        super().end_headers()
    def log_message(self,*args):pass
@contextlib.contextmanager
def serve(directory):
    server=http.server.ThreadingHTTPServer(("127.0.0.1",0),functools.partial(Handler,directory=str(directory)))
    t=threading.Thread(target=server.serve_forever,daemon=True);t.start()
    try:yield "http://127.0.0.1:"+str(server.server_address[1])
    finally:server.shutdown();server.server_close();t.join()
def main():
    with tempfile.TemporaryDirectory() as tmp:
        work=Path(tmp);root=work/"fixtures";shutil.copytree(ROOT/"Fixtures",root)
        site=root/"Site";single=root/"Field-Instrument.html";probe=work/"storage-probe"
        subprocess.run(["swiftc",str(ROOT/"Sources/Project.swift"),str(ROOT/"Tests/StorageProbe.swift"),"-o",str(probe)],check=True)
        original=hashes(root)
        for f in [site,single]:subprocess.run([probe,f],check=True)
        assert hashes(root)==original
        print("PASS SHA-256 open/save/reopen",json.dumps(original,sort_keys=True),flush=True)
        def commit(file, **edits):
            cmd=[probe,file]
            for i,(path,text) in enumerate(edits.items()):
                staged=work/("staged"+str(i));staged.write_bytes(text.encode());cmd+=[path,staged]
            subprocess.run(cmd,check=True)
        with serve(root) as base,sync_playwright() as automation:
            browser=automation.chromium.launch(executable_path=os.environ.get("CHROMIUM") or shutil.which("chromium"),args=["--no-sandbox"])
            print("Browser",browser.version,flush=True)
            p=browser.new_page(viewport={"width":960,"height":760})
            page_url=base+"/Site/index.html"; html=(site/"index.html").read_text(); css=(site/"css/bench.css").read_text()
            def design(text):
                ix=engine("info",text,MARKER);assert not ix["error"],ix["error"]
                p.unroute_all()
                p.route(page_url,lambda r:r.fulfill(body=ix["html"],content_type="text/html; charset=utf-8",headers={"Content-Security-Policy":"script-src 'none'"}))
                p.goto(page_url)
                p.evaluate("window.events=[];window.webkit={messageHandlers:{design:{postMessage:m=>events.push(m)}}}")
                conf={"tree":ix["nodes"],"marker":MARKER,"token":"fixture"}
                modules = ("source.js", "layout-drop.js", "arrange.js", "canvas.js")
                bridge = "\n".join((RES / name).read_text() for name in modules)
                p.evaluate("()=>{const WB=" + json.dumps(conf) + ";\n" + bridge + "}")
                assert p.evaluate("events.at(-1).kind")=="ready"
                return ix["nodes"]
            def event(kind):
                return p.evaluate("kind=>events.filter(e=>e.kind===kind).at(-1)",kind)
            def run():
                p.unroute_all();p.goto(page_url)
            def drop(selector,item):
                p.locator(selector).evaluate("""(e,item)=>{const r=e.getBoundingClientRect(),d=new DataTransfer();d.setData('text/plain','WebBench:'+item);
                 for(const t of ['dragover','drop'])e.dispatchEvent(new DragEvent(t,{bubbles:true,cancelable:true,clientX:r.right-8,clientY:r.top+r.height/2,dataTransfer:d}));}""",item)
                return event("drop")
            design(html);p.keyboard.type("ODIN");expect(p.locator("#signal")).to_have_text("Standby")
            d=drop(".actions","Button")
            result=engine("run",html,d["id"],{"kind":"insert","item":d["item"],"before":d["before"]}); inserted=result["text"]
            assert inserted==html.replace("</button></div>","</button><button type=\"button\">Button</button></div>")
            nodes=design(inserted);p.get_by_role("button",name="Button",exact=True).click()
            sel=event("select");assert sel["tag"]=="button" if "tag" in sel else sel["label"]=="button"
            mobile=engine("style",inserted,sel["id"],{"prop":"margin-top","value":"19px","mobile":True,"width":600,"external":True,"css":css})
            commit(site,**{"index.html":mobile["text"],"css/bench.css":mobile["css"]})
            run();btn=p.get_by_role("button",name="Button",exact=True)
            expect(btn).not_to_have_css("margin-top","19px")
            p.set_viewport_size({"width":380,"height":760});expect(btn).to_have_css("margin-top","19px")
            design(mobile["text"]);p.locator(".control").first.click();sel=event("select");rule=sel["rules"][sel["winner"]]
            assert rule["source"].endswith("/css/bench.css") and rule["count"]==2 and "600px" in rule["media"]
            assert rule["value"]=="2px"
            print("PASS flex drop, source patch, desktop/mobile output, winning declaration and affected count",flush=True)
            p.set_viewport_size({"width":960,"height":760})
            nodes=design(mobile["text"]);meter=next(n["id"] for n in nodes if n["label"]=="div#meter")
            p.evaluate("(id)=>webBenchSelect(id,'left')",meter)
            assert event("select")["canMove"]
            rect=p.locator("#meter").bounding_box();x=rect["x"]+rect["width"]/2;y=rect["y"]+rect["height"]/2
            p.keyboard.down("Alt");p.mouse.move(x,y);p.mouse.down();p.mouse.move(x+35,y+18);p.mouse.up();p.keyboard.up("Alt")
            m=event("frame"); moved=engine("run",mobile["text"],m["id"],{"kind":"frame","values":m["values"]})["text"]
            assert moved==mobile["text"].replace("left: 24px; top: 32px","left: 59px; top: 50px")
            commit(site,**{"index.html":moved});run()
            expect(p.locator("#meter")).to_have_css("left","59px");p.keyboard.type("ODIN");expect(p.locator("#signal strong")).to_have_text("⚡")
            r=p.locator("#meter").bounding_box();p.mouse.move(r["x"]+4,r["y"]+4);p.mouse.down();p.mouse.move(r["x"]+16,r["y"]+8);p.mouse.up()
            assert p.url==page_url, "A pointer drag triggered the nested link"
            p.evaluate("""()=>{const m=document.querySelector('#meter');m.dispatchEvent(new PointerEvent('pointerdown',{button:0,clientX:3,clientY:4}));window.dispatchEvent(new PointerEvent('pointermove',{buttons:1,clientX:13,clientY:14}));window.dispatchEvent(new PointerEvent('pointerup'));}""")
            assert p.locator("#meter").evaluate("e=>parseInt(e.style.left)")>=69
            p.locator("#meter a").click();expect(p.get_by_role("heading")).to_have_text("Meter notes")
            assert (site/"js/bench.js").read_bytes()==(ROOT/"Fixtures/Site/js/bench.js").read_bytes()
            print("PASS positioned drag, saved coordinates, original drag script, local link and ODIN",flush=True)
            # Use the palette and handler generator to build a separate standalone conversion tool.
            app=(RES/"blank.html").read_text()
            def find(text,label):return next(n["id"] for n in engine("info",text,"")["nodes"] if n["label"]==label)
            for item,label,id_value in [("Number input","input","celsius"),("Button","button","convert"),("Output","output","result")]:
                app=engine("run",app,find(app,"section.layout"),{"kind":"insert","item":item})["text"]
                app=engine("run",app,find(app,label),{"kind":"attr","key":"id","value":id_value})["text"]
            handler=engine("run",app,find(app,"button#convert"),{"kind":"handler"})
            app=handler["text"].replace("// Write the click action here.","document.getElementById('result').textContent = String(document.getElementById('celsius').valueAsNumber * 9 / 5 + 32);")
            commit(single,**{single.name:app});p.goto(single.as_uri());p.locator("#celsius").fill("25");p.locator("#convert").click();expect(p.locator("output")).to_have_text("77")
            p.goto((RES/"instrument.html").as_uri());p.get_by_role("button").click();expect(p.locator("output")).to_have_text("2.500 V")
            p.locator("#r1").fill("0");p.locator("#r2").fill("0");p.get_by_role("button").click();expect(p.locator("output")).to_have_text("Check inputs")
            print("PASS saved standalone instrument opened independently over file://, 25 °C → 77 °F; divider 2.500 V and invalid inputs",flush=True)
            browser.close()
if __name__=="__main__":main()
