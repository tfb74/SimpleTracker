#!/usr/bin/env python3
"""
Generate 3 App Store screenshots for SimpleTracking at 1284x2778 (6.5" iPhone).
English mockups: Workout route, Food entry, Statistics.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import random
import os

W, H = 1284, 2778
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

SF = "/System/Library/Fonts/SFNS.ttf"
SF_ROUNDED = "/System/Library/Fonts/SFCompactRounded.ttf"

# Color palette - inspired by iOS health/fitness apps
BG = (248, 248, 250)
CARD = (255, 255, 255)
ACCENT = (255, 95, 31)        # SimpleTracking orange
ACCENT_DARK = (220, 70, 10)
GREEN = (52, 199, 89)
BLUE = (10, 132, 255)
PURPLE = (175, 82, 222)
RED = (255, 69, 58)
TEXT = (28, 28, 30)
TEXT_SECONDARY = (99, 99, 102)
SEPARATOR = (220, 220, 224)

def font(size, weight="regular"):
    # SFNS variable font; we just vary size. For bold-ish look use bigger size effect
    return ImageFont.truetype(SF, size)

def font_rounded(size):
    return ImageFont.truetype(SF_ROUNDED, size)

def rounded_rect(draw, bbox, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(bbox, radius=radius, fill=fill, outline=outline, width=width)

def status_bar(draw, dark=False):
    color = (255, 255, 255) if dark else TEXT
    # Time
    f = font(48)
    draw.text((90, 60), "9:41", font=f, fill=color)
    # Signal/wifi/battery (simplified glyphs)
    f2 = font(40)
    draw.text((1050, 70), "•••  ", font=f2, fill=color)
    # Battery rect
    draw.rounded_rectangle((1170, 75, 1240, 100), radius=6, outline=color, width=3)
    draw.rounded_rectangle((1175, 80, 1232, 95), radius=3, fill=color)
    draw.rectangle((1240, 82, 1245, 93), fill=color)

def home_indicator(draw, dark=False):
    color = (255, 255, 255, 180) if dark else (60, 60, 67, 180)
    draw.rounded_rectangle((430, 2720, 854, 2735), radius=8, fill=color[:3])

def header_title(draw, title, subtitle=None, y=180, color=TEXT):
    draw.text((90, y), title, font=font(96), fill=color)
    if subtitle:
        draw.text((90, y + 130), subtitle, font=font(44), fill=TEXT_SECONDARY)

def big_caption(draw, line1, line2, y=2400):
    # Bold marketing caption above home indicator
    draw.text((90, y), line1, font=font_rounded(78), fill=ACCENT)
    if line2:
        draw.text((90, y + 100), line2, font=font(58), fill=TEXT)


# =========================================================
# Screenshot 1: WORKOUT — Map + live stats
# =========================================================
def make_workout():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # --- Map area (top 60%)
    map_top = 0
    map_bottom = 1700
    # Faux map background — gradient + roads
    for y in range(map_top, map_bottom):
        t = (y - map_top) / (map_bottom - map_top)
        r = int(225 + 15 * t)
        g = int(232 + 10 * t)
        b = int(220 + 20 * t)
        d.line((0, y, W, y), fill=(r, g, b))

    # Random road-like lines (light gray) for map texture
    random.seed(7)
    for _ in range(40):
        x1 = random.randint(-100, W + 100)
        y1 = random.randint(map_top, map_bottom)
        x2 = x1 + random.randint(-400, 400)
        y2 = y1 + random.randint(-400, 400)
        d.line((x1, y1, x2, y2), fill=(210, 215, 215), width=random.randint(3, 14))

    # Faux water / park blob
    d.ellipse((-300, 200, 500, 900), fill=(200, 225, 235))
    d.ellipse((900, 1100, 1600, 1650), fill=(205, 225, 200))

    # GPS route — orange polyline (organic curve)
    route_points = []
    cx, cy = 240, 1550
    for i in range(60):
        t = i / 59
        x = 200 + 800 * t + 180 * math.sin(t * 7)
        y = 1500 - 1100 * t + 120 * math.cos(t * 5)
        route_points.append((x, y))
    # Shadow under route
    for w in (32, 26):
        d.line(route_points, fill=(0, 0, 0, 80) if w == 32 else (0, 0, 0, 40), width=w, joint="curve")
    # White underline of route
    d.line(route_points, fill=(255, 255, 255), width=20, joint="curve")
    # Orange route
    d.line(route_points, fill=ACCENT, width=14, joint="curve")
    # Start marker (green)
    sx, sy = route_points[0]
    d.ellipse((sx-32, sy-32, sx+32, sy+32), fill=(255, 255, 255), outline=GREEN, width=8)
    d.ellipse((sx-16, sy-16, sx+16, sy+16), fill=GREEN)
    # Current position (orange pulse)
    ex, ey = route_points[-1]
    d.ellipse((ex-80, ey-80, ex+80, ey+80), fill=(255, 95, 31, 60))
    d.ellipse((ex-44, ey-44, ex+44, ey+44), fill=ACCENT, outline=(255,255,255), width=10)

    status_bar(d, dark=False)

    # --- Top inline header
    d.text((90, 170), "Running", font=font(54), fill=TEXT)
    d.text((90, 240), "Live tracking · GPS", font=font(36), fill=TEXT_SECONDARY)

    # --- Pause/Stop floating buttons over map
    cx_btn = W // 2
    by = 1580
    # Pause (round, gray)
    d.ellipse((cx_btn-220-90, by-90, cx_btn-220+90, by+90), fill=(255,255,255))
    d.rectangle((cx_btn-220-22, by-32, cx_btn-220-8, by+32), fill=TEXT)
    d.rectangle((cx_btn-220+8, by-32, cx_btn-220+22, by+32), fill=TEXT)
    # Stop (round, red)
    d.ellipse((cx_btn+220-90, by-90, cx_btn+220+90, by+90), fill=RED)
    d.rounded_rectangle((cx_btn+220-30, by-30, cx_btn+220+30, by+30), radius=6, fill=(255,255,255))

    # --- Stats card (bottom 40%)
    card_top = 1740
    rounded_rect(d, (0, card_top, W, H), 60, fill=CARD)
    # Drag handle
    d.rounded_rectangle((W//2 - 60, card_top + 30, W//2 + 60, card_top + 40), radius=6, fill=(200,200,205))

    # Big primary stat: Distance
    d.text((90, card_top + 100), "DISTANCE", font=font(36), fill=TEXT_SECONDARY)
    d.text((90, card_top + 145), "5.42", font=font_rounded(200), fill=TEXT)
    d.text((550, card_top + 280), "km", font=font(60), fill=TEXT_SECONDARY)

    # Secondary stats row
    row_y = card_top + 440
    col_w = W // 3
    stats = [
        ("DURATION", "32:18", "min"),
        ("PACE", "5:57", "min/km"),
        ("CALORIES", "412", "kcal"),
    ]
    for i, (label, val, unit) in enumerate(stats):
        x = i * col_w + 50
        d.text((x, row_y), label, font=font(28), fill=TEXT_SECONDARY)
        d.text((x, row_y + 50), val, font=font_rounded(100), fill=TEXT)
        d.text((x, row_y + 170), unit, font=font(32), fill=TEXT_SECONDARY)

    # Elevation row
    row_y2 = row_y + 280
    d.line((90, row_y2 - 30, W - 90, row_y2 - 30), fill=SEPARATOR, width=2)
    stats2 = [
        ("ELEVATION", "+82 m"),
        ("SPEED", "10.1 km/h"),
        ("HEART", "148 bpm"),
    ]
    for i, (label, val) in enumerate(stats2):
        x = i * col_w + 50
        d.text((x, row_y2), label, font=font(28), fill=TEXT_SECONDARY)
        d.text((x, row_y2 + 50), val, font=font_rounded(60), fill=TEXT)

    # Marketing caption
    big_caption(d, "Track every move.", "GPS workouts with live stats and Live Activities.")

    home_indicator(d)
    img.save(os.path.join(OUT_DIR, "01_workout.png"), "PNG", optimize=True)
    print("✓ 01_workout.png")


# =========================================================
# Screenshot 2: FOOD — entry list / nutrition
# =========================================================
def make_food():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    status_bar(d, dark=False)

    # Nav: back + title + add
    d.text((60, 160), "‹  Today", font=font(50), fill=ACCENT)
    d.text((W - 200, 160), "+", font=font_rounded(80), fill=ACCENT)
    # Big title
    d.text((90, 230), "Nutrition", font=font_rounded(110), fill=TEXT)

    # Date pill
    d.text((90, 380), "Wed, May 6", font=font(44), fill=TEXT_SECONDARY)

    # Calorie ring card
    card_y = 460
    card_h = 460
    rounded_rect(d, (60, card_y, W - 60, card_y + card_h), 48, fill=CARD)
    # Ring
    ring_cx, ring_cy = 260, card_y + card_h // 2
    R = 150
    # background ring
    d.ellipse((ring_cx-R, ring_cy-R, ring_cx+R, ring_cy+R), outline=(240,240,245), width=32)
    # progress arc 72%
    d.arc((ring_cx-R, ring_cy-R, ring_cx+R, ring_cy+R), start=-90, end=-90 + 360*0.72, fill=ACCENT, width=32)
    # center text
    d.text((ring_cx-115, ring_cy-50), "1,438", font=font_rounded(78), fill=TEXT)
    d.text((ring_cx-80, ring_cy+50), "of 2,000", font=font(36), fill=TEXT_SECONDARY)

    # Macros
    mx = 540
    macros = [("Protein", 92, 130, GREEN), ("Carbs", 168, 250, BLUE), ("Fat", 48, 70, PURPLE)]
    for i, (name, cur, tgt, color) in enumerate(macros):
        y = card_y + 70 + i * 120
        d.text((mx, y), name, font=font(40), fill=TEXT)
        d.text((mx + 380, y), f"{cur} / {tgt} g", font=font(38), fill=TEXT_SECONDARY)
        # Progress bar
        bar_y = y + 60
        bar_w = 600
        rounded_rect(d, (mx, bar_y, mx + bar_w, bar_y + 20), 10, fill=(240,240,245))
        rounded_rect(d, (mx, bar_y, mx + int(bar_w * cur/tgt), bar_y + 20), 10, fill=color)

    # Section header
    sec_y = card_y + card_h + 60
    d.text((90, sec_y), "MEALS", font=font(34), fill=TEXT_SECONDARY)

    # Meal entries
    meals = [
        ("Greek Yogurt with Berries", "Breakfast · 7:42 AM", "284", "kcal", GREEN),
        ("Grilled Chicken Salad", "Lunch · 12:30 PM", "512", "kcal", BLUE),
        ("Apple & Almonds", "Snack · 3:15 PM", "208", "kcal", ACCENT),
        ("Salmon, Rice & Veggies", "Dinner · 7:05 PM", "434", "kcal", PURPLE),
    ]
    list_y = sec_y + 80
    item_h = 200
    rounded_rect(d, (60, list_y, W - 60, list_y + item_h * len(meals)), 36, fill=CARD)
    for i, (name, sub, val, unit, color) in enumerate(meals):
        y = list_y + i * item_h
        if i > 0:
            d.line((140, y, W - 90, y), fill=SEPARATOR, width=1)
        # Icon circle
        d.ellipse((100, y + 50, 200, y + 150), fill=(color[0], color[1], color[2], 40) if False else (245,245,250))
        d.ellipse((130, y + 80, 170, y + 120), fill=color)
        # Name
        d.text((230, y + 50), name, font=font(46), fill=TEXT)
        d.text((230, y + 110), sub, font=font(34), fill=TEXT_SECONDARY)
        # Cal
        d.text((W - 320, y + 60), val, font=font_rounded(58), fill=TEXT)
        d.text((W - 180, y + 80), unit, font=font(34), fill=TEXT_SECONDARY)
        # Chevron
        d.text((W - 110, y + 80), "›", font=font(60), fill=(200,200,205))

    # Caption
    big_caption(d, "Log meals in seconds.", "AI photo analysis — fully on-device.")

    home_indicator(d)
    img.save(os.path.join(OUT_DIR, "02_food.png"), "PNG", optimize=True)
    print("✓ 02_food.png")


# =========================================================
# Screenshot 3: STATISTICS — weekly chart + summary
# =========================================================
def make_stats():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    status_bar(d, dark=False)

    d.text((90, 230), "Statistics", font=font_rounded(110), fill=TEXT)

    # Segmented control
    seg_y = 380
    seg_w = (W - 180) // 3
    segments = ["Week", "Month", "Year"]
    for i, s in enumerate(segments):
        sx = 90 + i * seg_w
        if i == 0:
            rounded_rect(d, (sx, seg_y, sx + seg_w - 6, seg_y + 80), 18, fill=CARD)
            d.text((sx + seg_w//2 - 60, seg_y + 18), s, font=font(40), fill=TEXT)
        else:
            d.text((sx + seg_w//2 - 60, seg_y + 18), s, font=font(40), fill=TEXT_SECONDARY)
    rounded_rect(d, (88, seg_y - 6, W - 86, seg_y + 90), 22, outline=SEPARATOR, width=2)

    # Steps card
    card_y = 520
    card_h = 700
    rounded_rect(d, (60, card_y, W - 60, card_y + card_h), 48, fill=CARD)
    d.text((100, card_y + 40), "STEPS", font=font(34), fill=TEXT_SECONDARY)
    d.text((100, card_y + 90), "9,427", font=font_rounded(140), fill=TEXT)
    d.text((100, card_y + 240), "avg / day this week", font=font(38), fill=TEXT_SECONDARY)
    # Bar chart
    chart_top = card_y + 340
    chart_bottom = card_y + 620
    chart_left = 130
    chart_right = W - 130
    days = ["M", "T", "W", "T", "F", "S", "S"]
    values = [0.65, 0.78, 0.55, 0.92, 0.71, 0.48, 0.83]
    bar_w = 110
    gap = (chart_right - chart_left - bar_w * 7) // 6
    for i, (day, v) in enumerate(zip(days, values)):
        bx = chart_left + i * (bar_w + gap)
        bh = (chart_bottom - chart_top - 40) * v
        # Bar background
        rounded_rect(d, (bx, chart_top, bx + bar_w, chart_bottom - 40), 20, fill=(245,245,250))
        # Bar fill
        rounded_rect(d, (bx, chart_bottom - 40 - bh, bx + bar_w, chart_bottom - 40), 20, fill=ACCENT)
        # Day label
        d.text((bx + 40, chart_bottom - 20), day, font=font(34), fill=TEXT_SECONDARY)

    # Quick stat tiles row
    tile_y = card_y + card_h + 40
    tile_w = (W - 180) // 2
    tile_h = 280
    tiles = [
        ("Calories", "2,140", "kcal / day", ACCENT, GREEN),
        ("Workouts", "5", "this week", BLUE, BLUE),
        ("Distance", "28.4", "km total", PURPLE, PURPLE),
        ("Active", "4h 12m", "this week", GREEN, GREEN),
    ]
    for i, (label, val, sub, c1, c2) in enumerate(tiles):
        col = i % 2
        row = i // 2
        tx = 60 + col * (tile_w + 60)
        ty = tile_y + row * (tile_h + 30)
        rounded_rect(d, (tx, ty, tx + tile_w, ty + tile_h), 36, fill=CARD)
        # Color dot
        d.ellipse((tx + 30, ty + 40, tx + 80, ty + 90), fill=c1)
        d.text((tx + 110, ty + 40), label, font=font(40), fill=TEXT_SECONDARY)
        d.text((tx + 30, ty + 110), val, font=font_rounded(96), fill=TEXT)
        d.text((tx + 30, ty + 220), sub, font=font(34), fill=TEXT_SECONDARY)

    # Caption
    big_caption(d, "See your progress.", "Daily, weekly, monthly — all your trends.")

    home_indicator(d)
    img.save(os.path.join(OUT_DIR, "03_statistics.png"), "PNG", optimize=True)
    print("✓ 03_statistics.png")


if __name__ == "__main__":
    make_workout()
    make_food()
    make_stats()
    # Verify dimensions
    for f in ("01_workout.png", "02_food.png", "03_statistics.png"):
        im = Image.open(os.path.join(OUT_DIR, f))
        print(f, im.size)
