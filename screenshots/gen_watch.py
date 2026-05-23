#!/usr/bin/env python3
"""
Generate 3 Apple Watch App Store screenshots for SimpleTracking
at 410x502 (Apple Watch Ultra 49mm, accepted by App Store Connect).

Screens mirror the actual watch UI in SimpleTrackingWatch/Views:
  1. Workout type list  (WatchMainView)
  2. Active run         (WatchActiveWorkoutView, mid-run state)
  3. Active cycling     (same view, paused state)
"""
from PIL import Image, ImageDraw, ImageFont
import math
import os

W, H = 410, 502
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

SF = "/System/Library/Fonts/SFNS.ttf"
SF_ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"

# watchOS dark palette
BG = (0, 0, 0)
CARD = (28, 28, 30)
ACCENT = (255, 95, 31)           # SimpleTracking orange
GREEN = (52, 199, 89)
BLUE = (10, 132, 255)
YELLOW = (255, 204, 0)
RED = (255, 69, 58)
PINK = (255, 55, 95)
TEXT = (255, 255, 255)
TEXT_SECONDARY = (174, 174, 178)
SEPARATOR = (60, 60, 65)


def f(size):
    return ImageFont.truetype(SF, size)


def fr(size):
    return ImageFont.truetype(SF_ROUNDED, size)


def text_w(draw, s, font):
    bbox = draw.textbbox((0, 0), s, font=font)
    return bbox[2] - bbox[0]


def status_bar(d, time="9:41"):
    """Watch-style time chip top right + small left dot."""
    fnt = fr(20)
    tw = text_w(d, time, fnt)
    d.text((W - tw - 18, 8), time, font=fnt, fill=ACCENT)


def screen_clip(img):
    """Apply rounded-rect mask to mimic Watch screen corners.
    Apple's screenshot specs say submit the rectangular pixel buffer,
    but the rounded look reads as a real watch — corners are masked
    by the device frame in marketing. We keep it rectangular to comply
    with the 410x502 requirement.
    """
    return img


# ----------------------------------------------------------
# Screen 1: Workout type list (WatchMainView)
# ----------------------------------------------------------
def make_main():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    status_bar(d)

    # Nav title
    d.text((18, 36), "SimpleTracking", font=fr(22), fill=TEXT)

    rows = [
        ("figure.run",       "Running",  ACCENT),
        ("bicycle",          "Cycling",  BLUE),
        ("figure.walk",      "Walking",  GREEN),
        ("figure.hiking",    "Hiking",   YELLOW),
        ("figure.pool.swim", "Swimming", PINK),
    ]

    # SF Symbols are not available to PIL; we draw colored glyph circles
    # plus the label, mimicking the Label(systemImage:) layout.
    top = 80
    row_h = 70
    for i, (_sym, name, color) in enumerate(rows):
        y = top + i * row_h
        # Icon disc
        d.rounded_rectangle((18, y + 8, 18 + 44, y + 8 + 44), radius=10, fill=color)
        # Symbol stand-in: a clean white pictogram per row
        draw_pictogram(d, name, 18 + 22, y + 8 + 22, color=(255, 255, 255))
        # Label
        d.text((78, y + 18), name, font=fr(22), fill=TEXT)
        # Separator
        if i < len(rows) - 1:
            d.line((78, y + row_h, W - 18, y + row_h), fill=SEPARATOR, width=1)

    img.save(os.path.join(OUT_DIR, "watch_01_workouts.png"))
    print("wrote watch_01_workouts.png")


def draw_pictogram(d, name, cx, cy, color=(255, 255, 255)):
    """Tiny vector glyphs for each workout type — readable at 44px."""
    if name == "Running":
        # Stickfigure mid-stride
        d.ellipse((cx - 3, cy - 14, cx + 3, cy - 8), fill=color)  # head
        d.line((cx, cy - 7, cx + 4, cy + 2), fill=color, width=2)  # torso
        d.line((cx + 4, cy + 2, cx + 9, cy + 9), fill=color, width=2)  # back leg
        d.line((cx + 4, cy + 2, cx - 4, cy + 9), fill=color, width=2)  # front leg
        d.line((cx + 1, cy - 5, cx - 6, cy - 2), fill=color, width=2)  # back arm
        d.line((cx + 3, cy - 4, cx + 9, cy - 1), fill=color, width=2)  # front arm
    elif name == "Cycling":
        # Two wheels + frame
        d.ellipse((cx - 13, cy + 1, cx - 3, cy + 11), outline=color, width=2)
        d.ellipse((cx + 3, cy + 1, cx + 13, cy + 11), outline=color, width=2)
        d.line((cx - 8, cy + 6, cx, cy - 2), fill=color, width=2)
        d.line((cx, cy - 2, cx + 8, cy + 6), fill=color, width=2)
        d.line((cx - 2, cy - 2, cx + 4, cy - 2), fill=color, width=2)  # handlebar
        d.ellipse((cx - 1, cy - 8, cx + 5, cy - 2), fill=color)  # rider head
    elif name == "Walking":
        d.ellipse((cx - 3, cy - 14, cx + 3, cy - 8), fill=color)
        d.line((cx, cy - 7, cx, cy + 3), fill=color, width=2)
        d.line((cx, cy + 3, cx + 5, cy + 10), fill=color, width=2)
        d.line((cx, cy + 3, cx - 4, cy + 10), fill=color, width=2)
        d.line((cx, cy - 4, cx - 5, cy - 1), fill=color, width=2)
    elif name == "Hiking":
        d.ellipse((cx - 3, cy - 14, cx + 3, cy - 8), fill=color)
        d.line((cx, cy - 7, cx + 3, cy + 2), fill=color, width=2)
        d.line((cx + 3, cy + 2, cx + 8, cy + 9), fill=color, width=2)
        d.line((cx + 3, cy + 2, cx - 3, cy + 10), fill=color, width=2)
        d.line((cx - 6, cy - 10, cx - 6, cy + 11), fill=color, width=2)  # walking stick
    elif name == "Swimming":
        # Wavy lines
        for j, oy in enumerate((-4, 2, 8)):
            pts = []
            for i in range(0, 26):
                x = cx - 13 + i
                y = cy + oy + int(2 * math.sin((i + j * 2) * 0.7))
                pts.append((x, y))
            d.line(pts, fill=color, width=2)


# ----------------------------------------------------------
# Screen 2: Active running workout (mid-run)
# ----------------------------------------------------------
def make_active_run():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    status_bar(d, time="9:41")

    # Header: workout icon + elapsed
    d.text((22, 38), "Running", font=fr(18), fill=TEXT_SECONDARY)
    # Elapsed time — big monospaced
    elapsed = "32:18"
    fnt_time = fr(64)
    tw = text_w(d, elapsed, fnt_time)
    d.text(((W - tw) // 2, 70), elapsed, font=fnt_time, fill=TEXT)

    # Divider
    d.line((22, 152, W - 22, 152), fill=SEPARATOR, width=1)

    # Distance — primary metric
    fnt_dist = fr(56)
    dist = "5.42"
    dw = text_w(d, dist, fnt_dist)
    d.text(((W - dw) // 2 - 22, 168), dist, font=fnt_dist, fill=TEXT)
    d.text(((W - dw) // 2 + dw - 18, 198), "km", font=fr(22), fill=TEXT_SECONDARY)

    # Three-column metric row
    row_y = 268
    metrics = [
        ("412",  "kcal",   ACCENT),
        ("164",  "bpm",    PINK),
        ("5:57", "/km",    BLUE),
    ]
    col_w = W / 3
    for i, (val, unit, color) in enumerate(metrics):
        cx = int(col_w * (i + 0.5))
        fnt_v = fr(26)
        vw = text_w(d, val, fnt_v)
        d.text((cx - vw // 2, row_y), val, font=fnt_v, fill=color)
        fnt_u = fr(16)
        uw = text_w(d, unit, fnt_u)
        d.text((cx - uw // 2, row_y + 34), unit, font=fnt_u, fill=TEXT_SECONDARY)

    # Pause/Stop controls
    btn_y = 380
    # Pause (yellow)
    d.rounded_rectangle((50, btn_y, 50 + 130, btn_y + 70), radius=35, fill=YELLOW)
    # Pause bars
    bcx, bcy = 50 + 65, btn_y + 35
    d.rectangle((bcx - 14, bcy - 16, bcx - 4, bcy + 16), fill=(0, 0, 0))
    d.rectangle((bcx + 4, bcy - 16, bcx + 14, bcy + 16), fill=(0, 0, 0))

    # Stop (red)
    d.rounded_rectangle((W - 50 - 130, btn_y, W - 50, btn_y + 70), radius=35, fill=RED)
    scx, scy = W - 50 - 65, btn_y + 35
    d.rounded_rectangle((scx - 14, scy - 14, scx + 14, scy + 14), radius=3, fill=(255, 255, 255))

    img.save(os.path.join(OUT_DIR, "watch_02_active_run.png"))
    print("wrote watch_02_active_run.png")


# ----------------------------------------------------------
# Screen 3: Active cycling, paused state
# ----------------------------------------------------------
def make_active_cycle_paused():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    status_bar(d, time="9:41")

    # Header
    d.text((22, 38), "Cycling · Paused", font=fr(18), fill=YELLOW)
    elapsed = "1:08:42"
    fnt_time = fr(56)
    tw = text_w(d, elapsed, fnt_time)
    d.text(((W - tw) // 2, 70), elapsed, font=fnt_time, fill=TEXT)

    d.line((22, 148, W - 22, 148), fill=SEPARATOR, width=1)

    # Distance
    fnt_dist = fr(56)
    dist = "24.7"
    dw = text_w(d, dist, fnt_dist)
    d.text(((W - dw) // 2 - 22, 162), dist, font=fnt_dist, fill=TEXT)
    d.text(((W - dw) // 2 + dw - 18, 192), "km", font=fr(22), fill=TEXT_SECONDARY)

    row_y = 262
    metrics = [
        ("687",  "kcal",   ACCENT),
        ("138",  "bpm",    PINK),
        ("2:31", "/km",    BLUE),
    ]
    col_w = W / 3
    for i, (val, unit, color) in enumerate(metrics):
        cx = int(col_w * (i + 0.5))
        fnt_v = fr(26)
        vw = text_w(d, val, fnt_v)
        d.text((cx - vw // 2, row_y), val, font=fnt_v, fill=color)
        fnt_u = fr(16)
        uw = text_w(d, unit, fnt_u)
        d.text((cx - uw // 2, row_y + 34), unit, font=fnt_u, fill=TEXT_SECONDARY)

    # Resume (green play) + Stop (red)
    btn_y = 374
    d.rounded_rectangle((50, btn_y, 50 + 130, btn_y + 70), radius=35, fill=GREEN)
    bcx, bcy = 50 + 65, btn_y + 35
    # Play triangle
    d.polygon([(bcx - 11, bcy - 16), (bcx - 11, bcy + 16), (bcx + 16, bcy)], fill=(0, 0, 0))

    d.rounded_rectangle((W - 50 - 130, btn_y, W - 50, btn_y + 70), radius=35, fill=RED)
    scx, scy = W - 50 - 65, btn_y + 35
    d.rounded_rectangle((scx - 14, scy - 14, scx + 14, scy + 14), radius=3, fill=(255, 255, 255))

    img.save(os.path.join(OUT_DIR, "watch_03_cycle_paused.png"))
    print("wrote watch_03_cycle_paused.png")


if __name__ == "__main__":
    make_main()
    make_active_run()
    make_active_cycle_paused()
