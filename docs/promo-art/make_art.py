#!/usr/bin/env python3
"""Featuring artwork for Relics: Consoles (Apple promotional asset guidelines).

One original scene: a pixel world that sharpens from chunky 8-bit blocks on the left,
through 16-bit, to smooth low-poly on the right, with a small hero standing on the
hilltop in the middle against an ember sun. No logos, no copy, no devices or
hardware (Apple's rules), no console or game art (ours only).

Writes one SVG per layer per size into out/<size>/, plus a flattened composite.
Render with render.sh (headless Chrome). Layers map 1:1 to Smart Objects in Apple's
PSD template when Apple asks.
"""
import math, os, random

SIZES = {
    # name: (W, H, hero centre y as fraction of H)
    "universal": (5244, 2950, 0.60),   # AppStore_Universal
    "appsgames": (4320, 1080, 0.47),   # AppStore_AppsGamesWatch (upper two-thirds of safe area)
}

EMBER = "#ff7a2f"; EMBER_HI = "#ffb347"; EMBER_DEEP = "#d9481c"
GRAPHITE = "#14141c"; NIGHT = "#1d1b2e"; DUSK = "#4a2a4a"; GLOW = "#ff9a52"

def hill(x, W, base, amp, phase, bump=0.0, bump_w=0.08):
    u = x / W
    y = base - amp * (0.55 * math.sin(u * 6.1 + phase) + 0.3 * math.sin(u * 13.7 + phase * 2.3)
                      + 0.15 * math.sin(u * 29.0 + phase * 0.7))
    # plateau-ish bump at the centre for the hero to stand on
    y -= bump * math.exp(-((u - 0.5) / bump_w) ** 2)
    return y

def step_for(u, k):
    """Pixel size by horizontal position: 8-bit blocks left, smooth low-poly right."""
    bands = [(0.14, 110), (0.27, 72), (0.38, 44), (0.47, 26), (0.55, 14), (0.63, 6)]
    for edge, s in bands:
        if u < edge:
            return max(2, round(s * k))
    return 0  # low-poly from here on

def hill_layer(W, H, k, base, amp, phase, col_a, col_b, bump=0.0, seed=1, rim=None):
    rnd = random.Random(seed)
    parts = []
    x = 0.0
    lowpoly_start = None
    while x < W:
        u = x / W
        s = step_for(u, k)
        if s == 0:
            lowpoly_start = x
            break
        y = hill(x + s / 2, W, base, amp, phase, bump)
        y = round(y / s) * s
        shade = col_a if (int(x // s) % 2 == 0 or s <= 8 * k) else col_b
        parts.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{s+0.6:.1f}" height="{H-y+2:.0f}" fill="{shade}"/>')
        if rim:
            parts.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{s+0.6:.1f}" height="{min(max(s*0.25, 4*k), 14*k):.1f}" fill="{rim}"/>')
        x += s
    if lowpoly_start is not None:
        seg = 150 * k
        xs = [lowpoly_start]
        while xs[-1] < W:
            xs.append(min(W + seg, xs[-1] + seg * (0.7 + 0.6 * rnd.random())))
        pts = [(xx, hill(xx, W, base, amp, phase, bump)) for xx in xs]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            mx = (x0 + x1) / 2; my = max(y0, y1) + 90 * k
            parts.append(f'<polygon points="{x0:.0f},{y0:.0f} {x1:.0f},{y1:.0f} {x1:.0f},{H+2} {x0:.0f},{H+2}" fill="{col_a}"/>')
            parts.append(f'<polygon points="{x0:.0f},{y0:.0f} {x1:.0f},{y1:.0f} {mx:.0f},{my:.0f}" fill="{col_b}"/>')
            if rim:
                parts.append(f'<line x1="{x0:.0f}" y1="{y0:.0f}" x2="{x1:.0f}" y2="{y1:.0f}" stroke="{rim}" stroke-width="{4*k:.1f}"/>')
    return "\n".join(parts)

HERO = [  # 14 x 22 original sprite: wanderer with an ember scarf. . = clear
    "......kkkk....",
    ".....kkkkkk...",
    ".....kSSSSk...",
    ".....kSeSek...",
    ".....kSSSSk...",
    "...rrrkkkk....",
    "..rrrrrrkkk...",
    ".rr.kkkkkkkk..",
    "r...kkkkkkkk..",
    "....kkkkkkkk..",
    "...kkkkkkkkkk.",
    "...kk.kkkk.kk.",
    "...kk.kkkk.kk.",
    "......kkkk....",
    "......kkkk....",
    ".....kk..kk...",
    ".....kk..kk...",
    ".....kk..kk...",
    ".....kk..kk...",
    ".....kk..kk...",
    "....kkk..kkk..",
    "....kkk..kkk..",
]
HERO_COL = {"k": "#0c0b12", "S": "#2a2633", "e": EMBER_HI, "r": EMBER}

def hero_layer(cx, foot_y, px):
    w = len(HERO[0]) * px; h = len(HERO) * px
    x0 = cx - w / 2; y0 = foot_y - h
    out = []
    for r, row in enumerate(HERO):
        for c, ch in enumerate(row):
            if ch != ".":
                out.append(f'<rect x="{x0+c*px:.1f}" y="{y0+r*px:.1f}" width="{px+0.4:.1f}" height="{px+0.4:.1f}" fill="{HERO_COL[ch]}"/>')
    return "\n".join(out), h

def build(name, W, H, hero_fy):
    k = W / 4320
    rnd = random.Random(7)
    cx = W / 2
    hero_px = 15 * k if name == "appsgames" else 22 * k
    sun_cy = H * hero_fy - (6 if name == "appsgames" else 9) * hero_px
    sun_r = (300 if name == "appsgames" else 560) * k
    near_base = H * hero_fy + 90 * k
    foot_y = hill(cx, W, near_base, 70 * k * (H / 1080) ** 0.5, 2.1, bump=60 * k)

    layers = {}
    layers["01-sky"] = (f'<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{GRAPHITE}"/><stop offset="0.45" stop-color="{NIGHT}"/>'
        f'<stop offset="0.78" stop-color="{DUSK}"/><stop offset="1" stop-color="{EMBER_DEEP}"/></linearGradient>'
        f'<radialGradient id="haze" cx="0.5" cy="{sun_cy/H:.3f}" r="0.6">'
        f'<stop offset="0" stop-color="{GLOW}" stop-opacity="0.45"/><stop offset="1" stop-color="{GLOW}" stop-opacity="0"/></radialGradient></defs>'
        f'<rect width="{W}" height="{H}" fill="url(#sky)"/><rect width="{W}" height="{H}" fill="url(#haze)"/>')
    stars = []
    for _ in range(int(260 * (W * H) / (4320 * 1080) ** 1)):
        x = rnd.random() * W; y = rnd.random() * H * 0.55
        u = x / W; s = step_for(u, k) or max(2, round(3 * k))
        s = max(3 * k, min(s, 14 * k)) * (0.5 + rnd.random() * 0.6)
        if math.hypot(x - cx, y - sun_cy) < sun_r * 1.4:
            continue
        op = 0.35 + rnd.random() * 0.6
        stars.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{s:.1f}" height="{s:.1f}" fill="#fff4e6" opacity="{op:.2f}"/>')
    layers["02-stars"] = "\n".join(stars)
    # ember sun with retro slats, slats widen toward the horizon
    slats = []
    y = sun_cy - sun_r * 0.25; gap = 5 * k; i = 0
    while y < sun_cy + sun_r:
        slats.append(f'<rect x="{cx-sun_r-2:.0f}" y="{y:.1f}" width="{2*sun_r+4:.0f}" height="{gap:.1f}" fill="black"/>')
        i += 1; y += gap + (sun_r * 0.16) / (1 + i * 0.35); gap *= 1.28
    layers["03-sun"] = (f'<defs><linearGradient id="sun" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{EMBER_HI}"/>'
        f'<stop offset="1" stop-color="{EMBER_DEEP}"/></linearGradient><mask id="slat"><rect width="{W}" height="{H}" fill="white"/>{"".join(slats)}</mask></defs>'
        f'<circle cx="{cx:.0f}" cy="{sun_cy:.0f}" r="{sun_r*1.25:.0f}" fill="{GLOW}" opacity="0.18"/>'
        f'<circle cx="{cx:.0f}" cy="{sun_cy:.0f}" r="{sun_r:.0f}" fill="url(#sun)" mask="url(#slat)"/>')
    layers["04-far-hills"] = hill_layer(W, H, k, near_base - 170 * k * (H / 1080) ** 0.6, 110 * k, 0.4, "#5a2d52", "#4c2647", seed=3, rim="#8a4a5e")
    layers["05-mid-hills"] = hill_layer(W, H, k, near_base - 70 * k * (H / 1080) ** 0.6, 90 * k, 4.0, "#33193a", "#2a1530", seed=5, rim="#6b3048")
    layers["06-near-hills"] = hill_layer(W, H, k, near_base, 70 * k * (H / 1080) ** 0.5, 2.1, "#141119", "#131018", bump=60 * k, seed=9, rim="#c2542a")
    hero, hero_h = hero_layer(cx, foot_y + 2 * k, hero_px)
    layers["07-hero"] = hero
    sparks = []
    sr = random.Random(11)
    for _ in range(int(55 * (W / 4320) * (H / 1080) ** 0.5)):
        x = sr.gauss(cx, W * 0.11); y = foot_y - sr.random() ** 0.7 * hero_h * 2.6
        sz = (4 + sr.random() * 9) * k
        sparks.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{sz:.1f}" height="{sz:.1f}" fill="{EMBER_HI if sr.random()<0.5 else EMBER}" opacity="{0.35+sr.random()*0.6:.2f}"/>')
    layers["08-sparks"] = (f'<defs><linearGradient id="gf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0"/>'
        f'<stop offset="1" stop-color="#05040a" stop-opacity="0.7"/></linearGradient></defs>'
        f'<rect x="0" y="{foot_y+40*k:.0f}" width="{W}" height="{H-foot_y:.0f}" fill="url(#gf)"/>' + "".join(sparks))
    return layers

def svg(W, H, body, transparent=True):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" shape-rendering="crispEdges">{body}</svg>'

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    for name, (W, H, fy) in SIZES.items():
        d = os.path.join(here, "out", name); os.makedirs(d, exist_ok=True)
        layers = build(name, W, H, fy)
        order = sorted(layers)
        for key in order:
            open(os.path.join(d, f"{key}.svg"), "w").write(svg(W, H, layers[key]))
        comp = [layers[k_] for k_ in order]
        open(os.path.join(d, "00-composite.svg"), "w").write(svg(W, H, "".join(comp)))
        print(name, W, H, len(order), "layers")
