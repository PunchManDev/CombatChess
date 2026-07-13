#!/usr/bin/env python3
"""App Store screenshot generator — iPhone 6.9" (1320x2868).

Composites 10 marketing screenshots from the game's real PixelAssets and the
actual in-app UI layouts (Arcade palette), with headline captions. Run from
the repo root after pixelgen.py has produced the assets.
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "CombatChess", "PixelAssets")
OUT = os.path.join(HERE, "..", "appstore_screens")
os.makedirs(OUT, exist_ok=True)

W, H = 1320, 2868

# ---- Arcade palette (mirrors PixelKit.swift)
BG = (23, 18, 33)
PANEL = (33, 26, 48)
GOLD = (245, 186, 38)
RED = (232, 66, 71)
BLUE = (71, 122, 245)
CREAM = (245, 240, 230)
GREEN = (90, 214, 120)
TEAL = (64, 230, 180)

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


def font(size, mono=False):
    return ImageFont.truetype(MONO if mono else FONT, size)


def load(name):
    return Image.open(os.path.join(ASSETS, f"{name}.png")).convert("RGBA")


def paste(canvas, asset, cx, cy, scale, mirror=False, anchor="center"):
    """Nearest-neighbor scale a pixel asset and paste centered at (cx, cy)."""
    img = asset
    if mirror:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    w, h = img.size
    img = img.resize((w * scale, h * scale), Image.NEAREST)
    w, h = img.size
    if anchor == "center":
        pos = (cx - w // 2, cy - h // 2)
    elif anchor == "bottom":
        pos = (cx - w // 2, cy - h)
    else:
        pos = (cx, cy)
    canvas.alpha_composite(img, pos)


def vgrad(d, x0, y0, x1, y1, c0, c1):
    span = max(1, y1 - y0)
    for y in range(y0, y1):
        t = (y - y0) / span
        c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)) + (255,)
        d.line([(x0, y), (x1, y)], fill=c)


def bg_fill(canvas, name, dim=0.0, y_shift=0):
    """Aspect-fill a stage background across the whole canvas."""
    bg = load(name)
    scale = max(W / bg.width, H / bg.height) + 0.001
    bg = bg.resize((int(bg.width * scale), int(bg.height * scale)), Image.NEAREST)
    canvas.alpha_composite(bg, ((W - bg.width) // 2, (H - bg.height) // 2 + y_shift))
    if dim > 0:
        ov = Image.new("RGBA", (W, H), (8, 5, 16, int(255 * dim)))
        canvas.alpha_composite(ov)


def text(d, s, x, y, f, fill, anchor="mm", shadow=True, tracking=0):
    if tracking and anchor in ("mm", "ma", "ms"):
        # manual letter spacing, centered
        widths = [d.textlength(ch, font=f) + tracking for ch in s]
        total = sum(widths) - tracking
        cx = x - total / 2
        for ch, wch in zip(s, widths):
            if shadow:
                d.text((cx + 3, y + 3), ch, font=f, fill=(0, 0, 0, 200), anchor="lm")
            d.text((cx, y), ch, font=f, fill=fill, anchor="lm")
            cx += wch
        return
    if shadow:
        d.text((x + 3, y + 3), s, font=f, fill=(0, 0, 0, 200), anchor=anchor)
    d.text((x, y), s, font=f, fill=fill, anchor=anchor)


def fit_font(s, maxw, start=112, tracking=2, mono=False):
    """Largest font size whose tracked width fits maxw."""
    size = start
    while size > 40:
        f = font(size, mono)
        dummy = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
        w = sum(dummy.textlength(ch, font=f) + tracking for ch in s) - tracking
        if w <= maxw:
            return f, size
        size -= 4
    return font(40, mono), 40


def caption(d, headline, sub, color=GOLD, y=150):
    """Top marketing caption band — headline auto-fits the screen width."""
    f, size = fit_font(headline, W - 120, start=112, tracking=2)
    text(d, headline, W // 2, y, f, color, tracking=2)
    if sub:
        sf, _ = fit_font(sub, W - 140, start=58, tracking=0)
        text(d, sub, W // 2, y + max(96, size + 24), sf, CREAM)


def panel_box(d, x0, y0, x1, y1, border=GOLD, fill=PANEL, alpha=250, lw=6):
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.rectangle([x0, y0, x1, y1], fill=fill + (alpha,))
    return ov, od


def bar(d, x, y, w, h, frac, color, back=(90, 24, 26)):
    d.rectangle([x, y, x + w, y + h], fill=back + (255,))
    d.rectangle([x, y, x + int(w * frac), y + h], fill=color + (255,))
    d.rectangle([x, y, x + w, y + h], outline=(245, 245, 245, 255), width=4)


def phone_frame(canvas):
    """Subtle rounded vignette so it reads as a screen."""
    pass


# ============================================================ screens =======

def draw_hud_bars(d, y, player_hp, ai_hp, player_stam, ai_stam, ptype, atype, timer):
    bw = int(W * 0.36)
    # player (left)
    bar(d, 40, y, bw, 40, player_hp, GOLD)
    bar(d, 40, y + 46, bw, 18, player_stam, TEAL, back=(40, 40, 40))
    text(d, f"YOU·{ptype}", 40, y + 92, font(34, True), CREAM, anchor="lm", shadow=False)
    # ai (right)
    bar(d, W - 40 - bw, y, bw, 40, ai_hp, GOLD)
    bar(d, W - 40 - bw, y + 46, bw, 18, ai_stam, TEAL, back=(40, 40, 40))
    text(d, f"FOE·{atype}", W - 40, y + 92, font(34, True), CREAM, anchor="rm", shadow=False)
    # timer box
    d.rectangle([W // 2 - 70, y - 6, W // 2 + 70, y + 96], fill=(0, 0, 0, 180), outline=GOLD + (255,), width=5)
    text(d, str(timer), W // 2, y + 45, font(72, True), CREAM)


def fighter_stage(canvas, stage, ptype, atype, pframe, aframe, y_ground):
    bg_fill(canvas, stage, dim=0.12)
    # shadows
    d = ImageDraw.Draw(canvas)
    for x in (int(W * 0.30), int(W * 0.70)):
        d.ellipse([x - 150, y_ground - 24, x + 150, y_ground + 24], fill=(0, 0, 0, 90))
    paste(canvas, load(f"fighter_{ptype}_white_{pframe}"), int(W * 0.30), y_ground, 9, anchor="bottom")
    paste(canvas, load(f"fighter_{atype}_black_{aframe}"), int(W * 0.70), y_ground, 9, mirror=True, anchor="bottom")


def control_deck(d, y0):
    """SF2-style button deck footprint."""
    d.rectangle([0, y0, W, H], fill=(0, 0, 0, 150))
    def btn(x0, yy0, x1, yy1, label, col, bord):
        d.rectangle([x0, yy0, x1, yy1], fill=col + (235,), outline=bord + (255,), width=6)
        text(d, label, (x0 + x1) // 2, (yy0 + yy1) // 2, font(40, True), CREAM)
    pw = (152, 42, 42); pb = (255, 116, 102)
    bw_ = (34, 58, 130); bb = (116, 168, 255)
    dw = (26, 104, 72); db = (90, 242, 154)
    gap = y0 + 40
    btn(40, gap, 380, gap + 150, "L PUNCH", pw, pb)
    btn(40, gap + 170, 380, gap + 320, "L BLOCK", bw_, bb)
    btn(W - 380, gap, W - 40, gap + 150, "R PUNCH", pw, pb)
    btn(W - 380, gap + 170, W - 40, gap + 320, "R BLOCK", bw_, bb)
    btn(40, gap + 340, W - 40, gap + 470, "DODGE", dw, db)


# ---- 01 Title
def s01():
    c = Image.new("RGBA", (W, H), BG + (255,))
    bg_fill(c, "bg_title")
    d = ImageDraw.Draw(c)
    paste(c, load("logo_combat"), W // 2, 560, 11)
    paste(c, load("logo_chess"), W // 2, 760, 11)
    text(c._draw if False else d, "CAPTURE · CHALLENGE · FIGHT", W // 2, 900, font(46), CREAM, tracking=3)
    # marquee fighters
    paste(c, load("fighter_knight_white_punch_l"), int(W * 0.30), 1500, 11)
    paste(c, load("text_vs"), W // 2, 1400, 8)
    paste(c, load("fighter_queen_black_idle_a"), int(W * 0.70), 1500, 11, mirror=True)
    # start button
    d.rectangle([210, 1760, W - 210, 1920], fill=(0, 0, 0, 150), outline=GOLD + (255,), width=8)
    text(d, "▶ START GAME", W // 2, 1840, font(78), GOLD)
    caption(d, "CHESS MEETS COMBAT", "The board game that fights back", y=2350)
    return c


# ---- 02 Board + cards
def s02():
    c = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(c)
    caption(d, "PLAY REAL CHESS", "Full rules. Stockfish opponent.", y=200)
    # opponent HUD
    text(d, "CPU · HARD", 70, 520, font(52, True), RED, anchor="lm")
    for i in range(3):
        paste(c, load("card_black"), 90 + i * 70, 640, 3)
    # board
    board_top = 760
    cell = (W - 120) // 8
    light, dark = load("tile_light"), load("tile_dark")
    # a simple mid-game position
    pos = {
        (0,0):("rook","white"),(4,0):("king","white"),(7,0):("rook","white"),
        (3,1):("pawn","white"),(4,2):("pawn","white"),(2,3):("knight","white"),
        (4,4):("queen","white"),(5,5):("bishop","white"),
        (3,4):("pawn","black"),(4,6):("pawn","black"),(6,5):("knight","black"),
        (0,7):("rook","black"),(4,7):("king","black"),(7,7):("rook","black"),
        (2,6):("queen","black"),
    }
    for row in range(8):
        for col in range(8):
            sq = (col, 7 - row)
            tile = light if (col + (7 - row)) % 2 == 1 else dark
            x = 60 + col * cell
            y = board_top + row * cell
            t = tile.resize((cell, cell), Image.NEAREST)
            c.alpha_composite(t, (x, y))
            if sq in pos:
                pc, cl = pos[sq]
                ic = load(f"icon_{pc}_{cl}").resize((int(cell*0.82), int(cell*0.82)), Image.NEAREST)
                c.alpha_composite(ic, (x + (cell-ic.width)//2, y + (cell-ic.height)//2))
    d.rectangle([60, board_top, 60 + cell*8, board_top + cell*8], outline=GOLD + (255,), width=8)
    # player HUD
    py = board_top + cell*8 + 60
    text(d, "YOU", 70, py, font(56, True), BLUE, anchor="lm")
    for i in range(3):
        paste(c, load("card_white"), 90 + i * 78, py + 130, 4)
    text(d, "ACTION CARDS — SPEND TO FIGHT", 90, py + 260, font(40, True), CREAM, anchor="lm", shadow=False)
    return c


# ---- 03 VS challenge
def s03():
    c = Image.new("RGBA", (W, H), BG + (255,))
    bg_fill(c, "bg_rooftop", dim=0.5)
    d = ImageDraw.Draw(c)
    caption(d, "CONTEST THE CAPTURE", "Don't lose your queen without a fight", y=210)
    paste(c, load("text_vs"), W // 2, 1120, 11)
    paste(c, load("fighter_queen_white_idle_a"), int(W*0.26), 1560, 10, anchor="bottom")
    paste(c, load("fighter_knight_black_idle_a"), int(W*0.74), 1560, 10, mirror=True, anchor="bottom")
    text(d, "YOUR QUEEN", int(W*0.26), 1660, font(48, True), BLUE)
    text(d, "HP 275/275", int(W*0.26), 1730, font(40, True), GREEN)
    text(d, "ENEMY KNIGHT", int(W*0.74), 1660, font(48, True), RED)
    text(d, "HP 125/125", int(W*0.74), 1730, font(40, True), GREEN)
    # buttons
    d.rectangle([120, 1900, 640, 2060], fill=(0,0,0,150), outline=CREAM + (255,), width=6)
    text(d, "CONCEDE", 380, 1980, font(64), CREAM)
    d.rectangle([680, 1900, 1200, 2060], fill=RED + (235,), outline=(255,150,150,255), width=6)
    text(d, "FIGHT!", 940, 1980, font(72), (20,10,10))
    caption(d, "WINNER KEEPS THE SQUARE", "", color=GOLD, y=2350)
    return c


# ---- 04 Fight HUD
def s04():
    c = Image.new("RGBA", (W, H), BG + (255,))
    fighter_stage(c, "bg_dojo", "QUEEN", "KNIGHT", "idle_a", "wind_r", 2050)
    d = ImageDraw.Draw(c)
    draw_hud_bars(d, 360, 0.82, 0.55, 0.9, 0.5, "QUEEN", "KNIGHT", 47)
    text(d, "L ◀ LIGHT", int(W*0.70), 900, font(44, True), TEAL)
    control_deck(d, 2380)
    caption(d, "STREET-FIGHTER COMBAT", "Read the tell. Punch, block, dodge.", y=180)
    return c


# ---- 05 Punch impact
def s05():
    c = Image.new("RGBA", (W, H), BG + (255,))
    fighter_stage(c, "bg_rooftop", "ROOK", "BISHOP", "punch_l", "hit", 2050)
    d = ImageDraw.Draw(c)
    draw_hud_bars(d, 360, 0.7, 0.28, 0.62, 0.4, "ROOK", "BISHOP", 39)
    # impact star + damage
    ix, iy = int(W*0.58), 1500
    text(d, "✦", ix, iy, font(220), (255,255,255))
    text(d, "-52", ix + 120, iy - 120, font(96), GOLD)
    caption(d, "EVERY HIT COUNTS", "Damage carries the whole match", y=180)
    return c


# ---- 06 Block / dodge
def s06():
    c = Image.new("RGBA", (W, H), BG + (255,))
    fighter_stage(c, "bg_throne", "PAWN", "QUEEN", "dodge_b", "punch_r", 2050)
    d = ImageDraw.Draw(c)
    draw_hud_bars(d, 360, 0.6, 0.75, 0.5, 0.7, "PAWN", "QUEEN", 33)
    text(d, "PERFECT DODGE!", W // 2, 1150, font(84), TEAL)
    caption(d, "TIMING IS EVERYTHING", "Dodge clean to charge your Super", y=180)
    return c


# ---- 07 Super / KO
def s07():
    c = Image.new("RGBA", (W, H), BG + (255,))
    fighter_stage(c, "bg_dojo", "KNIGHT", "ROOK", "punch_r", "ko", 2050)
    d = ImageDraw.Draw(c)
    draw_hud_bars(d, 360, 0.75, 0.0, 0.4, 0.0, "KNIGHT", "ROOK", 28)
    paste(c, load("text_ko"), W // 2, 1250, 14)
    text(d, "YOU WIN", W // 2, 1500, font(96), GREEN)
    caption(d, "STAR PUNCH FINISH", "Land the KO, take the piece", y=180)
    return c


# ---- 08 King's last stand
def s08():
    c = Image.new("RGBA", (W, H), BG + (255,))
    fighter_stage(c, "bg_throne", "KING", "QUEEN", "block_l", "wind_r", 2050)
    d = ImageDraw.Draw(c)
    draw_hud_bars(d, 360, 0.95, 0.8, 0.9, 0.7, "KING", "QUEEN", 51)
    text(d, "CHECKMATE!", W // 2, 900, font(96), RED)
    text(d, "THE KING'S LAST STAND", W // 2, 1010, font(52), CREAM)
    caption(d, "NEVER SAY DIE", "Checkmate? Fight your way out", y=180)
    return c


# ---- 09 Difficulty / Elo
def s09():
    c = Image.new("RGBA", (W, H), BG + (255,))
    bg_fill(c, "bg_title", dim=0.35)
    d = ImageDraw.Draw(c)
    caption(d, "POWERED BY STOCKFISH", "Tune the CPU from 600 to 3190 Elo", y=230)
    rows = [("EASY", "900 ELO", GREEN, 0.3), ("MEDIUM", "1600 ELO", GOLD, 0.55), ("HARD", "2400 ELO", RED, 0.8)]
    y = 900
    for name, elo, col, frac in rows:
        d.rectangle([160, y, W - 160, y + 300], fill=(0,0,0,150), outline=col + (255,), width=6)
        text(d, name, 220, y + 90, font(80), col, anchor="lm")
        text(d, elo, W - 220, y + 90, font(72, True), CREAM, anchor="rm")
        bar(d, 220, y + 200, W - 440, 40, frac, col, back=(50,50,50))
        y += 380
    return c


# ---- 10 Online
def s10():
    c = Image.new("RGBA", (W, H), BG + (255,))
    bg_fill(c, "bg_rooftop", dim=0.45)
    d = ImageDraw.Draw(c)
    caption(d, "CHALLENGE YOUR FRIENDS", "Online multiplayer via Game Center", y=220)
    paste(c, load("fighter_king_white_idle_a"), int(W*0.28), 1450, 12, anchor="bottom")
    paste(c, load("text_vs"), W // 2, 1150, 12)
    paste(c, load("fighter_king_black_idle_a"), int(W*0.72), 1450, 12, mirror=True, anchor="bottom")
    text(d, "YOU", int(W*0.28), 1520, font(56, True), BLUE)
    text(d, "A FRIEND", int(W*0.72), 1520, font(56, True), RED)
    d.rectangle([210, 1720, W - 210, 1880], fill=CREAM + (235,), outline=GOLD + (255,), width=8)
    text(d, "INVITE A FRIEND", W // 2, 1800, font(70), (20,15,10))
    caption(d, "OPEN SOURCE · GPLv3", "Free software, built to be shared", color=GOLD, y=2250)
    return c


SCREENS = [s01, s02, s03, s04, s05, s06, s07, s08, s09, s10]

if __name__ == "__main__":
    for i, fn in enumerate(SCREENS, 1):
        img = fn().convert("RGB")
        img.save(os.path.join(OUT, f"screenshot_{i:02d}.png"))
    print(f"Generated {len(SCREENS)} screenshots ({W}x{H}) into {OUT}")
