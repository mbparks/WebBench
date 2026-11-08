"""Run exported and reopened v0.12 interactions in a real browser against disposable files."""
import json
import os
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory
import wave

from playwright.sync_api import expect, sync_playwright

root = Path(__file__).resolve().parents[1]
base = """<!doctype html><html><head><meta charset="utf-8"><title>Interaction fixture</title>
<style>button{margin:3px}#far{margin-top:130vh}.active{color:navy}</style></head><body>
<form id="form"><label>Reading <input id="first" value="12"></label><label>Factor <input id="second" value="4"></label>
<input id="check" type="checkbox"><button id="submit">Submit</button></form>
<button id="calc">Divide</button><button id="copy">Copy</button><button id="state">Set controls</button>
<button id="restore">Restore</button><button id="hear">Play</button><button id="quiet">Pause</button>
<button id="jump">Jump</button><button id="probe">Check value</button>
<output id="out">Idle</output><p id="tail">Waiting</p><details id="more"><summary>More</summary>Details</details>
<audio id="player" src="tone.wav"></audio><p id="far">Destination</p></body></html>"""

def engine(name, method, *args):
    js = """const api=require(process.argv[1]); const [m,a]=JSON.parse(require('fs').readFileSync(0));
    process.stdout.write(JSON.stringify(api[m](...a)));"""
    return json.loads(subprocess.check_output(["node","-e",js,str(root/"Resources"/(name+".js"))],
                                             input=json.dumps([method,args]).encode()))

def make_page():
    variants = ["add", "subtract", "multiply", "divide", "empty", "filled", "equals", "contains", "less", "checked"]
    buttons = "".join(f'<button id="case-{name}" type="button">{name}</button>' for name in variants)
    html = base.replace('</body>', buttons + '</body>').replace("\n", "\r\n")
    ids = {n["attrs"]["id"]["value"]:n["id"] for n in engine("source","index",html)["nodes"] if "id" in n["attrs"]}
    def step(kind, target, value="", detail="", **extra):
        return dict(kind=kind, target=ids[target], value=value, detail=detail, **extra)
    def add(trigger, steps, event="click", condition=None, otherwise=None):
        nonlocal html
        model = dict(key=trigger+"-"+event.lower(), existing=False, trigger=ids[trigger], event=event,
                     preventDefault=True, steps=steps, condition=condition, otherwise=otherwise or [])
        html=engine("workflows","editWorkflow",html,model)["text"]
    add("calc", [step("calculate","out","divide"," V",input=ids["first"],operand=ids["second"],digits=2,invalid="Invalid reading"),
                 step("text","tail","Completed")])
    add("copy", [step("copyValue","out","[","]",input=ids["first"])])
    add("state", [step("enabled","second","disable"),step("checked","check","check"),
                  step("disclosure","more","open"),step("classChange","out","add","active"),step("focus","first")])
    add("restore",[step("resetForm","form"),step("enabled","second","enable"),step("disclosure","more","close"),
                   step("classChange","out","remove","active")])
    add("hear",[step("mediaControl","player","play")])
    add("quiet",[step("mediaControl","player","pause")])
    add("jump",[step("scroll","far")])
    add("form",[step("text","out","Submitted")],"submit")
    for event,label in [("enterKey","Enter"),("escapeKey","Escape"),("dblclick","Double"),("focus","Focused"),("blur","Blurred"),
                        ("pointerenter","Over"),("pointerleave","Out")]:
        add("probe",[step("text","tail",label)],event)
    add("probe",[step("text","out","Above limit")],
        condition=dict(source=ids["first"],test="greater",value="10"),otherwise=[step("text","out","Other")])
    for op in ["add","subtract","multiply","divide"]:
        add("case-"+op,[step("calculate","out",op,"",input=ids["first"],constant="-2",digits=-1,invalid="Invalid")])
    for predicate, reference in [("empty",""),("filled",""),("equals","5"),("contains","5"),("less","10"),("checked","")]:
        add("case-"+predicate,[step("text","out","Yes")],condition=dict(
            source=ids["check" if predicate == "checked" else "first"],test=predicate,value=reference),
            otherwise=[step("text","out","No")])
    return html

with TemporaryDirectory() as folder, sync_playwright() as pw:
    tmp = Path(folder)
    site = tmp/"site"
    site.mkdir()
    html = make_page()
    (site/"index.html").write_bytes(b"\xef\xbb\xbf"+base.encode())
    staged=tmp/"edited"
    staged.write_bytes(html.encode())
    with wave.open(str(site/"tone.wav"),"wb") as sound:
        sound.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
        sound.writeframes(b"\0\0" * 8000 * 5)
    store=tmp/"store"
    subprocess.run(["swiftc",root/"Sources/Project.swift",root/"Tests/StorageProbe.swift","-o",store],check=True)
    subprocess.run([store,site,"index.html",staged],check=True)
    subprocess.run([store,site],check=True)
    exported=tmp/"export"
    subprocess.run([store,"--snapshot",site,"index.html",staged,exported],check=True)
    assert (exported/"index.html").read_bytes()==(site/"index.html").read_bytes()==b"\xef\xbb\xbf"+html.encode()
    for f in engine("workflows","workflows",html)["flows"]:
        assert engine("workflows","editWorkflow",html,{**f,"existing":True})["text"]==html

    browser=pw.chromium.launch(executable_path=os.environ.get("CHROMIUM") or shutil.which("chromium"),args=["--no-sandbox"])
    page=browser.new_page(viewport={"width":900,"height":620},reduced_motion="reduce")
    page.set_default_timeout(5000)
    errors=[]
    page.on("pageerror",lambda e: errors.append(str(e)))
    page.goto((exported/"index.html").as_uri())
    at=lambda name: page.locator("#"+name)
    at("calc").click()
    expect(at("out")).to_have_text("3.00 V")
    expect(at("tail")).to_have_text("Completed")
    for x,y in [("","1"),("0","0"),("1","0"),("1e400","2"),("12 V","2")]:
        at("first").fill(x)
        at("second").fill(y)
        page.evaluate("document.getElementById('tail').textContent='Waiting'")
        at("calc").click()
        expect(at("out")).to_have_text("Invalid reading")
        expect(at("tail")).to_have_text("Waiting")
    at("first").fill("0")
    at("second").fill("2")
    at("calc").click()
    expect(at("out")).to_have_text("0.00 V")
    at("first").fill("<strong>literal</strong>")
    at("copy").click()
    expect(at("out")).to_have_text("[<strong>literal</strong>]")
    assert not at("out").locator("strong").count()
    at("state").click()
    expect(at("check")).to_be_checked()
    expect(at("second")).to_be_disabled()
    expect(at("more")).to_have_attribute("open","")
    expect(at("out")).to_have_class("active")
    expect(at("first")).to_be_focused()
    at("restore").click()
    expect(at("check")).not_to_be_checked()
    expect(at("second")).to_be_enabled()
    expect(at("first")).to_have_value("12")
    expect(at("more")).not_to_have_attribute("open","")
    expect(at("out")).not_to_have_class("active")
    at("submit").click()
    expect(at("out")).to_have_text("Submitted")
    at("hear").click()
    page.wait_for_function("document.querySelector('audio').currentTime > 0")
    at("quiet").click()
    assert at("player").evaluate("e => e.paused")
    assert at("far").evaluate("e => e.getBoundingClientRect().top > innerHeight")
    at("jump").click()
    page.wait_for_function("scrollY > 0 && document.getElementById('far').getBoundingClientRect().bottom <= innerHeight")
    # Event handlers share one trigger. Isolate real focus, pointer and keyboard events.
    at("probe").hover()
    expect(at("tail")).to_have_text("Over")
    at("copy").hover()
    expect(at("tail")).to_have_text("Out")
    at("probe").focus()
    expect(at("tail")).to_have_text("Focused")
    at("probe").press("Enter")
    expect(at("tail")).to_have_text("Enter")
    at("probe").press("Escape")
    expect(at("tail")).to_have_text("Escape")
    at("probe").dblclick()
    expect(at("tail")).to_have_text("Double")
    at("first").focus()
    expect(at("tail")).to_have_text("Blurred")
    for value, expected in [("12","Above limit"),("10","Other"),("","Other"),("1e500","Other")]:
        at("first").fill(value)
        at("probe").click()
        expect(at("out")).to_have_text(expected)
    at("first").fill("5")
    for op, expected in [("add","3"),("subtract","7"),("multiply","-10"),("divide","-2.5")]:
        at("case-"+op).click()
        expect(at("out")).to_have_text(expected)
    for predicate, value, expected in [("empty","","Yes"),("filled","  ","No"),("equals","5","Yes"),
                                        ("contains","25","Yes"),("less","-1","Yes"),("less","infinity","No")]:
        at("first").fill(value)
        at("case-"+predicate).click()
        expect(at("out")).to_have_text(expected)
    at("case-checked").click()
    expect(at("out")).to_have_text("No")
    at("check").check()
    at("case-checked").click()
    expect(at("out")).to_have_text("Yes")
    print("PASS four arithmetic operations with a fixed operand and all eight condition types, including the power meter validation below.")
    print("PASS exported v0.12 actions, both branches, all eight new events, audio play/pause, scroll and focus, invalid math recovery and live value copying.")

    page.goto((root/"Fixtures/Power-meter.html").as_uri())
    at("test").click()
    expect(at("power")).to_have_text("3.00 W")
    at("volts").fill("")
    at("test").click()
    expect(at("power")).to_have_class("warning")
    expect(at("power")).to_have_text("Enter a voltage and a current.")
    at("volts").fill("-5")
    at("test").click()
    expect(at("power")).to_have_text("-1.25 W")
    expect(at("power")).not_to_have_class("warning")
    assert not errors,errors
    assert (exported/"index.html").read_bytes()==b"\xef\xbb\xbf"+html.encode()
    print("PASS standalone DC power meter, invalid form, recovery, byte-identical workflow reopen and isolated source bytes.")
    browser.close()
