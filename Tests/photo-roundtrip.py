"""End-to-end portable photo test. Pillow supplies the codecs on Linux; macOS uses ImageIO."""
import base64
import hashlib
import io
import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from PIL import Image

root = Path(__file__).resolve().parents[1]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

with TemporaryDirectory(prefix="WebBenchPhoto-") as temp:
    work = Path(temp)
    site = work / "Site"
    site.mkdir()
    probe = work / "photo"
    subprocess.run(["swiftc", "-O", root / "Sources/Project.swift", root / "Sources/PhotoRecipe.swift",
                    root / "Tests/PhotoProbe.swift", "-o", probe], check=True)
    embedded = re.search(r'data:image/jpeg;base64,([^"]+)', (root / "Resources/studio.html").read_text())[1]
    original = site / "field.tiff"
    with Image.open(io.BytesIO(base64.b64decode(embedded))) as camera:
        camera.convert("RGB").resize((3200,2400)).save(original, compression="raw")
    original_hash = sha(original)
    assert original.stat().st_size > 12*1024*1024
    x,y,w,h,out_w,out_h = map(int, subprocess.check_output([probe,"geometry",work]).split())
    with Image.open(original) as photo:
        cropped = photo.crop((x,y,x+w,y+h)).resize((out_h,out_w), Image.Resampling.LANCZOS).convert("RGBA")
    (work / "input.rgba").write_bytes(cropped.tobytes())
    subprocess.run([probe,"pixels",work], check=True)
    edited = Image.frombytes("RGBA",(out_w,out_h),(work / "result.rgba").read_bytes())
    edited.save(work / "edited.png")
    assert edited.size == (360,640)
    assert edited.getpixel((180,590)) == (36,92,73,255)
    for px,py in [(78,100), (170,200), (275,390), (120,560)]:
        r,g,b,_ = cropped.getpixel((py,px))  # Clockwise rotation followed by horizontal mirror.
        value = round(.2126*r+.7152*g+.0722*b)
        assert edited.getpixel((px,py)) == (value,value,value,255)
    html = b"\xef\xbb\xbf<!-- retain -->\r\n<img alt='Field recorder' src='field.tiff'>\r\n"
    (site / "index.html").write_bytes(html)
    js = """const fs=require('node:fs'), engine=require(process.argv[1]);
      const source=fs.readFileSync(process.argv[2],'utf8').replace(/^\\uFEFF/,'');
      const id=engine.index(source).nodes.find(n=>n.tag==='img').id;
      fs.writeFileSync(process.argv[3],engine.run(source,id,{kind:'attr',key:'src',value:'assets/field-edited.png'}).text);"""
    subprocess.run(["node","-e",js,root/"Resources/source.js",site/"index.html",work/"patched.html"],check=True)
    subprocess.run([probe,"publish",work],check=True)
    for folder in [site,work/"Published"]:
        assert sha(folder/"field.tiff")==original_hash
        assert (folder/"index.html").read_bytes()==html.replace(b"field.tiff",b"assets/field-edited.png")
        with Image.open(folder/"assets/field-edited.png") as saved:
            assert saved.tobytes()==edited.tobytes()
    print(f"PASS {original.stat().st_size:,}-byte TIFF → cropped, rotated, mirrored, monochrome instant-print PNG "
          f"({out_w} × {out_h}, {(work/'edited.png').stat().st_size:,} bytes).")
    print("PASS edited src only, BOM and CRLF retained, original SHA-256 matched after save, export and reopen.")
