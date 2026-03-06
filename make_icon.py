from PIL import Image, ImageDraw

SIZE = 1024
img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))

# 대각선 그라디언트 배경 (진초록 → 밝은 초록)
bg = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
bg_draw = ImageDraw.Draw(bg)
for i in range(SIZE):
    ratio = i / SIZE
    r = int(22  + (56  - 22)  * ratio)
    g = int(160 + (217 - 160) * ratio)
    b = int(133 + (87  - 133) * ratio)
    bg_draw.line([(0, i), (SIZE, i)], fill=(r, g, b, 255))

# 둥근 모서리 마스크
mask = Image.new('L', (SIZE, SIZE), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE-1, SIZE-1], radius=220, fill=255)
img.paste(bg, (0, 0), mask)

draw = ImageDraw.Draw(img)
cx, cy = SIZE // 2, SIZE // 2

# ── 흰색 원형 접시 ──
pr = 300
draw.ellipse([cx-pr, cy-pr+20, cx+pr, cy+pr+20], fill=(255,255,255,240))
# 접시 안쪽 ring
draw.ellipse([cx-pr+22, cy-pr+42, cx+pr-22, cy+pr-2],
             outline=(230,245,235,200), width=14)

# ── 포크 (왼쪽, 흰 배경 위에 초록) ──
fc = (30, 170, 100)
fx, fy = cx - 95, cy - 165

# 포크 살 3개
for i, ox in enumerate([-20, 0, 20]):
    draw.rounded_rectangle([fx+ox-7, fy, fx+ox+7, fy+145], radius=7, fill=fc)
# 포크 가로 연결
draw.rounded_rectangle([fx-30, fy+135, fx+30, fy+155], radius=7, fill=fc)
# 포크 손잡이
draw.rounded_rectangle([fx-12, fy+150, fx+12, fy+330], radius=12, fill=fc)
# 손잡이 끝 동그라미
draw.ellipse([fx-16, fy+315, fx+16, fy+348], fill=fc)

# ── 스푼 (오른쪽, 흰 배경 위에 밝은 초록) ──
sc = (46, 204, 113)
sx, sy = cx + 95, cy - 165

# 스푼 머리 (타원)
draw.ellipse([sx-35, sy, sx+35, sy+95], fill=sc)
# 스푼 목
draw.rounded_rectangle([sx-9, sy+88, sx+9, sy+200], radius=9, fill=sc)
# 스푼 손잡이
draw.rounded_rectangle([sx-12, sy+195, sx+12, sy+330], radius=12, fill=sc)
# 손잡이 끝 동그라미
draw.ellipse([sx-16, sy+315, sx+16, sy+348], fill=sc)

# ── "AI" 뱃지 (접시 하단부) ──
bx, by = cx, cy + 160
# 뱃지 배경 pill
draw.rounded_rectangle([bx-68, by-28, bx+68, by+28], radius=28, fill=(30,170,100,230))

# A 글자 (삼각형 + 가로줄)
ax, ay_ = bx - 42, by - 16
pts_a = [(ax, ay_+32), (ax+18, ay_), (ax+36, ay_+32)]
draw.polygon(pts_a, fill=(255,255,255))
draw.rounded_rectangle([ax+8, ay_+18, ax+28, ay_+25], radius=3, fill=(30,170,100,230))

# I 글자
ix = bx + 16
draw.rounded_rectangle([ix-10, ay_+2, ix+10, ay_+30], radius=5, fill=(255,255,255))
draw.rounded_rectangle([ix-16, ay_+2, ix+16, ay_+10], radius=4, fill=(255,255,255))
draw.rounded_rectangle([ix-16, ay_+24, ix+16, ay_+32], radius=4, fill=(255,255,255))

# ── 하이라이트 (상단 광택) ──
hi = Image.new('RGBA', (SIZE, SIZE), (0,0,0,0))
hi_draw = ImageDraw.Draw(hi)
hi_draw.ellipse([cx-320, cy-440, cx+320, cy-60], fill=(255,255,255,22))
img = Image.alpha_composite(img, hi)

output = 'assets/icon/app_icon.png'
img.save(output, 'PNG')
print(f"아이콘 저장 완료: {output} ({SIZE}x{SIZE})")
