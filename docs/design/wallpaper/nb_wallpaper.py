#!/usr/bin/env python
"""Bioma's default wallpaper, redrawn in Opera Prisma's illustration style.

Same method as Opera Prisma's design/ui/_INTRO/nb_intro.py: Nano Banana Pro,
with the card style anchors in comfyui/nb_refs. Here one extra image goes in:
the wallpaper it replaced, a misty forest photograph, as the composition to
redraw. Variant 1 of the first run became assets/wallpapers/bioma-forest.jpg,
scaled to 3840x2160 (the model's 4K is 5504x3072).

    PY=~/Documents/Development/comfyui/.venv/bin/python
    $PY nb_wallpaper.py [variants]     # needs GEMINI_API_KEY; writes into ./nb_wallpaper/
"""
import os, sys, time, mimetypes, functools
print = functools.partial(print, flush=True)

HERE    = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, 'nb_wallpaper')
REF_DIR = os.path.expanduser('~/Documents/Development/comfyui/nb_refs')
SOURCE  = os.path.expanduser('~/.config/dcli/modules/configuration/dotfiles/wallpapers/wallhaven-9dw721.jpg')

MODEL      = 'gemini-3-pro-image-preview'
ASPECT     = '16:9'
IMAGE_SIZE = '4K'
MAX_STYLE  = 5

STYLE = 'comic book illustration, bold inked linework, cel shading, flat graphic colors'

PROMPT = (
    'The FIRST attached images are STYLE references: match EXACTLY their illustration style — '
    'the same inked linework weight, the same cel shading, the same flat graphic color treatment. '
    'Do NOT copy their characters, costumes or settings. Take the drawing style and nothing else.\n\n'
    'The LAST attached image is the COMPOSITION reference: a misty green forest photograph. '
    'Redraw that same scene in the style above — the same framing and layout: an arch of dense '
    'leafy canopy across the top, a massive mossy oak trunk on the right, a leafy bush mass on the '
    'left, a worn dirt path winding from the bottom centre into the forest, rows of tree trunks '
    'fading into bright hazy green-gold light in the centre distance, grassy banks on both sides.\n\n'
    f'{STYLE}. Light falls in soft shafts through the mist from the glowing centre; the edges and '
    'the canopy are deep, dark greens that read as material, not empty paper. Calm, quiet, no '
    'action. No people, no animals, no creatures, no buildings. '
    'Wide landscape desktop wallpaper: the centre and upper corners stay calm and uncluttered. '
    'No text, no letters, no logo, no watermark, no signature, no frame, no border, '
    'no letterboxing, edge to edge artwork.'
)

REQUEST_TIMEOUT_MS = 300_000


def part(path):
    from google.genai import types
    with open(path, 'rb') as f:
        return types.Part.from_bytes(data=f.read(), mime_type=mimetypes.guess_type(path)[0])


def main(variants):
    from google import genai
    from google.genai import types
    os.makedirs(OUT_DIR, exist_ok=True)
    styles = sorted(os.path.join(REF_DIR, n) for n in os.listdir(REF_DIR)
                    if (mimetypes.guess_type(n)[0] or '').startswith('image/'))[:MAX_STYLE]
    contents = [part(p) for p in styles] + [part(SOURCE), PROMPT]
    client = genai.Client(http_options=types.HttpOptions(timeout=REQUEST_TIMEOUT_MS))
    cfg = types.GenerateContentConfig(
        response_modalities=['TEXT', 'IMAGE'],
        image_config=types.ImageConfig(aspect_ratio=ASPECT, image_size=IMAGE_SIZE))
    print(f'{variants} variants, {len(styles)} style anchors, {MODEL} {IMAGE_SIZE} {ASPECT}')
    for v in range(1, variants + 1):
        out = os.path.join(OUT_DIR, f'bioma_forest_{v}.jpg')
        if os.path.exists(out):
            print('skip', out); continue
        for attempt in range(3):
            try:
                resp = client.models.generate_content(model=MODEL, contents=contents, config=cfg)
                img = None
                for p in resp.candidates[0].content.parts:
                    if getattr(p, 'inline_data', None) and p.inline_data.data:
                        img = p.inline_data.data
                if img:
                    with open(out, 'wb') as f:
                        f.write(img)
                    print('DONE', out)
                else:
                    print('NO IMAGE', ''.join(getattr(p, 'text', '') or '' for p in resp.candidates[0].content.parts)[:300])
                break
            except Exception as e:
                msg = str(e)
                if any(k in msg for k in ('429', 'RESOURCE_EXHAUSTED', '401', 'UNAUTHENTICATED',
                                          'API_KEY_INVALID', 'PERMISSION_DENIED')):
                    sys.exit(f'fatal: {msg[:300]}')
                print(f'ERR attempt {attempt + 1}: {msg[:200]}')
                time.sleep(15 * (2 ** attempt))


if __name__ == '__main__':
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 2)
