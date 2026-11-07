"""Exercise the Swift pixel tools and ICO writer with an independent PNG/ICO decoder."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
from PIL import Image

root = Path(__file__).resolve().parents[1]
with TemporaryDirectory(prefix="WebBenchIcon-") as t:
    work = Path(t)
    probe = work / "icons"
    subprocess.run(["swiftc", root / "Sources/Project.swift", root / "Sources/IconBitmap.swift",
                    root / "Tests/IconProbe.swift", "-o", probe], check=True)
    subprocess.run([probe, "paint", work], check=True)
    for n in (16, 32, 48):
        pixels = (work / f"{n}.rgba").read_bytes()
        Image.frombytes("RGBA", (n, n), pixels).save(work / f"{n}.png")
    with Image.open(work / "32.png") as img:
        assert img.getpixel((0, 0)) == (204, 51, 68, 255)
        assert img.getpixel((31, 0)) == (85, 153, 221, 128)
    subprocess.run([probe, "pack", work], check=True)
    with Image.open(work / "favicon.ico") as published:
        assert published.ico.sizes() == {(16, 16), (32, 32), (48, 48)}
        for n in (16, 32, 48):
            assert published.ico.getimage((n, n)).convert("RGBA").tobytes() == (work / f"{n}.rgba").read_bytes()
    print("PASS independent ICO decode: 16, 32 and 48 px; every pixel and alpha byte matched.")
