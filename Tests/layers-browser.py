"""Exercise actual rendered drop geometry, the Swift Layers planner, source patcher and saved page."""
import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory
from playwright.sync_api import sync_playwright

root=Path(__file__).resolve().parents[1]
res=root/"Resources"
marker="data-wb-check"
original="""<!doctype html><html><head><style>
*{box-sizing:border-box}body{position:relative;margin:0;min-height:680px}
#panel{position:absolute;left:40px;top:56px;width:580px;padding:16px;border:2px solid}
#inside{display:flex;gap:10px;min-height:80px;padding:15px}#empty{min-height:54px;padding:8px}
#grid{display:grid;grid-template-columns:1fr 1fr;min-height:84px}p{margin:0}
</style></head><body data-free-page data-design-canvas><section id="panel"><h2>Panel</h2>
<div id="inside"><p id="first">First</p><p id="last">Last</p></div>
<div id="empty"></div><div id="grid"></div></section><!-- keep -->
<a href="#panel" id="jump" style="position:absolute;left:40px;top:490px">Jump</a></body></html>"""
def swift(output,*files):
    subprocess.run(["swiftc",*[str(root/f) for f in files],"-o",str(output)],check=True)
with TemporaryDirectory() as folder, sync_playwright() as pw:
    tmp=Path(folder); site=tmp/"Site";site.mkdir();page_file=site/"index.html"
    initial=original.replace("\n","\r\n"); page_file.write_bytes(b"\xef\xbb\xbf"+initial.encode())
    planner=tmp/"layer-plan";storage=tmp/"storage"
    swift(planner,"Sources/LayerOrder.swift","Sources/Project.swift","Tests/LayerProbe.swift")
    swift(storage,"Sources/Project.swift","Tests/StorageProbe.swift")
    browser=pw.chromium.launch(executable_path=os.environ.get("CHROMIUM") or shutil.which("chromium"),args=["--no-sandbox"])
    page=browser.new_page(viewport={"width":900,"height":700})
    page.goto("about:blank");page.add_script_tag(content=(res/"source.js").read_text()+"\nwindow.engine=WebBench;")
    draft=initial
    bridges="\n".join((res/(n+".js")).read_text() for n in ["source","appearance","layout-drop","arrange","canvas"])
    canvas=browser.new_page(viewport={"width":900,"height":700})
    def call(method,*args):
        return page.evaluate("([m,args])=>window.engine[m](...args)",[method,args])
    def render():
        info=call("info",draft,marker);assert info["error"]==""
        canvas.goto("about:blank");canvas.set_content(info["html"])
        config={"tree":info["nodes"],"token":"browser","marker":marker}
        canvas.add_script_tag(content="const WB="+json.dumps(config)+";window.events=[];window.webkit={messageHandlers:{design:{postMessage:m=>events.push(m)}}};"+bridges)
        return info["nodes"]
    def node(rows,label):return next(n["id"] for n in rows if n["label"]==label)
    def coords(tag):
        r=canvas.locator(tag).bounding_box();return [r["x"]+r["width"]/2,r["y"]+r["height"]/2]
    def place(item,target,parent,click=False):
        global draft
        rows=render(); x,y=coords(target)
        if click:
            canvas.evaluate("item=>webBenchTools(item,false)",item)
            canvas.mouse.click(x,y)
        else:
            args=[item,x/900,y/700]
            canvas.evaluate("([i,x,y])=>webBenchPaletteDrag(i,'hover',x,y,false,false)",args)
            assert canvas.locator(parent+" > [inert]").count()==1
            canvas.evaluate("([i,x,y])=>webBenchPaletteDrag(i,'drop',x,y,false,false)",args)
        m=canvas.evaluate("events.filter(e=>['place','paletteDrop'].includes(e.kind)).at(-1)")
        assert m and m["id"]==int(canvas.locator(parent).get_attribute(marker)),(target,m)
        assert canvas.locator("[inert]").count()==0
        draft=call("run",draft,m["id"],{"kind":"insert","item":item,"before":m["before"],"point":m["point"]})["text"]
    place("Button","#first","#inside")
    place("Details","#empty","#empty",click=True)
    place("Card","#grid","#grid")
    rows=render()
    assert canvas.locator("#inside > button").count()==1
    assert canvas.locator("#empty > details > summary").inner_text()=="Details"
    assert canvas.locator("#grid > article").count()==1
    print("PASS real browser palette hover/drop and armed click into nested Flex, Grid and empty div on a free canvas")
    for zone,target in [("inside","div#empty"),("before","p#first"),("after","p#last")]:
        rows=render()
        r={"nodes":rows,"rules":call("parentRules"),"child":node(rows,"button"),"target":node(rows,target),"zone":zone}
        dest=json.loads(subprocess.check_output([planner],input=json.dumps(r).encode()))
        draft=call("run",draft,dest["parent"],dest["op"])["text"]
        render()
        expected={"inside":"#empty > button:last-child","before":"#inside > button:first-child","after":"#inside > button:last-child"}[zone]
        assert canvas.locator(expected).count()==1
    rows=render()
    # Confirm all palette entries survive the browser's HTML parser under a compatible parent.
    assert page.evaluate("""()=>engine.catalog().every(item=>{
      const p=(engine.parentRules()[item.tag]||engine.parentRules()['*'])[0];
      const parent=document.createElement(p);parent.innerHTML=engine.palette[item.id];
      return parent.children.length===1 && parent.firstElementChild.localName===item.tag;
    })""")
    assert "<!-- keep -->" in draft and "data-wb-check" not in draft and 'href="#panel"' in draft
    staged=tmp/"draft.html";staged.write_bytes(draft.encode())
    subprocess.run([storage,site,"index.html",staged],check=True)
    subprocess.run([storage,site],check=True)
    assert page_file.read_bytes()==b"\xef\xbb\xbf"+draft.encode()
    published=tmp/"Published"
    subprocess.run([storage,"--snapshot",site,"index.html",staged,published],check=True)
    canvas.goto((published/"index.html").as_uri())
    assert canvas.locator("#inside > button:last-child").count()==1
    canvas.locator("#jump").click();assert canvas.url.endswith("#panel")
    print("PASS Swift Layers before/inside/after → production source patches → BOM/CRLF save, export, reopen and working hyperlink")
    print("PASS browser parsed all",len(call("catalog")),"Insert templates. Chromium",browser.version)
    browser.close()
