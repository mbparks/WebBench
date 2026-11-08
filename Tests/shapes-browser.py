"""Exercise palette, selection handles and Inspector paint, then save and reopen the HTML."""
import json
from io import BytesIO
from PIL import Image, ImageChops
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[1]
resources = root / "Resources"
base = """<!doctype html>
<html><head><meta charset="utf-8"><style>
body { margin:0; min-height:640px; position:relative; }
section { display:flex; position:absolute; left:340px; top:40px; width:280px; min-height:120px; }
</style></head><body data-design-canvas data-free-page><!-- keep Ω -->
<section id="row"></section></body></html>
""".replace("\n","\r\n")
marker = "data-wb-shapetest"

with TemporaryDirectory() as folder, sync_playwright() as pw:
    tmp = Path(folder)
    probe = tmp/"storage"
    subprocess.run(["swiftc",root/"Sources/Project.swift",root/"Tests/StorageProbe.swift","-o",probe],check=True)
    browser = pw.chromium.launch(executable_path=os.environ.get("CHROMIUM"),args=["--no-sandbox"])
    engine = browser.new_page()
    engine.add_script_tag(content=(resources/"source.js").read_text()+"\nwindow.engine=WebBench;")
    def call(method,*args):
        return engine.evaluate("([m,a]) => engine[m](...a)",[method,args])
    # Compare screenshots of the authored CSS against a path drawn from the palette descriptor.
    shapes=engine.evaluate("engine.catalog().filter(item=>item.shape)")
    for item in shapes:
        engine.evaluate("""({id,shape}) => {
          document.body.innerHTML='<main><div id="actual"></div><canvas></canvas></main>';
          document.querySelector('main').style.cssText='display:flex;align-items:flex-start;background:white';
          document.querySelector('#actual').innerHTML=engine.palette[id];
          const node=document.querySelector('#actual > div'), rect=node.getBoundingClientRect();
          const w=shape.width,h=shape.height;
          if(rect.width!==w || rect.height!==h) throw Error('Size of '+id);
          const canvas=document.querySelector('canvas'); canvas.width=w; canvas.height=h;
          const ctx=canvas.getContext('2d');
          ctx.fillStyle=getComputedStyle(node).backgroundColor;
          if(shape.points) {
            shape.points.forEach(([x,y],i)=>ctx[i?'lineTo':'moveTo'](x*w/100,y*h/100));
            ctx.closePath();
          } else if(shape.ellipse) ctx.ellipse(w/2,h/2,w/2,h/2,0,0,2*Math.PI);
          else ctx.roundRect(0,0,w,h,Math.min(shape.radius||0,w/2,h/2));
          ctx.fill();
        }""",item)
        def pixels(selector):
            return Image.open(BytesIO(engine.locator(selector).screenshot())).convert("RGB")
        actual, expected=pixels("#actual"),pixels("canvas")
        diff=ImageChops.difference(actual,expected)
        red,green,blue=diff.split()
        histogram=ImageChops.lighter(ImageChops.lighter(red,green),blue).histogram()
        assert sum(histogram[25:])<=actual.width*actual.height*.01,(item["title"],diff.getbbox())
    canvas = browser.new_page(viewport={"width":800,"height":640})
    code = "\n".join((resources/(name+".js")).read_text() for name in ["source","layout-drop","arrange","appearance","canvas"])
    def render(text):
        parsed=call("info",text,marker)
        assert not parsed["error"]
        canvas.goto("about:blank")
        canvas.set_content(parsed["html"])
        config={"tree":parsed["nodes"],"marker":marker,"token":"shapes"}
        canvas.add_script_tag(content="const WB="+json.dumps(config)+";window.messages=[];window.webkit={messageHandlers:{design:{postMessage:m=>messages.push(m)}}};"+code)
    def last(kind):
        return canvas.evaluate("k=>messages.filter(m=>m.kind===k).at(-1)",kind)
    def drag(text,part,x,y,parent,cancel=False):
        render(text)
        args=[part,x/800,y/640]
        canvas.evaluate("([i,x,y])=>webBenchPaletteDrag(i,'hover',x,y,true,false)",args)
        ghost=canvas.locator(parent+" > [inert]")
        assert ghost.count()==1
        assert ghost.evaluate("n=>getComputedStyle(n).clipPath.startsWith('polygon(')")
        if cancel:
            canvas.evaluate("([i,x,y])=>webBenchPaletteDrag(i,'cancel',x,y,true,false)",args)
            assert not last("paletteDrop") and not ghost.count()
            return text
        canvas.evaluate("([i,x,y])=>webBenchPaletteDrag(i,'drop',x,y,true,false)",args)
        drop=last("paletteDrop")
        assert drop and not ghost.count()
        return call("run",text,drop["id"],{"kind":"insert","item":part,"point":drop["point"],"before":drop["before"]})["text"]
    assert drag(base,"Heart",80,80,"body",cancel=True)==base
    draft=drag(base,"Star",80,80,"body")
    draft=drag(draft,"Right arrow",420,80,"#row")
    render(draft)
    star=canvas.locator(".shape-star")
    rect=star.bounding_box()
    assert rect=={"x":80,"y":80,"width":110,"height":104}
    canvas.mouse.click(135,132)
    picked=last("select")
    assert picked["id"]==int(star.get_attribute(marker)) and picked["canResize"]
    canvas.mouse.move(190,184)
    canvas.mouse.down()
    canvas.keyboard.down("Alt")
    canvas.mouse.move(250,223,steps=6)
    assert star.bounding_box()["width"]>150
    canvas.mouse.up()
    canvas.keyboard.up("Alt")
    frame=last("frame")
    assert frame["id"]==picked["id"] and frame["values"]["width"]==170 and frame["values"]["height"]==143,frame
    draft=call("run",draft,frame["id"],{"kind":"frame","values":frame["values"]})["text"]
    render(draft)
    canvas.evaluate("id=>webBenchPaint('element',id,'#2345bc',true)",frame["id"])
    paint=last("paint")
    draft=call("backgrounds",draft,paint["scope"],paint["parts"],paint["id"])["text"]
    assert marker not in draft
    original=base.encode("utf-8-sig")
    site=tmp/"site";site.mkdir()
    entry=site/"index.html";entry.write_bytes(original)
    staged=tmp/"staged.html";staged.write_bytes(draft.encode())
    subprocess.run([probe,site,"index.html",staged],check=True)
    subprocess.run([probe,site],check=True)
    published=tmp/"export"
    subprocess.run([probe,"--snapshot",site,"index.html",staged,published],check=True)
    assert entry.read_bytes()==(published/"index.html").read_bytes()==draft.encode("utf-8-sig")
    canvas.goto((published/"index.html").as_uri())
    assert canvas.locator("#row > .shape-right-arrow").count()==1
    assert star.bounding_box()=={"x":80,"y":80,"width":170,"height":143}
    assert star.evaluate("n=>getComputedStyle(n).backgroundColor")=="rgb(35, 69, 188)"
    assert canvas.evaluate("document.elementFromPoint(81,81)!==document.querySelector('.shape-star')")
    assert canvas.evaluate("document.elementFromPoint(165,151)===document.querySelector('.shape-star')")
    assert "<!-- keep Ω -->\r\n" in draft
    print(f"PASS {len(shapes)} silhouettes, drag/cancel/free and flex insertion, pointer resize, Inspector paint, BOM/CRLF save and standalone export. Chromium {browser.version}")
    browser.close()
