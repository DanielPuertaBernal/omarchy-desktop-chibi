#!/usr/bin/env python3
"""Draw the placeholder sprite strips for characters/kumo.

These are simple flat figures, only good enough to see every state working
until the real art (see docs/gemini-sprite-prompts.md) replaces them. Each
frame is drawn as SVG at 2x (360x800), rendered with ImageMagick, scaled down
to 180x400 and joined into a horizontal strip.

Usage: python3 tools/make-placeholders.py [output-dir]   (needs `magick`)
"""

import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

W, H = 360, 800           # drawing canvas (2x)
OUT_W, OUT_H = 180, 400   # frame size in the strip

# Tokyo Night-friendly palette; the real character sheet can change it.
INK = "#16161e"
SKIN = "#f2d3c4"
HAIR = "#3b4261"
HAIR_HI = "#7aa2f7"
JACKET = "#7aa2f7"
TOP = "#c0caf5"
SKIRT = "#414868"
SHOES = "#bb9af7"


def pose(**kw):
    base = dict(bob=0, lean=0, armL=-8, armR=8, legL=-3, legR=3, eyes="open", mouth="smile",
                extra=[], sit=False, head=0, legLen=1.0, phase=0)
    base.update(kw)
    return base


# frames per animation: (fps-ish frameMs, sideways, [poses])
def animations():
    a = {}
    a["idle"] = (240, False, [pose(bob=b, armL=-8 - b, armR=8 + b) for b in (0, 2, 4, 4, 2, 0)])
    a["walk"] = (140, True, [pose(bob=abs(s) * -0.2, lean=4, legL=-s, legR=s, armL=s * 0.8, armR=-s * 0.8)
                             for s in (25, 12, 0, -12, -25, -12)])
    a["run"] = (80, True, [pose(bob=-abs(s) * 0.4, lean=12, legL=-s, legR=s, armL=s * 1.2 + 20, armR=-s * 1.2 + 20,
                                mouth="open") for s in (40, 20, -5, -40, -20, 5)])
    a["sit"] = (900, False, [pose(sit=True, armL=-20, armR=20), pose(sit=True, armL=-20, armR=20, eyes="closed")])
    a["sleep"] = (1000, False, [pose(sit=True, armL=-15, armR=15, eyes="closed", mouth="o", head=12, extra=["zz"])])
    a["hang"] = (280, False, [pose(bob=0, armL=-172, armR=172, legL=-6 + d, legR=6 + d, mouth="o") for d in (0, 6)])
    a["fall"] = (120, False, [pose(armL=-140 + d, armR=140 - d, legL=-25, legR=25, mouth="open", eyes="x")
                              for d in (0, 20, 0, -20)])
    a["climb"] = (200, True, [pose(lean=-6, armL=-170 + d, armR=170 - d, legL=-15 + d, legR=15 - d, phase=i)
                              for i, d in enumerate((0, 15, 0, -15))])
    a["think"] = (450, False, [pose(armR=150, head=6, extra=["dots%d" % i], mouth="flat") for i in (1, 2, 3, 3)])
    a["work"] = (110, False, [pose(sit=True, armL=-30 + d, armR=30 - d, extra=["laptop"], mouth="flat")
                              for d in (0, 8, 0, -8)])
    a["wave"] = (160, False, [pose(armR=a_, armL=-8, extra=["!"], mouth="open") for a_ in (150, 175, 150, 125)])
    a["celebrate"] = (130, False, [pose(bob=b, armL=-160, armR=160, mouth="open", extra=["spark"]) for b in (0, -20, -35, -20)])
    a["bow"] = (300, False, [pose(bob=b, head=h_, eyes="closed", extra=["heart"] if b else []) for b, h_ in ((0, 0), (20, 18), (35, 25), (20, 18))])
    a["oops"] = (130, False, [pose(lean=l, armL=-70, armR=70, eyes="x", mouth="o", extra=["sweat"]) for l in (8, 16, 10, 4)])
    a["talk"] = (160, False, [pose(mouth=m, armR=20) for m in ("open", "smile", "o", "smile")])
    a["dance"] = (170, False, [pose(lean=l, armL=-150 if i % 2 else -40, armR=40 if i % 2 else 150, bob=-abs(l))
                               for i, l in enumerate((6, -6, 6, -6, 6, -6))])
    a["jump"] = (260, False, [pose(bob=30, sit=False, armL=-30, armR=30), pose(bob=-50, armL=-160, armR=160, mouth="open"),
                              pose(bob=-30, armL=-120, armR=120), pose(bob=20, armL=-30, armR=30)])
    return a


def limb(x, y, angle, length, width, color, foot=None):
    """A limb hanging from (x, y); angle 0 points down, positive swings right."""
    r = math.radians(angle)
    ex, ey = x + math.sin(r) * length, y + math.cos(r) * length
    svg = (f'<line x1="{x:.1f}" y1="{y:.1f}" x2="{ex:.1f}" y2="{ey:.1f}" stroke="{INK}" stroke-width="{width + 8}" stroke-linecap="round"/>'
           f'<line x1="{x:.1f}" y1="{y:.1f}" x2="{ex:.1f}" y2="{ey:.1f}" stroke="{color}" stroke-width="{width}" stroke-linecap="round"/>')
    if foot:
        svg += f'<ellipse cx="{ex:.1f}" cy="{ey:.1f}" rx="24" ry="14" fill="{foot}" stroke="{INK}" stroke-width="5"/>'
    else:
        svg += f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="13" fill="{SKIN}" stroke="{INK}" stroke-width="5"/>'
    return svg


def face(p, cx, cy):
    out = []
    for ex in (cx - 26, cx + 26):
        if p["eyes"] == "open":
            out.append(f'<ellipse cx="{ex}" cy="{cy + 8}" rx="9" ry="14" fill="{INK}"/>'
                       f'<circle cx="{ex + 3}" cy="{cy + 3}" r="4" fill="white"/>')
        elif p["eyes"] == "closed":
            out.append(f'<path d="M{ex - 11},{cy + 10} q11,9 22,0" stroke="{INK}" stroke-width="5" fill="none"/>')
        else:
            out.append(f'<path d="M{ex - 9},{cy} l18,18 M{ex + 9},{cy} l-18,18" stroke="{INK}" stroke-width="5"/>')
    m = p["mouth"]
    my = cy + 42
    if m == "smile":
        out.append(f'<path d="M{cx - 12},{my} q12,10 24,0" stroke="{INK}" stroke-width="4" fill="none"/>')
    elif m == "open":
        out.append(f'<ellipse cx="{cx}" cy="{my + 3}" rx="11" ry="9" fill="#9d3b52" stroke="{INK}" stroke-width="4"/>')
    elif m == "o":
        out.append(f'<circle cx="{cx}" cy="{my + 2}" r="6" fill="none" stroke="{INK}" stroke-width="4"/>')
    else:
        out.append(f'<line x1="{cx - 10}" y1="{my}" x2="{cx + 10}" y2="{my}" stroke="{INK}" stroke-width="4"/>')
    out.append(f'<ellipse cx="{cx - 40}" cy="{cy + 30}" rx="10" ry="6" fill="#f7768e" opacity="0.35"/>'
               f'<ellipse cx="{cx + 40}" cy="{cy + 30}" rx="10" ry="6" fill="#f7768e" opacity="0.35"/>')
    return "".join(out)


def extras(p, cx, top):
    out = []
    for e in p["extra"]:
        if e == "zz":
            out.append(f'<text x="{cx + 70}" y="{top + 10}" font-size="54" font-family="sans-serif" font-weight="bold" fill="{HAIR_HI}" stroke="{INK}" stroke-width="2">z</text>'
                       f'<text x="{cx + 105}" y="{top - 30}" font-size="38" font-family="sans-serif" font-weight="bold" fill="{HAIR_HI}" stroke="{INK}" stroke-width="2">z</text>')
        elif e.startswith("dots"):
            for i in range(int(e[4:])):
                out.append(f'<circle cx="{cx + 70 + i * 26}" cy="{top - 10}" r="9" fill="{TOP}" stroke="{INK}" stroke-width="3"/>')
        elif e == "!":
            out.append(f'<text x="{cx + 95}" y="{top + 20}" font-size="90" font-family="sans-serif" font-weight="bold" fill="#e0af68" stroke="{INK}" stroke-width="3">!</text>')
        elif e == "spark":
            for sx, sy in ((cx - 120, top + 40), (cx + 110, top + 10), (cx + 125, top + 160)):
                out.append(f'<path d="M{sx},{sy - 22} L{sx + 7},{sy - 7} L{sx + 22},{sy} L{sx + 7},{sy + 7} L{sx},{sy + 22} L{sx - 7},{sy + 7} L{sx - 22},{sy} L{sx - 7},{sy - 7} Z" fill="#e0af68" stroke="{INK}" stroke-width="3"/>')
        elif e == "heart":
            out.append(f'<path d="M{cx + 110},{top + 40} c-25,-30 -60,0 0,40 c60,-40 25,-70 0,-40 z" fill="#f7768e" stroke="{INK}" stroke-width="3"/>')
        elif e == "sweat":
            out.append(f'<path d="M{cx + 85},{top + 40} q-16,30 0,40 q16,-10 0,-40 z" fill="#7dcfff" stroke="{INK}" stroke-width="3"/>')
        elif e == "laptop":
            out.append(f'<rect x="{cx - 75}" y="{top + 420}" width="150" height="16" rx="4" fill="#565f89" stroke="{INK}" stroke-width="4"/>'
                       f'<rect x="{cx - 70}" y="{top + 340}" width="140" height="85" rx="6" fill="#24283b" stroke="{INK}" stroke-width="4"/>'
                       f'<circle cx="{cx}" cy="{top + 382}" r="8" fill="{HAIR_HI}"/>')
    return "".join(out)


def frame_svg(p, label):
    cx = 180
    ground = 785
    sit_drop = 190 if p["sit"] else 0
    hip_y = 470 + p["bob"] + sit_drop
    sh_y = 290 + p["bob"] + sit_drop
    head_cy = 150 + p["bob"] + sit_drop + p["head"]
    top = head_cy - 95
    body = []
    # hair behind the body
    body.append(f'<path d="M{cx - 90},{head_cy} Q{cx - 104},{head_cy + 140} {cx - 78},{head_cy + 175} L{cx + 78},{head_cy + 175} Q{cx + 104},{head_cy + 140} {cx + 90},{head_cy} Z" fill="{HAIR}" stroke="{INK}" stroke-width="6"/>')
    # legs
    if p["sit"]:
        for side in (-1, 1):
            body.append(limb(cx + side * 22, hip_y, side * 55, 120, 34, SKIN))
            body.append(limb(cx + side * 22 + side * 98, hip_y + 69, 0, ground - hip_y - 80, 34, SKIN, foot=SHOES))
    else:
        leg = ground - hip_y - 12
        body.append(limb(cx - 22, hip_y, p["legL"], leg, 34, SKIN, foot=SHOES))
        body.append(limb(cx + 22, hip_y, p["legR"], leg, 34, SKIN, foot=SHOES))
    # skirt + torso
    body.append(f'<path d="M{cx - 58},{hip_y - 30} L{cx + 58},{hip_y - 30} L{cx + 85},{hip_y + 70} L{cx - 85},{hip_y + 70} Z" fill="{SKIRT}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/>')
    body.append(f'<rect x="{cx - 62}" y="{sh_y - 20}" width="124" height="{hip_y - sh_y}" rx="34" fill="{TOP}" stroke="{INK}" stroke-width="6"/>')
    body.append(f'<path d="M{cx - 62},{sh_y} L{cx - 20},{sh_y - 18} L{cx - 30},{hip_y - 30} L{cx - 62},{hip_y - 34} Z M{cx + 62},{sh_y} L{cx + 20},{sh_y - 18} L{cx + 30},{hip_y - 30} L{cx + 62},{hip_y - 34} Z" fill="{JACKET}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/>')
    # arms
    body.append(limb(cx - 66, sh_y + 4, p["armL"], 200, 26, JACKET))
    body.append(limb(cx + 66, sh_y + 4, p["armR"], 200, 26, JACKET))
    # neck, hair back, head, bangs
    body.append(f'<rect x="{cx - 14}" y="{head_cy + 70}" width="28" height="{sh_y - head_cy - 70}" fill="{SKIN}" stroke="{INK}" stroke-width="5"/>')
    body.append(f'<ellipse cx="{cx}" cy="{head_cy + 8}" rx="74" ry="82" fill="{SKIN}" stroke="{INK}" stroke-width="6"/>')
    body.append(f'<path d="M{cx - 84},{head_cy + 10} Q{cx - 80},{head_cy - 95} {cx},{head_cy - 92} Q{cx + 80},{head_cy - 95} {cx + 84},{head_cy + 10} Q{cx + 40},{head_cy - 40} {cx + 8},{head_cy - 20} Q{cx - 30},{head_cy - 45} {cx - 84},{head_cy + 10} Z" fill="{HAIR}" stroke="{INK}" stroke-width="6"/>')
    body.append(f'<path d="M{cx - 40},{head_cy - 70} Q{cx},{head_cy - 85} {cx + 45},{head_cy - 66}" stroke="{HAIR_HI}" stroke-width="7" fill="none" stroke-linecap="round"/>')
    body.append(face(p, cx, head_cy))
    lean = f'rotate({p["lean"]} {cx} {ground})'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'<g transform="{lean}">{"".join(body)}</g>{extras(p, cx, top)}'
            f'<text x="10" y="{H - 6}" font-size="22" font-family="monospace" fill="{INK}" opacity="0.55">{label}</text></svg>')


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "characters" / "kumo")
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"_meta": {"box": [OUT_W, OUT_H], "scale": 1, "placeholder": True}}
    with tempfile.TemporaryDirectory() as tmp:
        for name, (ms, sideways, poses) in animations().items():
            frames = []
            for i, p in enumerate(poses):
                svg = Path(tmp) / f"{name}-{i}.svg"
                svg.write_text(frame_svg(p, f"{name} {i + 1}/{len(poses)} placeholder"))
                frames.append(str(svg))
            # Render at 2x, downscale, join side by side.
            cmd = ["magick", "-background", "none"]
            for f in frames:
                cmd += ["(", f, "-resize", f"{OUT_W}x{OUT_H}!", ")"]
            cmd += ["+append", "-strip", "-depth", "8", "-define", "png:compression-level=9", str(out / f"{name}.png")]
            subprocess.run(cmd, check=True)
            manifest[name] = {"frameWidth": OUT_W, "frameHeight": OUT_H, "frameCount": len(poses),
                              "frameMs": ms, "sideways": sideways}
    (out / "sprites.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {len(manifest) - 1} strips to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
