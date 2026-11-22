#!/usr/bin/env python3
"""Draws the No Wave launcher icon sources from geometry, not from a bitmap.

The mark is the brand's "wave that stops": one orange stroke dips, rises
once, comes back down and runs flat, with a thin paper rule under the flat
part - the line the wave settles onto. It is the same mark as the web
favicon, redrawn heavier so it survives 48 px.

Outputs (all referenced from `flutter_launcher_icons:` in pubspec.yaml):

* assets/icons/logo.png            1024, opaque ink tile (iOS + legacy Android)
* assets/icons/logo-foreground.png 1024, transparent, adaptive foreground
* assets/icons/logo-monochrome.png 1024, alpha-only, Android 13 themed icon

`dart run flutter_launcher_icons` (CI, before the release build) turns these
into the platform files; the committed platform files are regenerated from
the same sources so a local build looks the same.

Usage: python3 tool/brand/launcher_icon.py   (needs pillow + numpy)
"""
from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image, ImageDraw

# Mirrors AppPalette.ink / .paper / .orange in lib/core/theme/app_palette.dart.
INK = (15, 13, 12)
PAPER = (242, 238, 230)
ORANGE = (216, 84, 31)

# Geometry in mark units: mark width 1.0, baseline y 0, +y points down.
WAVE_WIDTH = 0.10  # orange stroke
RULE_WIDTH = 0.030  # paper rule
RULE_GAP = 0.105  # baseline of the wave to the rule
RULE_START = 0.50  # the rule only sits under the settled, flat part
DIP = 0.035  # the stroke starts a little below the baseline
CREST = 0.16  # crest height above the baseline

# Share of the tile the whole mark (caps included) spans. The adaptive
# foreground is drawn into the central 68% of the 108dp canvas (16% inset),
# which is about the 72dp a launcher mask shows, so the same share works for
# both and keeps the mark well inside the 66dp safe circle.
MARK_SHARE = 0.60

SUPERSAMPLE = 4
SIZE = 1024


def _cubic(p0, p1, p2, p3, n: int = 600) -> np.ndarray:
    t = np.linspace(0.0, 1.0, n)[:, None]
    return (
        (1 - t) ** 3 * np.array(p0)
        + 3 * (1 - t) ** 2 * t * np.array(p1)
        + 3 * (1 - t) * t**2 * np.array(p2)
        + t**3 * np.array(p3)
    )


def wave() -> np.ndarray:
    rise = _cubic((0.0, DIP), (0.075, DIP), (0.105, -CREST), (0.19, -CREST))
    fall = _cubic((0.19, -CREST), (0.27, -CREST), (0.30, 0.0), (0.42, 0.0))
    flat = np.stack([np.linspace(0.42, 1.0, 600), np.zeros(600)], axis=1)
    return np.concatenate([rise, fall, flat])


def rule() -> np.ndarray:
    return np.stack([np.linspace(RULE_START, 1.0, 400), np.full(400, RULE_GAP)], axis=1)


def _bounds(points: np.ndarray) -> tuple[float, float, float, float]:
    left = -WAVE_WIDTH / 2
    right = 1 + WAVE_WIDTH / 2
    top = points[:, 1].min() - WAVE_WIDTH / 2
    bottom = RULE_GAP + RULE_WIDTH / 2
    return left, top, right, bottom


def _stroke(draw: ImageDraw.ImageDraw, points: np.ndarray, width: float, fill) -> None:
    radius = width / 2
    for x, y in points:
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=fill)


def render(background, wave_fill, rule_fill, size: int = SIZE) -> Image.Image:
    canvas = size * SUPERSAMPLE
    image = Image.new('RGBA', (canvas, canvas), background)
    w = wave()
    left, top, right, bottom = _bounds(w)
    scale = MARK_SHARE * canvas / (right - left)
    offset = np.array([canvas / 2 - (left + right) / 2 * scale, canvas / 2 - (top + bottom) / 2 * scale])
    draw = ImageDraw.Draw(image)
    _stroke(draw, rule() * scale + offset, RULE_WIDTH * scale, rule_fill)
    _stroke(draw, w * scale + offset, WAVE_WIDTH * scale, wave_fill)
    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    root = pathlib.Path(__file__).resolve().parents[2] / 'assets' / 'icons'
    render(INK + (255,), ORANGE + (255,), PAPER + (255,)).convert('RGB').save(
        root / 'logo.png', optimize=True
    )
    render((0, 0, 0, 0), ORANGE + (255,), PAPER + (255,)).save(root / 'logo-foreground.png', optimize=True)
    # Themed icons keep only alpha; the rule stays quieter than the wave.
    render((255, 255, 255, 0), (255, 255, 255, 255), (255, 255, 255, 140)).save(
        root / 'logo-monochrome.png', optimize=True
    )


if __name__ == '__main__':
    main()
