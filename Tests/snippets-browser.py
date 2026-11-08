"""Check editable iframe geometry and run/export behavior with two disposable loopback origins."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from threading import Thread
from playwright.sync_api import sync_playwright, expect

root=Path(__file__).resolve().parents[1]
res=root/"Resources"
fixture=root/"Fixtures/Snippets-and-embeds.html"
marker="data-wb-snippet-check"

def server(routes,requests):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            data=routes.get(self.path.split("?",1)[0])
            if data is None:
                self.send_error(404)
                return
            body,policy=data
            self.send_response(200)
            self.send_header("Content-Type","text/html; charset=utf-8")
            if policy:
                self.send_header("Content-Security-Policy",policy)
            self.end_headers()
            self.wfile.write(body.encode())
        def log_message(self,*args):
            pass
    http=ThreadingHTTPServer(("127.0.0.1",0),Handler)
    Thread(target=http.serve_forever,daemon=True).start()
    return http

with TemporaryDirectory() as folder, sync_playwright() as pw:
    tmp=Path(folder); site=tmp/"site"; site.mkdir()
    browser=pw.chromium.launch(executable_path=os.environ.get("CHROMIUM"),args=["--no-sandbox"])
    engine=browser.new_page()
    engine.add_script_tag(content=(res/"source.js").read_text()+"\nwindow.engine=WebBench")
    def call(method,*args):
        return engine.evaluate("([m,a])=>engine[m](...a)",[method,args])

    local_requests,external_requests=[],[]
    routes={}
    child='<html><body><button onclick="this.textContent=\'Received\'">Pulse</button></body></html>'
    local=server(routes,local_requests)
    provider=server({"/player":(child,"")},external_requests)
    origin=f"http://127.0.0.1:{local.server_port}"
    url=f"http://127.0.0.1:{provider.server_port}/player"
    try:
        original=fixture.read_text().replace("\n","\r\n")
        body=next(n["id"] for n in call("index",original)["nodes"] if n["tag"]=="body")
        def add(text,target,title):
            return call("run",text,body,dict(kind="snippet",type="iframe",text="",url=target,title=title,fields=True))["text"]
        source=add(add(original,"parts/child.html","Local meter"),url,"External meter")
        (site/"parts").mkdir()
        (site/"parts/child.html").write_text(child)
        (site/"index.html").write_bytes(original.encode("utf-8-sig"))
        stage=tmp/"edited.html";stage.write_bytes(source.encode())
        storage=tmp/"probe"
        subprocess.run(["swiftc",root/"Sources/Project.swift",root/"Tests/StorageProbe.swift","-o",storage],check=True)
        subprocess.run([storage,site,"index.html",stage],check=True)
        subprocess.run([storage,site],check=True)
        export=tmp/"published"
        subprocess.run([storage,"--snapshot",site,"index.html",stage,export],check=True)
        data=(export/"index.html").read_bytes()
        assert data==(site/"index.html").read_bytes()==source.encode("utf-8-sig")
        parsed=call("info",source,marker)
        assert not parsed["error"] and marker not in source
        design_frames=[n for n in call("index",parsed["html"])["nodes"] if n["tag"]=="iframe"]
        assert all("src" not in n["attrs"] for n in design_frames)
        assert design_frames[-1]["attrs"][marker+"-src"]["value"]==url
        # Mirror the app's Design / Run policies with HTTP loopback standing in for webbench://project.
        common="; style-src 'self' 'unsafe-inline'; img-src 'self' data:; object-src 'none'; connect-src 'self'; base-uri 'self'; form-action 'none'"
        routes.update({"/design":(parsed["html"],"default-src 'none'; script-src 'none'; frame-src about: 'self'"+common),
                       "/run":(source,"default-src 'none'; script-src 'self' 'unsafe-inline'; frame-src about: 'self'"+common),
                       "/parts/child.html":(child,"")})
        page=browser.new_page(viewport={"width":980,"height":840})
        page.goto(origin+"/design")
        scripts="\n".join((res/(name+".js")).read_text() for name in ["source","appearance","layout-drop","arrange","canvas"])
        config=dict(marker=marker,token="fixture",tree=parsed["nodes"])
        page.evaluate("() => { const WB="+json.dumps(config)+";window.messages=[];window.webkit={messageHandlers:{design:{postMessage:m=>messages.push(m)}}};"+scripts+"\n}")
        frames=page.locator("iframe")
        assert frames.count()==3
        expect(page.frame_locator("iframe").first.locator("body")).to_contain_text("Iframe embed")
        page.locator("#send").click()
        expect(page.locator("#count")).to_have_text("0")
        frame=frames.first
        frame.scroll_into_view_if_needed()
        rect=frame.bounding_box()
        x,y=rect["x"]+rect["width"]/2,rect["y"]+rect["height"]/2
        frame_id=int(frame.get_attribute(marker))
        page.mouse.click(x,y)
        assert page.evaluate("messages.filter(m=>m.kind==='select').at(-1).id")==frame_id
        page.mouse.dblclick(x,y)
        assert page.evaluate("messages.filter(m=>m.kind==='editSnippet').at(-1).id")==frame_id
        # Resize from the lower-right grip, including when it lies over the inactive browsing context.
        right,bottom=rect["x"]+rect["width"],rect["y"]+rect["height"]
        page.mouse.move(right,bottom);page.mouse.down();page.mouse.move(right+32,bottom+16,steps=5);page.mouse.up()
        frame_event=page.evaluate("messages.filter(m=>m.kind==='frame').at(-1)")
        assert frame_event and frame_event["id"]==frame_id,frame_event
        assert not external_requests and "/parts/child.html" not in local_requests
        page.goto(origin+"/run")
        page.locator("#send").click()
        expect(page.locator("#count")).to_have_text("1")
        expect(page.locator("pre code")).to_contain_text("<button")
        assert not page.locator("pre button").count()
        slider=page.frame_locator('iframe[title="Signal level control"]').locator("input")
        slider.focus();slider.press("ArrowRight")
        expect(page.frame_locator('iframe[title="Signal level control"]').locator("output")).to_have_text("51%")
        button=page.frame_locator('iframe[title="Local meter"]').get_by_role("button")
        button.click();expect(button).to_have_text("Received")
        assert not external_requests
        page.goto((export/"index.html").as_uri())
        external=page.frame_locator('iframe[title="External meter"]').get_by_role("button")
        external.click();expect(external).to_have_text("Received")
        assert external_requests.count("/player")==1
        expect(page.frame_locator('iframe[title="Local meter"]').get_by_role("button")).to_have_text("Pulse")
        assert (export/"index.html").read_bytes()==data
        print("PASS literal code, custom JavaScript, Design frame selection/double-click/resize, offline inline and local frames, and exported cross-origin embed. Chromium",browser.version)
    finally:
        local.shutdown();provider.shutdown();browser.close()
