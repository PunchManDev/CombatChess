#!/usr/bin/env python3
"""Combat Chess pixel asset generator v2 — SF2-density design language.

96x96 jointed fighters with 12 poses (directional punches/blocks, timed dodge,
exhausted, KO), 360x640 detailed stages, 24px board tiles + icons, pixel text.
Run from repo root; outputs into CombatChess/CombatChess/PixelAssets/.
"""
import os
import random
from PIL import Image, ImageDraw

random.seed(1994)

OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "CombatChess", "PixelAssets")
os.makedirs(OUTDIR, exist_ok=True)

# ---------------------------------------------------------------- palette ---
OUT = (24, 16, 30, 255)
SKIN = (242, 199, 152, 255)
SKIN_SH = (208, 152, 104, 255)
SKIN_HI = (255, 230, 194, 255)
SKIN_DK = (156, 100, 66, 255)
GLOVE = (206, 66, 54, 255)
GLOVE_SH = (146, 40, 34, 255)
GOLD = (246, 182, 30, 255)
GOLD_SH = (178, 122, 20, 255)
GREY = (208, 212, 224, 255)
GREY_SH = (140, 146, 168, 255)
GREY_DK = (96, 102, 124, 255)
BROWN = (138, 92, 56, 255)
WHITE = (248, 244, 234, 255)
SHOE = (48, 38, 58, 255)
SHOE_HI = (86, 72, 100, 255)
SWEAT = (140, 220, 250, 255)

TEAMS = {
    # Chess armies: WHITE = polished silver plate (player), BLACK = obsidian
    # plate (CPU). GI = heraldic cloth accents (tabard/mane/plume) — blue for
    # White, red for Black — so teams stay readable mid-fight.
    # STEEL = 6-tone armor ramp (deep shadow → specular).
    "white": {"GI": (70, 124, 248, 255), "GI_SH": (42, 76, 176, 255),
              "GI_DK": (26, 46, 116, 255), "GI_HI": (128, 168, 255, 255),
              "STEEL": [(64, 62, 80, 255), (104, 104, 124, 255), (148, 150, 170, 255),
                        (190, 194, 212, 255), (226, 230, 242, 255), (255, 255, 255, 255)],
              "PANTS": [(118, 114, 128, 255), (168, 164, 176, 255), (212, 208, 218, 255), (244, 242, 248, 255)]},
    "black": {"GI": (238, 70, 66, 255), "GI_SH": (172, 40, 52, 255),
              "GI_DK": (112, 22, 38, 255), "GI_HI": (255, 132, 116, 255),
              "STEEL": [(18, 14, 26, 255), (40, 34, 56, 255), (66, 58, 88, 255),
                        (96, 88, 124, 255), (134, 126, 164, 255), (198, 190, 226, 255)],
              "PANTS": [(14, 12, 20, 255), (40, 36, 52, 255), (68, 64, 86, 255), (104, 100, 130, 255)]},
}

PIECES = ["pawn", "knight", "bishop", "rook", "queen"]
FRAMES = ["idle_a", "idle_b", "idle_c", "wind_l", "wind_r", "punch_l", "punch_r",
          "block_l", "block_r", "dodge", "dodge_b", "hit", "exhausted", "ko"]

CANVAS = 96
GROUND = 90
CX0 = 42


def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def rect(d, x0, y0, x1, y1, c):
    if x1 < x0 or y1 < y0:
        return
    d.rectangle([x0, y0, x1, y1], fill=c)


def line(d, p0, p1, c, w):
    d.line([p0, p1], fill=c, width=w)


def auto_outline(img):
    px = img.load()
    w, h = img.size
    edges = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 0:
                        edges.append((x, y))
                        break
    for x, y in edges:
        px[x, y] = OUT
    return img


def mix(c, target, t):
    return tuple(int(c[i] + (target[i] - c[i]) * t) for i in range(3)) + (255,)


def shade_pass(img):
    """SF2-style volume pass: top-lit highlight, under-shadow, edge dither.

    For each opaque pixel, if the pixel above is empty → lighten (light from
    above); if the pixel below is empty → darken. Adds rounded, sculpted depth
    to every shape without hand-shading each frame.
    """
    px = img.load()
    w, h = img.size
    lighten, darken = [], []
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if c[3] == 0 or c[:3] == OUT[:3]:
                continue
            above = px[x, y - 1] if y > 0 else (0, 0, 0, 0)
            below = px[x, y + 1] if y < h - 1 else (0, 0, 0, 0)
            if above[3] == 0:
                lighten.append((x, y, c))
            elif below[3] == 0:
                darken.append((x, y, c))
            else:
                # subtle left-edge rim shadow for roundness
                left = px[x - 1, y] if x > 0 else (0, 0, 0, 0)
                if left[3] == 0 and (x + y) % 2 == 0:
                    darken.append((x, y, c))
    for x, y, c in lighten:
        px[x, y] = mix(c, (255, 255, 255), 0.35)
    for x, y, c in darken:
        px[x, y] = mix(c, (0, 0, 0), 0.3)
    return img


# ------------------------------------------------------------------- heads --
def draw_head(d, piece, hx, hy, pal):
    """Armored head, ~20px tall. hx = center, hy = top of head block."""
    S = pal["STEEL"]
    C, C_SH = pal["GI"], pal["GI_SH"]
    if piece == "pawn":
        # great helm with plume
        rect(d, hx - 6, hy + 2, hx + 6, hy + 16, S[2])
        rect(d, hx - 6, hy + 2, hx - 4, hy + 16, S[1])
        rect(d, hx + 4, hy + 2, hx + 6, hy + 16, S[3])
        d.ellipse([hx - 6, hy - 3, hx + 6, hy + 6], fill=S[3])   # dome
        rect(d, hx - 3, hy - 2, hx + 1, hy - 1, S[5])            # dome glint
        rect(d, hx - 4, hy + 7, hx + 5, hy + 7, S[4])            # brow ridge
        rect(d, hx - 4, hy + 8, hx + 5, hy + 9, OUT)             # visor slit
        for by in (hy + 12, hy + 14):                            # breath holes
            rect(d, hx - 2, by, hx + 2, by, S[1])
        rect(d, hx - 1, hy - 9, hx + 1, hy - 3, C)               # plume
        rect(d, hx - 1, hy - 9, hx - 1, hy - 3, C_SH)
    elif piece == "knight":
        # armored warhorse (chanfron face plate)
        rect(d, hx - 5, hy, hx + 4, hy + 17, S[2])               # skull plate
        rect(d, hx - 5, hy, hx - 3, hy + 17, S[1])
        rect(d, hx - 1, hy + 1, hx + 2, hy + 2, S[4])            # forehead glint
        rect(d, hx + 4, hy + 7, hx + 13, hy + 15, S[3])          # muzzle armor
        rect(d, hx + 4, hy + 13, hx + 13, hy + 15, S[1])
        rect(d, hx + 11, hy + 9, hx + 12, hy + 10, OUT)          # nostril
        rect(d, hx + 4, hy + 8, hx + 10, hy + 8, GOLD)           # chanfron trim
        rect(d, hx - 3, hy - 5, hx - 1, hy, S[3])                # ear guards
        rect(d, hx + 1, hy - 5, hx + 3, hy, S[3])
        rect(d, hx - 8, hy - 3, hx - 5, hy + 17, C)              # mane
        rect(d, hx - 8, hy + 4, hx - 5, hy + 5, C_SH)
        rect(d, hx - 8, hy + 10, hx - 5, hy + 11, C_SH)
        rect(d, hx + 1, hy + 4, hx + 3, hy + 6, OUT)             # eye slit
        rect(d, hx + 1, hy + 4, hx + 1, hy + 4, S[5])            # eye glint
    elif piece == "bishop":
        rect(d, hx - 5, hy + 10, hx + 5, hy + 18, SKIN)          # face
        rect(d, hx - 5, hy + 10, hx - 3, hy + 18, SKIN_SH)
        rect(d, hx - 5, hy + 16, hx + 5, hy + 18, GREY_SH)       # beard
        rect(d, hx - 7, hy + 7, hx + 7, hy + 10, C)              # mitre base
        rect(d, hx - 6, hy + 3, hx + 6, hy + 7, C)
        rect(d, hx - 4, hy - 1, hx + 4, hy + 3, C)
        rect(d, hx - 2, hy - 4, hx + 2, hy - 1, C)
        rect(d, hx - 7, hy + 7, hx - 4, hy + 10, C_SH)
        rect(d, hx - 1, hy - 4, hx + 1, hy + 9, GOLD)            # front band
        rect(d, hx - 3, hy + 1, hx + 3, hy + 2, GOLD)            # cross bar
        rect(d, hx + 2, hy + 12, hx + 4, hy + 13, OUT)           # eye
        rect(d, hx - 6, hy + 18, hx + 6, hy + 20, S[3])          # gorget
        rect(d, hx - 6, hy + 20, hx + 6, hy + 20, S[1])
    elif piece == "rook":
        rect(d, hx - 9, hy + 3, hx + 9, hy + 18, S[2])           # tower
        rect(d, hx - 9, hy + 3, hx - 6, hy + 18, S[1])
        rect(d, hx + 6, hy + 3, hx + 9, hy + 18, S[3])
        for bx in (hx - 9, hx - 2, hx + 5):                      # merlons
            rect(d, bx, hy - 3, bx + 3, hy + 3, S[3])
            rect(d, bx, hy - 3, bx + 3, hy - 3, S[5])
        rect(d, hx - 9, hy + 9, hx + 9, hy + 9, S[0])            # brick lines
        rect(d, hx - 9, hy + 14, hx + 9, hy + 14, S[0])
        rect(d, hx - 4, hy + 10, hx + 6, hy + 13, OUT)           # visor
        rect(d, hx - 2, hy + 11, hx + 4, hy + 12, GOLD)          # glow eyes
        rect(d, hx + 6, hy + 5, hx + 7, hy + 7, S[0])            # crack
    elif piece == "queen":
        rect(d, hx - 8, hy + 6, hx - 5, hy + 20, BROWN)          # hair back
        rect(d, hx + 5, hy + 8, hx + 7, hy + 17, BROWN)          # hair front
        rect(d, hx - 5, hy + 6, hx + 5, hy + 16, SKIN)           # face
        rect(d, hx - 5, hy + 6, hx - 3, hy + 16, SKIN_SH)
        rect(d, hx - 7, hy + 2, hx + 7, hy + 5, GOLD)            # crown band
        for cx_ in (hx - 7, hx - 2, hx + 3):
            rect(d, cx_, hy - 3, cx_ + 1, hy + 2, GOLD)          # points
        rect(d, hx - 1, hy + 1, hx, hy + 2, (232, 62, 96, 255))  # jewel
        rect(d, hx + 4, hy + 3, hx + 5, hy + 4, (98, 214, 232, 255))
        rect(d, hx + 1, hy + 9, hx + 3, hy + 10, OUT)            # eye
        rect(d, hx + 1, hy + 8, hx + 3, hy + 8, BROWN)           # brow
        rect(d, hx + 1, hy + 13, hx + 3, hy + 13, (206, 82, 92, 255))  # lips
        rect(d, hx - 5, hy + 17, hx + 5, hy + 19, S[3])          # gorget
        rect(d, hx - 5, hy + 19, hx + 5, hy + 19, S[1])
    elif piece == "king":
        rect(d, hx - 5, hy + 6, hx + 5, hy + 14, SKIN)           # face
        rect(d, hx - 5, hy + 6, hx - 3, hy + 14, SKIN_SH)
        rect(d, hx - 5, hy + 12, hx + 5, hy + 17, GREY)          # beard
        rect(d, hx - 5, hy + 12, hx - 3, hy + 17, GREY_SH)
        rect(d, hx - 1, hy + 12, hx + 1, hy + 13, SKIN_SH)       # mouth gap
        rect(d, hx - 7, hy + 2, hx + 7, hy + 5, GOLD)            # crown band
        rect(d, hx - 7, hy - 1, hx - 5, hy + 2, GOLD)
        rect(d, hx + 5, hy - 1, hx + 7, hy + 2, GOLD)
        rect(d, hx - 1, hy - 2, hx + 1, hy + 2, GOLD)            # center arch
        rect(d, hx - 1, hy - 6, hx, hy - 2, GOLD)                # cross post
        rect(d, hx - 2, hy - 5, hx + 1, hy - 4, GOLD)            # cross bar
        rect(d, hx - 1, hy + 3, hx, hy + 4, (232, 62, 96, 255))  # jewel
        rect(d, hx + 3, hy + 3, hx + 4, hy + 4, (98, 214, 232, 255))
        rect(d, hx + 2, hy + 8, hx + 4, hy + 9, OUT)             # eye
        rect(d, hx + 1, hy + 7, hx + 4, hy + 7, GREY_SH)         # brow
        rect(d, hx - 5, hy + 17, hx + 5, hy + 19, S[3])          # gorget
        rect(d, hx - 5, hy + 19, hx + 5, hy + 19, S[1])


# ----------------------------------------------------------------- fighter --
# SF1-brawler bodies: bare muscled torsos, baggy team-colored pants, bare
# fists with heraldic wristbands. Piece identity stays in the heads.
POSES = {
    "idle_a":   dict(lean=0, crouch=0, lead=(14, -9), rear=(8, -14), legs="stance"),
    "idle_b":   dict(lean=1, crouch=3, lead=(13, -6), rear=(7, -11), legs="stance"),
    "idle_c":   dict(lean=0, crouch=1, lead=(14, -8), rear=(8, -13), legs="stance"),
    "wind_l":   dict(lean=-4, crouch=2, lead=(-6, 2), rear=(9, -13), legs="stance"),
    "wind_r":   dict(lean=-8, crouch=4, lead=(12, -10), rear=(-17, -2), legs="crouch"),
    "punch_l":  dict(lean=7, crouch=0, lead=(33, -7), rear=(4, -12), legs="lunge", speed=1),
    "punch_r":  dict(lean=13, crouch=1, lead=(8, -16), rear=(37, -8), legs="lunge", speed=2),
    "block_l":  dict(lean=-2, crouch=2, lead=(12, -18), rear=(14, -10), legs="stance"),
    "block_r":  dict(lean=-4, crouch=7, lead=(12, 4), rear=(13, -3), legs="crouch"),
    "dodge":    dict(lean=-16, crouch=5, lead=(10, -7), rear=(6, -12), legs="back", lines=True),
    "dodge_b":  dict(lean=-22, crouch=8, lead=(9, -5), rear=(5, -10), legs="back", lines=True),
    "hit":      dict(lean=-14, crouch=2, lead=(-8, -16), rear=(-12, 0), legs="back", spark=True),
    "exhausted": dict(lean=6, crouch=9, lead=(8, 18), rear=(4, 20), legs="crouch", sweat=True),
}


def skin_tones(piece):
    """(deep, shadow, base, highlight). The rook is a stone golem."""
    if piece == "rook":
        return ((84, 90, 112, 255), (128, 134, 156, 255),
                (176, 182, 200, 255), (218, 224, 238, 255))
    return (SKIN_DK, SKIN_SH, SKIN, SKIN_HI)


def draw_fist(d, x, y, tones, pal, big=False):
    """Bare fist with knuckle crease + heraldic wristband."""
    dk, sh, base, hi = tones
    s = 5 if big else 4
    rect(d, x - s - 2, y - 2, x - s, y + 3, pal["GI"])            # wristband
    rect(d, x - s - 2, y + 2, x - s, y + 3, pal["GI_SH"])
    rect(d, x - s, y - s + 1, x + s, y + s - 1, base)
    rect(d, x - s, y + s - 3, x + s, y + s - 1, sh)
    rect(d, x - s, y - s + 1, x + s, y - s + 1, hi)
    rect(d, x - s + 1, y - 1, x + s - 1, y - 1, dk)               # knuckles


def draw_arm(d, piece, pal, shoulder, fist, front, extended):
    """Bare muscled arm: deltoid cap, thick bicep, tapered forearm."""
    tones = skin_tones(piece)
    dk, sh, base, hi = tones
    c = base if front else sh
    sag = 0 if extended else 5
    ex = shoulder[0] + (fist[0] - shoulder[0]) * 0.45
    ey = shoulder[1] + (fist[1] - shoulder[1]) * 0.45 + sag
    line(d, shoulder, (ex, ey), c, 8)                             # bicep
    line(d, (ex, ey), fist, c, 6)                                 # forearm
    if front:
        # muscle ridge highlights + under-shadow
        line(d, (shoulder[0], shoulder[1] - 2), (ex, ey - 2), hi, 3)
        line(d, (ex, ey - 2), (fist[0], fist[1] - 2), hi, 2)
        line(d, (ex, ey + 2), (fist[0], fist[1] + 2), dk, 1)
        # deltoid cap
        d.ellipse([shoulder[0] - 5, shoulder[1] - 5, shoulder[0] + 4, shoulder[1] + 3], fill=base)
        rect(d, shoulder[0] - 3, shoulder[1] - 4, shoulder[0] + 1, shoulder[1] - 3, hi)
    draw_fist(d, fist[0], fist[1], tones, pal, big=extended)


def draw_muscle_torso(d, piece, pal, cx, chest_y, hip_y, cw):
    """Shirtless brawler chest: traps, clavicle, pecs, ab grid, obliques.
    The queen wears a cloth bodice instead."""
    half = cw // 2
    if piece == "queen":
        C, C_SH, C_DK, C_HI = pal["GI"], pal["GI_SH"], pal["GI_DK"], pal["GI_HI"]
        span = max(1, hip_y - chest_y)
        for i, y in enumerate(range(chest_y, hip_y + 1)):
            t = i / span
            w = int(half - 2 * t)
            rect(d, cx - w, y, cx + w, y, C)
            rect(d, cx - w, y, cx - w + 1, y, C_SH)
            rect(d, cx + w - 1, y, cx + w, y, C_HI)
        rect(d, cx - 1, chest_y + 3, cx, hip_y - 3, C_DK)         # bodice seam
        rect(d, cx - half + 1, chest_y + 8, cx + half - 1, chest_y + 8, C_DK)
        rect(d, cx - 3, chest_y - 2, cx + 3, chest_y + 1, SKIN)   # neckline
        return

    dk, sh, base, hi = skin_tones(piece)
    span = max(1, hip_y - chest_y)
    for i, y in enumerate(range(chest_y, hip_y + 1)):
        t = i / span
        w = int(half - 2 * t)                                     # V-taper
        rect(d, cx - w, y, cx + w, y, base)
        rect(d, cx - w, y, cx - w + 1, y, sh)
        rect(d, cx + w - 1, y, cx + w, y, hi)
    # traps + neck
    rect(d, cx - 4, chest_y - 3, cx + 4, chest_y, base)
    rect(d, cx - 4, chest_y - 3, cx + 4, chest_y - 3, hi)
    # clavicle
    rect(d, cx - half + 2, chest_y + 2, cx + half - 2, chest_y + 2, sh)
    # pecs
    d.ellipse([cx - half + 1, chest_y + 3, cx - 1, chest_y + 9], fill=hi)
    d.ellipse([cx + 1, chest_y + 3, cx + half - 1, chest_y + 9], fill=hi)
    rect(d, cx - half + 2, chest_y + 9, cx - 1, chest_y + 9, dk)
    rect(d, cx + 1, chest_y + 9, cx + half - 2, chest_y + 9, dk)
    rect(d, cx - 1, chest_y + 4, cx, chest_y + 9, sh)             # sternum
    rect(d, cx - half + 3, chest_y + 8, cx - half + 3, chest_y + 8, dk)
    rect(d, cx + half - 3, chest_y + 8, cx + half - 3, chest_y + 8, dk)
    # abs grid
    ab_top = chest_y + 11
    rect(d, cx, ab_top, cx, hip_y - 2, sh)
    for gy in (ab_top + 3, ab_top + 7):
        rect(d, cx - 4, gy, cx + 4, gy, sh)
        rect(d, cx - 3, gy - 1, cx + 3, gy - 1, hi)
    # obliques
    rect(d, cx - half + 1, ab_top + 1, cx - half + 2, hip_y - 2, sh)


def draw_pants_leg(d, P, hip, knee, ankle, front, toe_dx=4):
    """Baggy trouser leg: wide thigh/shin, fold shading, cuff, grey shoe."""
    c = P[2] if front else P[1]
    line(d, hip, knee, c, 10)
    line(d, knee, ankle, c, 9)
    if front:
        line(d, (hip[0] - 3, hip[1]), (knee[0] - 3, knee[1]), P[3], 3)     # fold light
        line(d, (hip[0] + 3, hip[1]), (knee[0] + 3, knee[1]), P[0], 2)     # crease
        line(d, (knee[0] - 3, knee[1]), (ankle[0] - 3, ankle[1]), P[3], 2)
        rect(d, int(knee[0]) - 2, int(knee[1]), int(knee[0]) + 2, int(knee[1]), P[0])
    ax, ay = int(ankle[0]), int(ankle[1])
    rect(d, ax - 6, ay - 2, ax + 6, ay + 1, P[1])                 # gathered cuff
    rect(d, ax - 6, ay - 2, ax + 6, ay - 2, P[3])
    rect(d, ax - 5, ay + 1, ax + 5 + toe_dx, ay + 4, GREY)        # shoe
    rect(d, ax - 5, ay + 1, ax + 5 + toe_dx, ay + 1, WHITE)
    rect(d, ax - 5, ay + 4, ax + 5 + toe_dx, ay + 4, GREY_SH)


def leg_points(cx, crouch, style):
    hip_y = 66 + crouch
    if style == "stance":
        return [((cx - 4, hip_y), (cx - 14, 77), (cx - 18, GROUND - 4), False),
                ((cx + 4, hip_y), (cx + 11, 76), (cx + 15, GROUND - 4), True)]
    if style == "lunge":
        return [((cx - 4, hip_y), (cx - 18, 78), (cx - 24, GROUND - 4), False),
                ((cx + 4, hip_y), (cx + 17, 75), (cx + 24, GROUND - 4), True)]
    if style == "back":
        return [((cx - 4, hip_y), (cx - 16, 76), (cx - 21, GROUND - 4), False),
                ((cx + 4, hip_y), (cx + 6, 77), (cx + 9, GROUND - 4), True)]
    # crouch
    return [((cx - 4, hip_y), (cx - 15, 80), (cx - 17, GROUND - 4), False),
            ((cx + 4, hip_y), (cx + 13, 80), (cx + 15, GROUND - 4), True)]


def draw_ko(d, piece, pal):
    """Face-down sprawl, Joe-style."""
    tones = skin_tones(piece)
    dk, sh, base, hi = tones
    P = pal["PANTS"]
    g = GROUND - 1
    # legs crumpled right
    line(d, (56, g - 7), (72, g - 4), P[2], 9)
    line(d, (54, g - 4), (66, g - 2), P[1], 7)
    rect(d, 72, g - 7, 80, g - 2, GREY)                           # shoe
    rect(d, 72, g - 7, 80, g - 7, WHITE)
    # torso mound (bare back)
    d.ellipse([32, g - 13, 58, g - 2], fill=base)
    rect(d, 34, g - 4, 56, g - 2, sh)
    rect(d, 36, g - 12, 52, g - 11, hi)                           # spine light
    rect(d, 50, g - 13, 54, g - 2, P[2])                          # waistband
    # reaching arm
    line(d, (36, g - 9), (23, g - 13), base, 5)
    draw_fist(d, 21, g - 15, tones, pal)
    # head on its side
    draw_head(d, piece, 22, g - 27, pal)
    # dizzy stars
    for sx, sy in ((16, g - 44), (30, g - 50), (44, g - 44)):
        rect(d, sx - 1, sy, sx + 1, sy, GOLD)
        rect(d, sx, sy - 1, sx, sy + 1, GOLD)


def draw_frame(piece, team, frame):
    pal = TEAMS[team]
    P = pal["PANTS"]
    C, C_SH = pal["GI"], pal["GI_SH"]
    img = new(CANVAS, CANVAS)
    d = ImageDraw.Draw(img)

    if frame == "ko":
        draw_ko(d, piece, pal)
        return auto_outline(shade_pass(img))

    p = POSES[frame]
    lean, crouch = p["lean"], p["crouch"]
    cx = CX0 + lean
    cw = {"pawn": 13, "rook": 18}.get(piece, 15)                  # chest width
    half = cw // 2
    chest_y = 36 + crouch
    hip_y = 60 + crouch

    legs_cx = CX0 + lean // 2
    legs = leg_points(legs_cx, crouch, p["legs"])

    # ---- back leg / dress
    if piece == "queen":
        top_w, bot_w = half + 1, half + 8
        for i, y in enumerate(range(hip_y, GROUND - 1)):
            t = i / max(1, (GROUND - 2 - hip_y))
            wdt = int(top_w + (bot_w - top_w) * t)
            rect(d, legs_cx - wdt, y, legs_cx + wdt, y, C)
            rect(d, legs_cx - wdt, y, legs_cx - wdt + 3, y, C_SH)
            rect(d, legs_cx + wdt - 1, y, legs_cx + wdt, y, pal["GI_HI"])
        for fx in (legs_cx - 4, legs_cx + 2, legs_cx + 8):
            rect(d, fx, hip_y + 6, fx, GROUND - 3, pal["GI_DK"])
        for ty in range(hip_y + 12, GROUND - 4):                  # fabric dither
            for tx in range(legs_cx - half - 4, legs_cx + half + 5):
                if (tx + ty) % 2 == 0 and (ty - hip_y) % 3 == 0:
                    rect(d, tx, ty, tx, ty, C_SH)
        rect(d, legs_cx - half - 7, GROUND - 3, legs_cx - half - 1, GROUND - 1, GREY)
        rect(d, legs_cx + half + 1, GROUND - 3, legs_cx + half + 7, GROUND - 1, GREY)
    else:
        hip, knee, ankle, front = legs[0]
        draw_pants_leg(d, P, hip, knee, ankle, front, toe_dx=3)

    # ---- rear arm (behind torso)
    rear_sh = (cx - half + 2, chest_y + 4)
    rear_fist = (rear_sh[0] + p["rear"][0], rear_sh[1] + p["rear"][1])
    rear_extended = frame == "punch_r"
    draw_arm(d, piece, pal, rear_sh, rear_fist, front=rear_extended, extended=rear_extended)

    # ---- baggy hip block + torso
    if piece != "queen":
        rect(d, cx - half - 1, hip_y - 1, cx + half + 1, hip_y + 7, P[2])
        rect(d, cx - half - 1, hip_y - 1, cx - half + 1, hip_y + 7, P[1])
        rect(d, cx + half, hip_y - 1, cx + half + 1, hip_y + 7, P[3])
        rect(d, cx, hip_y + 2, cx, hip_y + 7, P[0])               # crotch crease
        # belt + heraldic buckle
        rect(d, cx - half - 1, hip_y - 2, cx + half + 1, hip_y - 1, (40, 34, 48, 255))
        rect(d, cx - 1, hip_y - 2, cx + 1, hip_y - 1, C)
    draw_muscle_torso(d, piece, pal, cx, chest_y, hip_y, cw)

    # ---- front leg (overlaps hip block)
    if piece != "queen":
        hip, knee, ankle, front = legs[1]
        draw_pants_leg(d, P, hip, knee, ankle, front, toe_dx=4)

    # ---- head
    head_dx = {"hit": -5, "punch_r": 2, "exhausted": 3}.get(frame, 0)
    draw_head(d, piece, cx + 1 + head_dx, chest_y - 22, pal)

    # ---- front (lead) arm
    lead_sh = (cx + half - 1, chest_y + 3)
    lead_fist = (lead_sh[0] + p["lead"][0], lead_sh[1] + p["lead"][1])
    lead_extended = frame == "punch_l"
    draw_arm(d, piece, pal, lead_sh, lead_fist, front=True, extended=lead_extended)

    # ---- effects
    if p.get("speed"):
        n = p["speed"]
        fist = lead_fist if frame == "punch_l" else rear_fist
        for i in range(2 + n):
            ly = fist[1] - 6 + i * 5
            rect(d, min(93, fist[0] + 8), ly, min(94, fist[0] + 14 + n * 3), ly, WHITE)
    if p.get("lines"):
        for ly in (chest_y + 4, chest_y + 14, hip_y + 4):
            rect(d, cx + half + 10, ly, cx + half + 20, ly, WHITE)
    if p.get("spark"):
        sx, sy = cx + 16, chest_y - 16
        rect(d, sx - 1, sy, sx + 1, sy, GOLD)
        rect(d, sx, sy - 1, sx, sy + 1, WHITE)
    if p.get("sweat"):
        rect(d, cx - 10, chest_y - 20, cx - 10, chest_y - 18, SWEAT)
        rect(d, cx + 12, chest_y - 24, cx + 12, chest_y - 22, SWEAT)
        rect(d, cx + 14, chest_y - 18, cx + 14, chest_y - 17, SWEAT)

    return auto_outline(shade_pass(img))


def gen_fighters():
    # The king fights too (check-challenge last-stand rule).
    for piece in PIECES + ["king"]:
        for team in TEAMS:
            for frame in FRAMES:
                draw_frame(piece, team, frame).save(
                    os.path.join(OUTDIR, f"fighter_{piece}_{team}_{frame}.png"))


# ------------------------------------------------------------- board icons --
def draw_icon(piece, is_white):
    """24x24 staunton icons."""
    img = new(24, 24)
    d = ImageDraw.Draw(img)
    body = (246, 240, 226, 255) if is_white else (70, 62, 92, 255)
    shade = (204, 192, 168, 255) if is_white else (48, 42, 66, 255)
    hi = WHITE if is_white else (108, 98, 134, 255)

    def base():
        rect(d, 4, 19, 19, 21, body)
        rect(d, 4, 21, 19, 21, shade)
        rect(d, 6, 18, 17, 18, shade)

    if piece == "pawn":
        rect(d, 9, 3, 14, 8, body)
        rect(d, 9, 3, 10, 8, shade)
        rect(d, 10, 9, 13, 13, body)
        rect(d, 8, 14, 15, 17, body)
        rect(d, 10, 4, 10, 5, hi)
    elif piece == "knight":
        rect(d, 7, 3, 13, 17, body)
        rect(d, 13, 5, 18, 10, body)
        rect(d, 7, 3, 8, 17, shade)
        rect(d, 7, 1, 10, 3, body)
        rect(d, 12, 1, 14, 3, body)
        rect(d, 6, 10, 7, 17, body)
        rect(d, 15, 7, 16, 8, shade)
        rect(d, 8, 4, 8, 5, hi)
    elif piece == "bishop":
        rect(d, 11, 0, 12, 2, body)
        rect(d, 8, 3, 15, 11, body)
        rect(d, 8, 3, 9, 11, shade)
        rect(d, 11, 5, 12, 8, shade)
        rect(d, 9, 12, 14, 17, body)
        rect(d, 9, 4, 9, 5, hi)
    elif piece == "rook":
        for bx in (5, 10, 15):
            rect(d, bx, 2, bx + 3, 6, body)
        rect(d, 5, 6, 18, 9, body)
        rect(d, 7, 10, 16, 17, body)
        rect(d, 7, 10, 8, 17, shade)
        rect(d, 10, 12, 13, 15, shade)
        rect(d, 6, 3, 6, 5, hi)
    elif piece == "queen":
        for bx in (5, 10, 15):
            rect(d, bx, 1, bx + 2, 5, body)
        rect(d, 5, 0, 6, 1, body)
        rect(d, 15, 0, 16, 1, body)
        rect(d, 5, 6, 18, 9, body)
        rect(d, 7, 10, 16, 16, body)
        rect(d, 7, 10, 8, 16, shade)
        rect(d, 10, 7, 10, 8, hi)
    elif piece == "king":
        rect(d, 11, 0, 12, 6, body)
        rect(d, 9, 2, 14, 3, body)
        rect(d, 6, 7, 17, 10, body)
        rect(d, 8, 11, 15, 16, body)
        rect(d, 8, 11, 9, 16, shade)
        rect(d, 11, 12, 12, 15, shade)
        rect(d, 7, 8, 7, 9, hi)
    base()
    return auto_outline(img)


def gen_icons():
    for piece in PIECES + ["king"]:
        for color, is_white in (("white", True), ("black", False)):
            draw_icon(piece, is_white).save(
                os.path.join(OUTDIR, f"icon_{piece}_{color}.png"))


# ------------------------------------------------------------- action cards --
def draw_card(kind):
    """22x30 SF-style action card: gold frame, energy stripes, boxing glove,
    lightning bolt. `kind` = 'blue' / 'red' / 'spent'."""
    img = new(22, 30)
    d = ImageDraw.Draw(img)
    spent = kind == "spent"
    frame = GREY_SH if spent else GOLD
    frame_hi = GREY if spent else (255, 226, 120, 255)
    inner = (34, 30, 46, 255) if spent else (22, 18, 44, 255)

    rect(d, 0, 0, 21, 29, frame)
    rect(d, 0, 0, 21, 0, frame_hi)                      # top frame shine
    rect(d, 0, 0, 0, 29, frame_hi)
    rect(d, 2, 2, 19, 27, inner)

    if spent:
        # burnt-out card: hollow glove + crack
        rect(d, 7, 11, 14, 17, (58, 52, 74, 255))
        rect(d, 8, 12, 13, 16, inner)
        line(d, (5, 5), (16, 24), (72, 64, 92, 255), 1)
        return img

    stripe = TEAMS[kind]["GI"]
    stripe_dk = TEAMS[kind]["GI_SH"]
    # diagonal energy stripes
    line(d, (2, 22), (19, 5), stripe_dk, 3)
    line(d, (2, 26), (19, 9), stripe, 2)
    # lightning bolt (top)
    rect(d, 11, 3, 13, 4, GOLD)
    rect(d, 9, 5, 11, 6, GOLD)
    rect(d, 11, 7, 12, 8, GOLD)
    # boxing glove (center)
    rect(d, 6, 12, 15, 19, GLOVE)
    rect(d, 6, 17, 15, 19, GLOVE_SH)
    rect(d, 14, 14, 16, 18, GLOVE)                      # thumb
    rect(d, 7, 13, 8, 14, WHITE)                        # glint
    rect(d, 6, 20, 15, 21, GOLD)                        # wrist band
    # star pips (bottom)
    for px_ in (5, 10, 15):
        rect(d, px_, 24, px_ + 1, 25, GOLD)
    return img


def gen_cards():
    for kind in ("white", "black", "spent"):
        draw_card(kind).save(os.path.join(OUTDIR, f"card_{kind}.png"))


# -------------------------------------------------------------- board tiles --
def gen_tiles():
    specs = {
        "tile_light": ((236, 216, 176, 255), (218, 194, 150, 255), (246, 232, 200, 255)),
        "tile_dark": ((148, 96, 62, 255), (124, 76, 48, 255), (168, 116, 80, 255)),
    }
    for name, (base_c, grain, hi) in specs.items():
        img = new(24, 24)
        d = ImageDraw.Draw(img)
        rect(d, 0, 0, 23, 23, base_c)
        for gy in (4, 9, 15, 20):                       # wood grain
            gx0 = random.randint(0, 6)
            gx1 = random.randint(16, 23)
            rect(d, gx0, gy, gx1, gy, grain)
        for _ in range(10):
            x, y = random.randint(0, 23), random.randint(0, 23)
            rect(d, x, y, x, y, grain)
        rect(d, 0, 0, 23, 0, hi)
        rect(d, 0, 0, 0, 23, hi)
        rect(d, 0, 23, 23, 23, grain)
        rect(d, 23, 0, 23, 23, grain)
        img.save(os.path.join(OUTDIR, f"{name}.png"))


# --------------------------------------------------------------- pixel font --
GLYPHS = {
    "C": [" ###.", "#...#", "#....", "#....", "#....", "#...#", " ### "],
    "O": [" ### ", "#...#", "#...#", "#...#", "#...#", "#...#", " ### "],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "B": ["#### ", "#...#", "#...#", "#### ", "#...#", "#...#", "#### "],
    "A": [" ### ", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "E": ["#####", "#....", "#....", "#### ", "#....", "#....", "#####"],
    "S": [" ####", "#....", "#....", " ### ", "....#", "....#", "#### "],
    "V": ["#...#", "#...#", "#...#", "#...#", "#...#", " #.# ", "  #  "],
    "K": ["#...#", "#..# ", "#.#  ", "##   ", "#.#  ", "#..# ", "#...#"],
    "F": ["#####", "#....", "#....", "#### ", "#....", "#....", "#...."],
    "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    "G": [" ####", "#....", "#....", "#..##", "#...#", "#...#", " ### "],
    "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
    ".": [".....", ".....", ".....", ".....", ".....", ".....", "..#.."],
    " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}


def render_text(text, scale, top_color, bottom_color):
    gw = 5 * scale + scale
    w = gw * len(text) + 2
    h = 7 * scale + 2
    img = new(w, h)
    d = ImageDraw.Draw(img)
    for gi, ch in enumerate(text):
        glyph = GLYPHS.get(ch.upper())
        if glyph is None:
            continue
        for gy, row in enumerate(glyph):
            t = gy / 6.0
            col = tuple(int(top_color[i] + (bottom_color[i] - top_color[i]) * t)
                        for i in range(3)) + (255,)
            for gx, c in enumerate(row):
                if c == "#":
                    x0 = 1 + gi * gw + gx * scale
                    y0 = 1 + gy * scale
                    rect(d, x0, y0, x0 + scale - 1, y0 + scale - 1, col)
    return auto_outline(img)


def gen_text_art():
    gold_top, gold_bot = (255, 214, 92), (214, 110, 20)
    red_top, red_bot = (255, 110, 90), (170, 20, 40)
    render_text("COMBAT", 4, gold_top, gold_bot).save(os.path.join(OUTDIR, "logo_combat.png"))
    render_text("CHESS", 4, red_top, red_bot).save(os.path.join(OUTDIR, "logo_chess.png"))
    render_text("VS", 5, gold_top, gold_bot).save(os.path.join(OUTDIR, "text_vs.png"))
    render_text("FIGHT!", 4, gold_top, gold_bot).save(os.path.join(OUTDIR, "text_fight.png"))
    render_text("K.O.!", 4, red_top, red_bot).save(os.path.join(OUTDIR, "text_ko.png"))


# -------------------------------------------------------------- backgrounds --
BW, BH = 360, 640


def vgrad(d, y0, y1, c0, c1, bands=10):
    """Posterized gradient with dithered band seams (SF2 sky treatment)."""
    span = y1 - y0
    cols = []
    for b in range(bands):
        t = b / max(1, bands - 1)
        cols.append(tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)) + (255,))
    for b in range(bands):
        rect(d, 0, y0 + span * b // bands, BW - 1, y0 + span * (b + 1) // bands - 1, cols[b])
    for b in range(1, bands):
        ys = y0 + span * b // bands
        for x in range(BW):
            if (x + ys) % 2 == 0 and ys - 1 >= y0:
                rect(d, x, ys - 1, x, ys - 1, cols[b])
            elif ys + 1 <= y1:
                rect(d, x, ys, x, ys, cols[b - 1])


def speckle(d, y0, y1, color, n):
    """Ground/sand texture noise."""
    for _ in range(n):
        x = random.randint(0, BW - 1)
        y = random.randint(y0, y1)
        rect(d, x, y, x + random.randint(0, 1), y, color)


def stars(d, y_max, n=60):
    for _ in range(n):
        x, y = random.randint(0, BW - 1), random.randint(0, y_max)
        c = (255, 255, 240, 255) if random.random() < 0.3 else (180, 180, 214, 255)
        rect(d, x, y, x, y, c)


def moon(d, x, y, r, base=(250, 240, 214, 255), shade=(224, 210, 178, 255)):
    d.ellipse([x - r, y - r, x + r, y + r], fill=base)
    d.ellipse([x - r // 2, y - r // 3, x - r // 6, y], fill=shade)
    d.ellipse([x + r // 6, y + r // 4, x + r // 2, y + r // 2 + r // 6], fill=shade)


def crowd_row(d, y, n, dark, lit_chance=0.2):
    """Row of tinted onlookers with varied outfits (SF2 stage crowds)."""
    outfits = [(150, 84, 56), (76, 104, 158), (140, 122, 64),
               (100, 72, 118), (72, 124, 92), (156, 70, 70)]
    skin_dim = (150, 118, 92, 255)
    x = random.randint(-6, 4)
    while x < BW:
        w = random.randint(8, 12)
        h = random.randint(14, 22)
        col = random.choice(outfits) + (255,)
        d.ellipse([x, y - h, x + w, y - h + 9], fill=skin_dim)         # head
        rect(d, x - 1, y - h + 8, x + w + 1, y, col)                   # body
        rect(d, x - 1, y - h + 8, x, y, tuple(int(c * 0.7) for c in col[:3]) + (255,))
        if random.random() < 0.3:                                      # raised arm
            rect(d, x + w, y - h + 2, x + w + 1, y - h + 9, skin_dim)
        x += w + random.randint(2, 5)


def bg_rooftop():
    img = new(BW, BH)
    d = ImageDraw.Draw(img)
    vgrad(d, 0, 400, (40, 22, 68), (240, 116, 60), bands=14)
    stars(d, 180)
    moon(d, 284, 84, 20)
    # cloud strips
    for cy in (140, 190, 230):
        cx_ = random.randint(10, 200)
        rect(d, cx_, cy, cx_ + random.randint(60, 130), cy + 3, (150, 80, 100, 255))
    # far skyline
    x = 0
    while x < BW:
        w = random.randint(20, 44)
        h = random.randint(40, 110)
        rect(d, x, 400 - h, x + w, 400, (48, 30, 76, 255))
        x += w + random.randint(2, 6)
    # near buildings + windows
    x = -12
    while x < BW:
        w = random.randint(40, 70)
        h = random.randint(80, 160)
        rect(d, x, 400 - h, x + w, 400, (24, 16, 44, 255))
        for _ in range(w * h // 130):
            wx = random.randint(x + 4, x + w - 4)
            wy = random.randint(400 - h + 5, 392)
            if 0 <= wx < BW:
                rect(d, wx, wy, wx + 1, wy + 1, (255, 202, 92, 255))
        x += w + random.randint(5, 12)
    # neon "KO" sign
    ko = render_text("KO", 3, (255, 120, 220), (200, 40, 160))
    img.alpha_composite(ko, (250, 306))
    d = ImageDraw.Draw(img)
    rect(d, 246, 302, 250 + ko.width, 306 + ko.height + 2, (0, 0, 0, 0))  # noop keep
    # antenna + water tower silhouettes
    rect(d, 30, 330, 33, 400, (16, 10, 30, 255))
    line(d, (31, 330), (18, 352), (16, 10, 30, 255), 2)
    line(d, (31, 330), (46, 352), (16, 10, 30, 255), 2)
    rect(d, 300, 352, 340, 384, (16, 10, 30, 255))
    rect(d, 306, 384, 310, 400, (16, 10, 30, 255))
    rect(d, 330, 384, 334, 400, (16, 10, 30, 255))
    # parapet + floor
    rect(d, 0, 396, BW - 1, 412, (88, 62, 110, 255))
    rect(d, 0, 396, BW - 1, 399, (118, 88, 140, 255))
    vgrad(d, 413, BH, (60, 44, 82), (32, 22, 48), bands=8)
    speckle(d, 416, BH - 1, (74, 56, 98, 255), 220)
    speckle(d, 416, BH - 1, (24, 16, 38, 255), 160)
    for gy in range(436, BH, 38):
        rect(d, 0, gy, BW - 1, gy, (26, 18, 42, 255))
    # roof vents
    rect(d, 20, 420, 52, 434, (44, 32, 62, 255))
    rect(d, 20, 420, 52, 423, (70, 52, 92, 255))
    rect(d, 312, 424, 344, 438, (44, 32, 62, 255))
    rect(d, 312, 424, 344, 427, (70, 52, 92, 255))
    return img


def bg_dojo():
    img = new(BW, BH)
    d = ImageDraw.Draw(img)
    vgrad(d, 0, 400, (160, 112, 74), (126, 84, 54), bands=8)
    # wall beams
    for y in (70, 200, 336):
        rect(d, 0, y, BW - 1, y + 8, (94, 60, 38, 255))
        rect(d, 0, y, BW - 1, y + 1, (116, 78, 50, 255))
    for x in (20, 168, 318):
        rect(d, x, 0, x + 12, 404, (86, 54, 34, 255))
        rect(d, x, 0, x + 3, 404, (110, 72, 46, 255))
    # round window with frame
    d.ellipse([150, 14, 210, 66], fill=(240, 206, 132, 255))
    rect(d, 150, 38, 210, 41, (94, 60, 38, 255))
    rect(d, 178, 14, 181, 66, (94, 60, 38, 255))
    # banners
    for bx, col in ((64, (200, 56, 50, 255)), (238, (58, 96, 200, 255))):
        rect(d, bx, 90, bx + 38, 190, col)
        rect(d, bx, 90, bx + 6, 190, tuple(int(c * 0.7) for c in col[:3]) + (255,))
        rect(d, bx - 3, 84, bx + 41, 90, (226, 190, 100, 255))
        rect(d, bx + 16, 190, bx + 22, 202, (226, 190, 100, 255))
    # weapon rack
    rect(d, 120, 240, 250, 246, (86, 54, 34, 255))
    line(d, (130, 214), (240, 238), (150, 116, 70, 255), 4)     # staff
    line(d, (130, 238), (240, 214), (120, 90, 56, 255), 4)      # staff 2
    # lanterns
    for lx in (44, 306):
        rect(d, lx, 110, lx + 1, 122, (60, 40, 26, 255))
        rect(d, lx - 7, 122, lx + 8, 146, (244, 150, 60, 255))
        rect(d, lx - 7, 130, lx + 8, 132, (200, 100, 40, 255))
        rect(d, lx - 4, 146, lx + 5, 150, (60, 40, 26, 255))
    # crowd on the back porch
    crowd_row(d, 400, 20, (70, 44, 30, 255))
    # floor: tatami
    rect(d, 0, 400, BW - 1, 416, (72, 48, 32, 255))
    vgrad(d, 417, BH, (122, 142, 84), (86, 106, 60), bands=6)
    speckle(d, 420, BH - 1, (140, 160, 98, 255), 260)
    speckle(d, 420, BH - 1, (66, 84, 46, 255), 200)
    for gy in range(444, BH, 36):
        rect(d, 0, gy, BW - 1, gy, (70, 88, 48, 255))
    for gx in range(0, BW, 90):
        rect(d, gx, 417, gx + 1, BH - 1, (70, 88, 48, 255))
    return img


def bg_throne():
    img = new(BW, BH)
    d = ImageDraw.Draw(img)
    vgrad(d, 0, 410, (70, 50, 102), (42, 30, 64), bands=8)
    # brick pattern
    for y in range(24, 400, 26):
        rect(d, 0, y, BW - 1, y, (54, 38, 80, 255))
        off = 20 if (y // 26) % 2 else 0
        for x in range(off, BW, 40):
            rect(d, x, y - 26, x, y, (54, 38, 80, 255))
    # stained-glass window behind throne
    d.ellipse([148, 40, 212, 104], fill=(90, 60, 130, 255))
    for i, col in enumerate(((214, 80, 90, 255), (86, 130, 220, 255), (240, 190, 80, 255))):
        d.ellipse([158 + i * 8, 52 + i * 6, 202 - i * 8, 96 - i * 6], fill=col)
    rect(d, 178, 40, 181, 104, (46, 30, 70, 255))
    rect(d, 148, 70, 212, 73, (46, 30, 70, 255))
    # chandelier
    rect(d, 176, 0, 179, 20, (40, 30, 56, 255))
    rect(d, 150, 20, 206, 26, (120, 96, 50, 255))
    for cx_ in (154, 176, 198):
        rect(d, cx_, 12, cx_ + 3, 20, (255, 200, 80, 255))
    # columns + torches
    for x in (22, 306):
        rect(d, x, 40, x + 28, 408, (112, 102, 144, 255))
        rect(d, x, 40, x + 6, 408, (88, 78, 114, 255))
        rect(d, x + 24, 40, x + 28, 408, (134, 124, 164, 255))
        rect(d, x - 4, 32, x + 32, 42, (134, 124, 164, 255))
        for by in range(80, 400, 60):
            rect(d, x + 6, by, x + 22, by + 1, (88, 78, 114, 255))
        tx = x + 14
        rect(d, tx - 2, 128, tx + 3, 146, (94, 62, 40, 255))
        rect(d, tx - 4, 110, tx + 5, 128, (255, 120, 30, 255))
        rect(d, tx - 2, 102, tx + 3, 118, (255, 190, 60, 255))
        rect(d, tx, 96, tx + 1, 106, (255, 235, 140, 255))
    # throne
    rect(d, 130, 180, 230, 404, (32, 22, 50, 255))
    rect(d, 118, 210, 130, 404, (32, 22, 50, 255))
    rect(d, 230, 210, 242, 404, (32, 22, 50, 255))
    for bx in (130, 172, 214):
        rect(d, bx, 164, bx + 10, 184, (32, 22, 50, 255))
    rect(d, 138, 188, 222, 192, (120, 96, 50, 255))              # gold trim
    rect(d, 142, 220, 218, 300, (60, 30, 66, 255))               # cushion
    # floor + carpet
    vgrad(d, 404, BH, (58, 48, 84), (36, 28, 52), bands=6)
    speckle(d, 408, BH - 1, (76, 64, 104, 255), 200)
    speckle(d, 408, BH - 1, (28, 22, 44, 255), 150)
    for i, y in enumerate(range(404, BH)):
        t = (y - 404) / (BH - 404)
        half = int(38 + t * 130)
        rect(d, 180 - half, y, 180 + half, y, (156, 34, 46, 255))
        rect(d, 180 - half, y, 180 - half + 4, y, (208, 162, 62, 255))
        rect(d, 180 + half - 4, y, 180 + half, y, (208, 162, 62, 255))
        if i % 24 == 0:
            rect(d, 180 - half + 4, y, 180 + half - 4, y, (128, 26, 38, 255))
    return img


def bg_title():
    img = new(BW, BH)
    d = ImageDraw.Draw(img)
    vgrad(d, 0, 460, (12, 8, 36), (70, 26, 84), bands=12)
    stars(d, 340, n=110)
    moon(d, 268, 120, 46, (242, 232, 208, 255), (216, 204, 176, 255))
    # clouds
    for cy in (200, 250):
        cx_ = random.randint(0, 160)
        rect(d, cx_, cy, cx_ + random.randint(80, 160), cy + 4, (54, 30, 74, 255))
    # castle on hill
    rect(d, 0, 410, BW - 1, 460, (20, 12, 34, 255))
    rect(d, 56, 320, 306, 440, (20, 12, 34, 255))
    for tx in (36, 130, 226, 292):
        rect(d, tx, 268, tx + 32, 440, (20, 12, 34, 255))
        for mx in range(tx, tx + 32, 10):
            rect(d, mx, 258, mx + 5, 272, (20, 12, 34, 255))
        rect(d, tx + 10, 244, tx + 22, 268, (20, 12, 34, 255))   # spire base
        line(d, (tx + 16, 226), (tx + 16, 244), (20, 12, 34, 255), 3)
        rect(d, tx + 15, 222, tx + 17, 227, (216, 60, 70, 255))  # pennant
    for _ in range(22):
        wx = random.randint(60, 300)
        wy = random.randint(300, 420)
        rect(d, wx, wy, wx + 1, wy + 3, (255, 202, 92, 255))
    # dueling silhouettes on the foreground cliff
    vgrad(d, 460, BH, (26, 18, 44), (12, 8, 22), bands=6)
    sil = (8, 5, 16, 255)
    line(d, (96, 512), (110, 484), sil, 6)                       # fighter A
    d.ellipse([104, 466, 122, 484], fill=sil)
    line(d, (112, 490), (140, 482), sil, 5)
    line(d, (250, 512), (238, 484), sil, 6)                      # fighter B
    d.ellipse([226, 466, 244, 484], fill=sil)
    line(d, (236, 490), (208, 482), sil, 5)
    for gy in range(520, BH, 26):
        rect(d, 0, gy, BW - 1, gy, (8, 5, 16, 255))
    return img


def gen_backgrounds():
    bg_dojo().save(os.path.join(OUTDIR, "bg_dojo.png"))
    bg_rooftop().save(os.path.join(OUTDIR, "bg_rooftop.png"))
    bg_throne().save(os.path.join(OUTDIR, "bg_throne.png"))
    bg_title().save(os.path.join(OUTDIR, "bg_title.png"))




# ---------------------------------------------------------------- app icon --
def gen_app_icon():
    """1024px App Store icon: outlined pixel knight + boxing glove on a dusk
    gradient. Drawn on a 64px grid, nearest-upscaled 16x. Fully opaque."""
    G = 64
    img = Image.new("RGBA", (G, G), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)

    # dusk gradient with dithered seams
    bands = [(28, 16, 58), (52, 24, 82), (82, 32, 100), (118, 42, 108),
             (156, 56, 100), (196, 76, 84), (224, 96, 66), (240, 116, 56)]
    bh = G // len(bands)
    for i, c in enumerate(bands):
        rect(d, 0, i * bh, G - 1, (i + 1) * bh - 1, c + (255,))
        if i > 0:
            for x in range(G):
                if (x + i) % 2 == 0:
                    rect(d, x, i * bh, x, i * bh, bands[i - 1] + (255,))
    for sx, sy in ((6, 4), (18, 8), (30, 3), (44, 6), (56, 10), (10, 14), (52, 14)):
        rect(d, sx, sy, sx, sy, (255, 244, 214, 255))

    # ring floor + shadow
    d.ellipse([2, 46, 62, 62], fill=(40, 22, 52, 255))
    d.ellipse([6, 48, 58, 58], fill=(64, 36, 74, 255))
    d.ellipse([8, 50, 56, 60], fill=(34, 18, 46, 255))

    # ---- foreground on its own layer for the signature dark outline
    fg = new(G, G)
    fd = ImageDraw.Draw(fg)
    body = (246, 240, 226, 255)
    shade = (204, 192, 168, 255)
    hi = (255, 255, 255, 255)

    # staunton knight
    rect(fd, 16, 14, 30, 40, body)             # head/neck mass
    rect(fd, 16, 14, 19, 40, shade)
    rect(fd, 30, 16, 40, 24, body)             # muzzle
    rect(fd, 30, 22, 40, 24, shade)
    rect(fd, 17, 8, 22, 14, body)              # ear
    rect(fd, 24, 8, 29, 14, body)              # ear 2
    rect(fd, 12, 20, 16, 44, body)             # mane/chest
    rect(fd, 12, 20, 13, 44, shade)
    rect(fd, 14, 40, 34, 48, body)             # collar
    rect(fd, 14, 46, 34, 48, shade)
    rect(fd, 10, 49, 38, 54, body)             # base
    rect(fd, 10, 52, 38, 54, shade)
    rect(fd, 31, 18, 33, 20, (36, 28, 44, 255))    # eye
    rect(fd, 21, 10, 22, 12, hi)               # ear glint
    rect(fd, 22, 16, 24, 18, hi)               # brow glint

    # red boxing glove: raised fist, thumb, knuckle crease, wrist band
    glove = (214, 58, 48, 255)
    glove_hi = (238, 96, 78, 255)
    glove_sh = (148, 34, 30, 255)
    fd.ellipse([40, 20, 60, 38], fill=glove)        # fist
    fd.ellipse([42, 22, 54, 30], fill=glove_hi)     # top light
    rect(fd, 40, 33, 60, 38, glove_sh)              # under shade
    rect(fd, 42, 30, 58, 31, glove_sh)              # knuckle crease
    fd.ellipse([37, 27, 45, 36], fill=glove)        # thumb
    fd.ellipse([38, 28, 42, 32], fill=glove_hi)
    rect(fd, 45, 38, 55, 43, GOLD)                  # wrist band
    rect(fd, 45, 42, 55, 43, GOLD_SH)
    rect(fd, 44, 23, 46, 24, hi)                    # glint

    auto_outline(fg)
    img.alpha_composite(fg)
    d = ImageDraw.Draw(img)

    # impact spark + speed lines (over the outline, off the knight)
    rect(d, 61, 16, 61, 16, hi)
    rect(d, 60, 15, 62, 15, (255, 220, 120, 255))
    rect(d, 60, 17, 62, 17, (255, 220, 120, 255))
    rect(d, 61, 14, 61, 18, (255, 220, 120, 255))
    for lx in (47, 51, 55):
        rect(d, lx, 46, lx, 50, (255, 244, 214, 255))

    icon = img.resize((1024, 1024), Image.NEAREST).convert("RGB")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "CombatChess", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    icon.save(out)


# ------------------------------------------------------------ contact sheet --
def contact_sheet():
    cell = 96 * 2
    sheet = Image.new("RGBA", (cell * len(FRAMES), cell * len(PIECES)), (40, 34, 52, 255))
    for pi, piece in enumerate(PIECES):
        for fi, frame in enumerate(FRAMES):
            img = Image.open(os.path.join(OUTDIR, f"fighter_{piece}_white_{frame}.png"))
            sheet.alpha_composite(img.resize((cell, cell), Image.NEAREST), (fi * cell, pi * cell))
    root = os.path.dirname(os.path.abspath(__file__))
    sheet.save(os.path.join(root, "..", "contact_fighters.png")
               if root.endswith("CombatChess") else os.path.join(root, "contact_fighters.png"))


if __name__ == "__main__":
    gen_fighters()
    gen_icons()
    gen_cards()
    gen_tiles()
    gen_text_art()
    gen_backgrounds()
    gen_app_icon()
    contact_sheet()
    n = len([f for f in os.listdir(OUTDIR) if f.endswith(".png")])
    print(f"Generated {n} PNGs into {OUTDIR}")
