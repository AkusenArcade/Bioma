#!/usr/bin/env python
"""Bioma's "Tissue" wallpaper: a leaf section seen as a landscape.

The machine is an organism, made of membranes, tissues and cells, and a cell
speaks only when it has something to say. The picture is that idea: a tissue at
rest, almost all of it in shadow, with a few cells lit. One light, from above
and slightly from the left (the style guide's 165 degrees).

The prompt alone, coloured by one of the shipped palettes (config/palettes/).
The bioma variant was drawn with no reference image; its variant 1 then went in
as the composition reference for paper, so the two themes show the same tissue.
Nano Banana Pro at 4K (5504x3072), filled and centre-cropped to 3840x2160:
bioma variant 1 became assets/wallpapers/bioma-tissue.jpg, paper variant 3
assets/wallpapers/paper-tissue.jpg.

    PY=~/Documents/Development/comfyui/.venv/bin/python
    $PY nb_tissue.py <bioma|paper> [variants] [reference]   # needs GEMINI_API_KEY; writes into ./nb_wallpaper/
"""
import os, sys, time, mimetypes, functools
print = functools.partial(print, flush=True)

HERE    = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, 'nb_wallpaper')

MODEL      = 'gemini-3-pro-image-preview'
ASPECT     = '16:9'
IMAGE_SIZE = '4K'

SUBJECT = (
    'A cross-section of a plant leaf seen through a microscope, drawn at the scale of a landscape: '
    'plant cells packed into a living tissue, each one a rounded polygonal chamber walled by a '
    'translucent membrane, with small chloroplast granules resting inside. '
    'The tissue is AT REST: nearly every cell sits quiet in shadow. Only a FEW scattered cells, '
    'no more than five or six across the whole image, are lit from within, as if they alone had '
    'something to say. '
    'One light source only, from above and slightly from the left: the upper edge of every '
    'membrane catches a thin line of light, the lower side falls into shade. '
)

COMPOSITION = (
    'Composition for a wide desktop wallpaper: the tissue is dense and detailed in the lower right '
    'and along the bottom edge, and dissolves softly into depth and out of focus towards the top '
    'and the centre, so the centre and the upper corners stay calm and uncluttered. '
    'Macro photography depth of field, soft painterly digital illustration, subtle organic texture, '
    'quiet and still. '
)

THEMES = {
    'bioma': (
        'Colour palette, strictly: a very dark green-black ground (#12160F, #1B2117); membranes and '
        'cell walls in muted moss green (#4F6340, #6B8457) with a paler rim of light (#8BA86E) on '
        'their upper edges; the few lit cells glow a warm lime green (#B9DE6B); a faint teal '
        '(#3FBFA0) in the fluid between some cells. Overall dark and low-key, like a desktop at '
        'night. No red, no yellow, no orange, no blue, no purple. '
    ),
    'paper': (
        'Colour palette, strictly: a warm off-white paper ground (#F4F1EA), like a stained '
        'specimen on a light-microscope slide or a plate in an old botanical atlas; membranes and '
        'cell walls drawn in soft sage grey-green (#5E6B5C) and fine dark ink (#1E1B16) at low '
        'contrast; the few lit cells filled with a warm ochre gold (#8A6A12), gently luminous. '
        'Overall light, airy and high-key, with plenty of pale paper around the tissue. '
        'No saturated greens, no red, no blue, no purple. '
    ),
}

CLEAN = (
    'No people, no animals, no creatures, no buildings. No text, no letters, no labels, no scale '
    'bar, no logo, no watermark, no signature, no frame, no border, no vignette ring of a '
    'microscope eyepiece, no letterboxing, edge to edge artwork.'
)

REFERENCE = (
    'The attached image is the COMPOSITION reference: redraw that same tissue, with the same '
    'framing, the same curved band of cells, the same lit cells in the same places and the same '
    'empty calm areas, but in the colour palette below and nothing of its own colours. '
)

REQUEST_TIMEOUT_MS = 300_000


def main(theme, variants, reference=None):
    from google import genai
    from google.genai import types
    os.makedirs(OUT_DIR, exist_ok=True)
    prompt = SUBJECT + COMPOSITION + THEMES[theme] + CLEAN
    contents = [prompt]
    if reference:
        with open(reference, 'rb') as f:
            ref = types.Part.from_bytes(data=f.read(), mime_type=mimetypes.guess_type(reference)[0])
        contents = [ref, REFERENCE + prompt]
    client = genai.Client(http_options=types.HttpOptions(timeout=REQUEST_TIMEOUT_MS))
    cfg = types.GenerateContentConfig(
        response_modalities=['TEXT', 'IMAGE'],
        image_config=types.ImageConfig(aspect_ratio=ASPECT, image_size=IMAGE_SIZE))
    print(f'{theme}: {variants} variants, {MODEL} {IMAGE_SIZE} {ASPECT}, reference {reference}')
    for v in range(1, variants + 1):
        out = os.path.join(OUT_DIR, f'{theme}_tissue_{v}.jpg')
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
    if len(sys.argv) < 2 or sys.argv[1] not in THEMES:
        sys.exit(f'usage: nb_tissue.py <{"|".join(THEMES)}> [variants] [reference]')
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 4,
         sys.argv[3] if len(sys.argv) > 3 else None)
