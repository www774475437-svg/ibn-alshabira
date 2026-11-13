import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
F = '/home/claude/fonts/'
AMIRI_B = F+'Amiri-1.000/Amiri-Bold.ttf'
KUFI_B = F+'ReemKufi-1.7/ttf/ReemKufi-Bold.ttf'
GOLD = (214, 178, 94); GOLD2 = (240, 212, 140); GREEN = (22, 64, 42); DGREEN = (10, 36, 23)
S = 1024

def radial_bg(c_in, c_out):
    im = Image.new('RGB', (S, S), c_out)
    d = ImageDraw.Draw(im)
    for r in range(S//2+200, 0, -4):
        t = r/(S/2+200)
        col = tuple(int(c_in[i]*(1-t)+c_out[i]*t) for i in range(3))
        d.ellipse([S/2-r, S/2-r, S/2+r, S/2+r], fill=col)
    return im

def gold_text(im, text, font, cy, size_box):
    f = ImageFont.truetype(font, 10, layout_engine=ImageFont.Layout.RAQM)
    # fit width
    size = 10
    while True:
        f = ImageFont.truetype(font, size, layout_engine=ImageFont.Layout.RAQM)
        b = f.getbbox(text, direction='rtl', language='ar')
        if b[2]-b[0] > size_box or size > 600: break
        size += 4
    f = ImageFont.truetype(font, size-4, layout_engine=ImageFont.Layout.RAQM)
    b = f.getbbox(text, direction='rtl', language='ar')
    w, h = b[2]-b[0], b[3]-b[1]
    x, y = (S-w)/2 - b[0], cy - h/2 - b[1]
    # shadow
    sh = Image.new('L', (S, S), 0)
    ImageDraw.Draw(sh).text((x+6, y+8), text, font=f, fill=180, direction='rtl', language='ar')
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    im.paste((0, 0, 0), (0, 0), sh)
    # gold gradient fill
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).text((x, y), text, font=f, fill=255, direction='rtl', language='ar')
    grad = Image.new('RGB', (S, S))
    gd = ImageDraw.Draw(grad)
    for yy in range(S):
        t = (yy - (cy-h/2)) / max(h, 1); t = min(max(t, 0), 1)
        col = tuple(int(GOLD2[i]*(1-t)+GOLD[i]*t) for i in range(3))
        gd.line([(0, yy), (S, yy)], fill=col)
    im.paste(grad, (0, 0), mask)

def ring(d, r, w, col):
    d.ellipse([S/2-r, S/2-r, S/2+r, S/2+r], outline=col, width=w)

def dots_ring(d, r, n, rad, col):
    for i in range(n):
        a = 2*math.pi*i/n
        x, y = S/2+r*math.cos(a), S/2+r*math.sin(a)
        d.ellipse([x-rad, y-rad, x+rad, y+rad], fill=col)

def design_a():  # Amiri calligraphy in double gold ring, green
    im = radial_bg((34, 92, 60), DGREEN); d = ImageDraw.Draw(im)
    ring(d, 430, 14, GOLD); ring(d, 395, 4, GOLD); dots_ring(d, 412, 48, 4, GOLD)
    gold_text(im, 'ابن', AMIRI_B, 330, 200)
    gold_text(im, 'الشابرة', AMIRI_B, 560, 600)
    return im

def design_b():  # Kufi on black with gold disc
    im = Image.new('RGB', (S, S), (8, 8, 8)); d = ImageDraw.Draw(im)
    d.ellipse([S/2-420, S/2-420, S/2+420, S/2+420], fill=(18, 18, 18))
    ring(d, 420, 10, GOLD); ring(d, 380, 3, GOLD)
    gold_text(im, 'الشابرة', KUFI_B, 520, 560)
    d.line([(S/2-150, 700), (S/2+150, 700)], fill=GOLD, width=4)
    return im

def design_c():  # Open book + name, green
    im = radial_bg((30, 84, 55), DGREEN); d = ImageDraw.Draw(im)
    ring(d, 430, 10, GOLD)
    gold_text(im, 'الشابرة', AMIRI_B, 420, 560)
    # open book
    cx, top = S/2, 600
    for side in (-1, 1):
        pts = [(cx, top+40), (cx+side*230, top), (cx+side*230, top+170), (cx, top+210)]
        d.polygon(pts, outline=GOLD, width=10)
        for k in range(1, 4):
            y0 = top+40+k*38
            d.line([(cx+side*30, y0+4), (cx+side*200, y0-24)], fill=GOLD, width=5)
    return im

def foreground(im_fn):
    """Adaptive-icon foreground: transparent bg, design shrunk into safe zone."""
    full = im_fn()
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).ellipse([S/2-440, S/2-440, S/2+440, S/2+440], fill=255)
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    fg.paste(full, (0, 0), mask)
    small = fg.resize((int(S*0.66), int(S*0.66)), Image.LANCZOS)
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(small, ((S-small.width)//2, (S-small.height)//2), small)
    return out

out = sys.argv[1]
designs = {'a': design_a, 'b': design_b, 'c': design_c}
imgs = {}
for k, fn in designs.items():
    imgs[k] = fn(); imgs[k].save(f'{out}/logo_{k}.png')
foreground(design_a).save(f'{out}/logo_a_foreground.png')
# preview sheet
sheet = Image.new('RGB', (3*360+80, 470), (245, 240, 228)); sd = ImageDraw.Draw(sheet)
lab = ImageFont.truetype(AMIRI_B, 40, layout_engine=ImageFont.Layout.RAQM)
for i, k in enumerate('abc'):
    sm = imgs[k].resize((340, 340), Image.LANCZOS)
    m = Image.new('L', (340, 340), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, 339, 339], 70, fill=255)
    x = 20+i*(360+20)
    sheet.paste(sm, (x, 20), m)
    sd.text((x+170, 410), ['التصميم ١', 'التصميم ٢', 'التصميم ٣'][i], font=lab, fill=(30, 60, 40), anchor='mm', direction='rtl', language='ar')
sheet.save(f'{out}/logos_preview.png')
print('ok')
