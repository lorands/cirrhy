#!/usr/bin/env python3
# Copyright 2026 Lóránd Somogyi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Regenerates every platform's app icon from the single source mark.

The mark is `assets/logo/cirrhy-mark.svg` — `assets/logo/logo-1.svg` cropped to
its drawing bounds, so the file's viewBox *is* the mark's bounding box. Nothing
here rasterises and rescales: every output is composed as SVG and rendered
straight to its final pixel size, so a 16px favicon is as crisp as a 1024px
store asset.

Geometry and colour come from the Penpot library, page `08 · Brand & Logo`,
card `App icon`. Measured off the 112px artboard:

    tile corner radius   25 / 112      = 22.32% of the tile
    mark width           67.2 / 112    = 60%    of the tile
    mark left inset      22.4 / 112    = 20%    of the tile
    mark top inset       24.64 / 112   = 22%    of the tile

The mark sits a hair below centre — that is the design, not a rounding error;
the hands reach up and to the right, so optical centre is below geometric.

Penpot names three variants; each platform gets the ones it can actually show:

    light   #E8F7F0 tile, #0B8560 mark    iOS light appearance
    dark    #0B1512 tile, #34D399 mark    iOS dark appearance
    solid   #0B8560 tile, #FFFFFF mark    everything with only one slot

Desktops and the Android launcher get `solid`: green reads on both a light and
a dark shelf, where the pale `light` tile vanishes on white and `dark` vanishes
on black. iOS is the one target that genuinely swaps, so it carries all three
(plus the greyscale `tinted` appearance iOS 18 composites the user's colour
onto).

Usage:

    python3 tool/gen_app_icons.py            # regenerate everything
    python3 tool/gen_app_icons.py --recrop   # re-derive the mark from logo-1.svg first

Needs `rsvg-convert` (librsvg) and `magick` (ImageMagick 7) on PATH; `--recrop`
additionally needs `inkscape`.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "assets" / "logo" / "logo-1.svg"
MARK = ROOT / "assets" / "logo" / "cirrhy-mark.svg"
ICON_DIR = ROOT / "assets" / "icon"
APP = ROOT / "app"

APPLICATION_ID = "com.lorands.cirrhy"

# --- Geometry, as fractions of the tile ------------------------------------

RADIUS = 25 / 112
MARK_W = 0.60
MARK_LEFT = 0.20
MARK_TOP = 0.22

# Apple's macOS icon grid: the rounded body fills 824 of a 1024 canvas, the
# rest is transparent margin. macOS draws icons unmasked, so unlike iOS the
# shape has to be baked in.
MACOS_BODY = 824 / 1024

# An Android adaptive icon is a 108dp canvas of which the launcher mask can
# only ever reveal the middle 72dp. The design fractions apply to that visible
# tile, not to the canvas.
ADAPTIVE_CANVAS = 108
ADAPTIVE_SAFE = 72

# Optical sizing. The mark is drawn as filled outlines whose thinnest lines
# measure ~0.9 units across the mark's own 64.64-unit viewBox (measured off a
# 2048px render, 25th percentile of scanline runs — the low percentiles are the
# ones that cross a stroke square-on). Scaled down, those lines fall under a
# pixel and antialias into a grey ghost: at 32px they are a quarter-pixel wide.
# So below the size where a hairline still covers MIN_STROKE_PX, the path is
# given a stroke of its own fill colour to make up the difference. The taper is
# automatic — at 128px and above the boost is zero and the pixels are exactly
# what the design draws. Anything smaller was unreadable before, not faithful.
HAIRLINE_UNITS = 0.9
MIN_STROKE_PX = 0.75


@dataclass(frozen=True)
class Variant:
    tile: str
    mark: str


VARIANTS = {
    "light": Variant(tile="#E8F7F0", mark="#0B8560"),
    "dark": Variant(tile="#0B1512", mark="#34D399"),
    "solid": Variant(tile="#0B8560", mark="#FFFFFF"),
    # iOS composites the user's tint over this one, so it wants maximum
    # luminance range rather than brand colour.
    "tinted": Variant(tile="#000000", mark="#FFFFFF"),
}


# --- Source mark ------------------------------------------------------------


def recrop() -> None:
    """Re-derives cirrhy-mark.svg from logo-1.svg, cropped to the drawing."""
    run(
        [
            "inkscape",
            "--export-area-drawing",
            "--export-plain-svg",
            f"--export-filename={MARK}",
            str(LOGO),
        ]
    )
    print(f"  recropped {MARK.relative_to(ROOT)}")


def load_mark() -> tuple[str, float, float]:
    """Returns the mark's drawable markup and its intrinsic width and height."""
    svg = MARK.read_text(encoding="utf-8")

    view_box = re.search(r'viewBox="([^"]+)"', svg)
    if not view_box:
        sys.exit(f"{MARK} has no viewBox — re-run with --recrop")
    _, _, width, height = (float(n) for n in view_box.group(1).split())

    body = re.search(r"(<g\b.*</g>)", svg, re.S)
    if not body:
        sys.exit(f"{MARK} has no drawable <g> — re-run with --recrop")

    return body.group(1), width, height


MARK_BODY, MARK_VB_W, MARK_VB_H = "", 1.0, 1.0
MARK_ASPECT = 1.0  # height / width


# --- Composition ------------------------------------------------------------


def thicken(markup: str, colour: str, width: float) -> str:
    """Strokes the mark's outlines in their own fill colour. See MIN_STROKE_PX."""

    def restyle(match: re.Match[str]) -> str:
        style = re.sub(r"stroke[^;]*;?", "", match.group(1)).strip(";")
        return (
            f'style="{style};stroke:{colour};stroke-width:{width:.5f};'
            'stroke-linejoin:round;stroke-linecap:round"'
        )

    return re.sub(r'style="([^"]*)"', restyle, markup)


def compose(
    canvas: float,
    variant: Variant,
    *,
    body: tuple[float, float, float, float] | None = None,
    radius: float = RADIUS,
    draw_tile: bool = True,
    px: int | None = None,
) -> str:
    """Builds one square icon as SVG.

    `body` is the tile's rect within the canvas, defaulting to the whole
    canvas. `radius` is a fraction of the body's width; pass 0 for the
    full-bleed square iOS and the Play Store want. `draw_tile=False` emits the
    mark alone on transparency, which is what an Android adaptive foreground
    and its monochrome sibling are. `px` is the pixel size the result will be
    rasterised at, and only affects the optical-size stroke boost; leave it
    unset for output that stays vector.
    """
    bx, by, bw, bh = body if body else (0.0, 0.0, canvas, canvas)

    mw = bw * MARK_W
    mh = mw * MARK_ASPECT
    mx = bx + bw * MARK_LEFT
    my = by + bh * MARK_TOP

    tile = ""
    if draw_tile:
        rx = f' rx="{bw * radius:.4f}" ry="{bw * radius:.4f}"' if radius else ""
        tile = (
            f'<rect x="{bx:.4f}" y="{by:.4f}" width="{bw:.4f}" '
            f'height="{bh:.4f}"{rx} fill="{variant.tile}"/>'
        )

    mark = MARK_BODY.replace("fill:#000000", f"fill:{variant.mark}")

    if px:
        mark_px = mw / canvas * px
        hairline_px = HAIRLINE_UNITS / MARK_VB_W * mark_px
        if hairline_px < MIN_STROKE_PX:
            deficit = (MIN_STROKE_PX - hairline_px) * MARK_VB_W / mark_px
            mark = thicken(mark, variant.mark, deficit)

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{canvas:g}" '
        f'height="{canvas:g}" viewBox="0 0 {canvas:g} {canvas:g}">'
        f"{tile}"
        f'<svg x="{mx:.4f}" y="{my:.4f}" width="{mw:.4f}" height="{mh:.4f}" '
        f'viewBox="0 0 {MARK_VB_W} {MARK_VB_H}">{mark}</svg>'
        f"</svg>"
    )


# --- Rendering --------------------------------------------------------------


def run(cmd: list[str]) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"{cmd[0]} failed:\n{result.stderr.strip()}")


def render(svg_for: Callable[[int], str], out: Path, size: int, *, opaque: bool = False) -> Path:
    """Rasterises a composed icon to a PNG of exactly `size` square.

    Takes a builder rather than finished markup because composition depends on
    the target size — see MIN_STROKE_PX.
    """
    out.parent.mkdir(parents=True, exist_ok=True)
    scratch = out.with_suffix(".svg.tmp")
    scratch.write_text(svg_for(size), encoding="utf-8")
    run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(out), str(scratch)])
    scratch.unlink()
    if opaque:
        # The App Store rejects an app icon carrying an alpha channel, even a
        # fully opaque one. Forcing TrueColor keeps the greyscale tinted
        # variant from being written as a single-channel PNG.
        # -strip and excluding the time chunk keep the output byte-identical
        # across runs; without them ImageMagick stamps the current time and
        # every regeneration shows up as a diff.
        run(["magick", str(out), "-background", "white", "-alpha", "remove", "-alpha", "off",
             "-colorspace", "sRGB", "-type", "TrueColor", "-strip",
             "-define", "png:color-type=2", "-define", "png:exclude-chunk=date,time",
             str(out)])
    return out


# --- Targets ----------------------------------------------------------------


def gen_masters() -> None:
    """The three composed 1024 tiles, kept as vector for design hand-off."""
    for name in ("light", "dark", "solid"):
        path = ICON_DIR / f"app-icon-{name}.svg"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(compose(1024, VARIANTS[name]), encoding="utf-8")
        print(f"  {path.relative_to(ROOT)}")


def gen_ios() -> None:
    """iOS 18 appearance-aware app icon: light, dark and tinted at 1024.

    Xcode derives every smaller size from these, which is why the legacy
    per-size Icon-App-*.png list this replaces is gone.
    """
    d = APP / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

    for stale in d.glob("Icon-App-*.png"):
        stale.unlink()

    files = {
        "light": "Icon-App-1024x1024@1x.png",
        "dark": "Icon-App-Dark-1024x1024@1x.png",
        "tinted": "Icon-App-Tinted-1024x1024@1x.png",
    }
    for variant, filename in files.items():
        # Full bleed, no corner radius: iOS applies its own squircle mask.
        render(lambda px, v=variant: compose(1024, VARIANTS[v], radius=0, px=px),
               d / filename, 1024, opaque=True)

    entries = [
        '    {\n      "filename" : "%s",\n      "idiom" : "universal",\n'
        '      "platform" : "ios",\n      "size" : "1024x1024"\n    }' % files["light"],
        '    {\n      "appearances" : [\n        {\n'
        '          "appearance" : "luminosity",\n          "value" : "dark"\n'
        '        }\n      ],\n      "filename" : "%s",\n      "idiom" : "universal",\n'
        '      "platform" : "ios",\n      "size" : "1024x1024"\n    }' % files["dark"],
        '    {\n      "appearances" : [\n        {\n'
        '          "appearance" : "luminosity",\n          "value" : "tinted"\n'
        '        }\n      ],\n      "filename" : "%s",\n      "idiom" : "universal",\n'
        '      "platform" : "ios",\n      "size" : "1024x1024"\n    }' % files["tinted"],
    ]
    (d / "Contents.json").write_text(
        '{\n  "images" : [\n' + ",\n".join(entries) + "\n  ],\n"
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n',
        encoding="utf-8",
    )
    print(f"  {d.relative_to(ROOT)}/ — light, dark, tinted")


def gen_macos() -> None:
    """macOS wants the rounded shape and its margin baked into the pixels."""
    d = APP / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    inset = (1 - MACOS_BODY) / 2
    body = (1024 * inset, 1024 * inset, 1024 * MACOS_BODY, 1024 * MACOS_BODY)
    svg_for = lambda px: compose(1024, VARIANTS["solid"], body=body, px=px)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        render(svg_for, d / f"app_icon_{size}.png", size)
    print(f"  {d.relative_to(ROOT)}/ — 7 sizes, solid")


def gen_android() -> None:
    """Legacy launcher bitmaps, the adaptive layers, and a themed monochrome."""
    res = APP / "android" / "app" / "src" / "main" / "res"
    solid = VARIANTS["solid"]

    # Pre-API-26 launchers use this bitmap as-is, so the tile shape is baked in.
    legacy = lambda px: compose(1024, solid, px=px)
    for bucket, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                         ("xxhdpi", 144), ("xxxhdpi", 192)):
        render(legacy, res / f"mipmap-{bucket}" / "ic_launcher.png", size)

    # API 26+ composites a foreground over a background and applies its own
    # mask, so the foreground is the mark alone, positioned against the 72dp
    # safe zone rather than the full 108dp canvas.
    edge = (ADAPTIVE_CANVAS - ADAPTIVE_SAFE) / 2
    safe = (edge, edge, ADAPTIVE_SAFE, ADAPTIVE_SAFE)
    foreground = lambda px: compose(ADAPTIVE_CANVAS, solid, body=safe, draw_tile=False, px=px)
    # Android 13+ themed icons tint this by luminance, so it is the same
    # geometry drawn flat.
    mono_variant = Variant(tile="#000000", mark="#FFFFFF")
    monochrome = lambda px: compose(ADAPTIVE_CANVAS, mono_variant, body=safe,
                                    draw_tile=False, px=px)
    for bucket, size in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                         ("xxhdpi", 324), ("xxxhdpi", 432)):
        render(foreground, res / f"mipmap-{bucket}" / "ic_launcher_foreground.png", size)
        render(monochrome, res / f"mipmap-{bucket}" / "ic_launcher_monochrome.png", size)

    (res / "values").mkdir(parents=True, exist_ok=True)
    (res / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{solid.tile}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )

    # No android:roundIcon companion here on purpose. Adaptive icons already
    # give circular launchers a correct circle from this one definition, and a
    # roundIcon that only exists under -v26 blows up on anything older.
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )

    # Play Console listing icon: 512 square, no transparency, no baked mask.
    render(lambda px: compose(1024, solid, radius=0, px=px),
           ICON_DIR / "play-store-512.png", 512, opaque=True)
    print("  app/android/.../res/ — legacy, adaptive, monochrome + play-store-512.png")


def gen_windows() -> None:
    """A multi-resolution .ico; Windows picks the size, and never masks."""
    out = APP / "windows" / "runner" / "resources" / "app_icon.ico"
    out.parent.mkdir(parents=True, exist_ok=True)
    svg_for = lambda px: compose(1024, VARIANTS["solid"], px=px)
    staged = [render(svg_for, out.parent / f".ico-{s}.png", s)
              for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)]
    run(["magick", *[str(p) for p in staged], str(out)])
    for p in staged:
        p.unlink()
    print(f"  {out.relative_to(ROOT)} — 9 sizes")


def gen_linux() -> None:
    """A hicolor tree the runner reads at run time and a package can install."""
    d = APP / "linux" / "runner" / "resources"
    svg_for = lambda px: compose(1024, VARIANTS["solid"], px=px)
    for size in (16, 22, 24, 32, 48, 64, 128, 256, 512):
        render(svg_for, d / "icons" / "hicolor" / f"{size}x{size}" / "apps"
               / f"{APPLICATION_ID}.png", size)

    scalable = d / "icons" / "hicolor" / "scalable" / "apps" / f"{APPLICATION_ID}.svg"
    scalable.parent.mkdir(parents=True, exist_ok=True)
    scalable.write_text(compose(512, VARIANTS["solid"]), encoding="utf-8")

    desktop = d / f"{APPLICATION_ID}.desktop"
    desktop.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Cirrhy\n"
        "GenericName=Time Tracker\n"
        "Comment=A single-file personal time tracker\n"
        "Exec=cirrhy %f\n"
        f"Icon={APPLICATION_ID}\n"
        "Terminal=false\n"
        "Categories=Office;ProjectManagement;Utility;\n"
        "Keywords=time;tracking;timer;timesheet;\n"
        f"StartupWMClass={APPLICATION_ID}\n",
        encoding="utf-8",
    )
    print(f"  {d.relative_to(ROOT)}/ — hicolor 16–512, scalable, .desktop")


# --- Entry point ------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--recrop", action="store_true",
                        help="re-derive cirrhy-mark.svg from logo-1.svg (needs inkscape)")
    args = parser.parse_args()

    for binary in ("rsvg-convert", "magick"):
        if shutil.which(binary) is None:
            sys.exit(f"{binary} not found on PATH")
    if args.recrop:
        if shutil.which("inkscape") is None:
            sys.exit("inkscape not found on PATH")
        recrop()

    global MARK_BODY, MARK_VB_W, MARK_VB_H, MARK_ASPECT
    MARK_BODY, MARK_VB_W, MARK_VB_H = load_mark()
    MARK_ASPECT = MARK_VB_H / MARK_VB_W

    for name, fn in (
        ("masters", gen_masters),
        ("ios", gen_ios),
        ("macos", gen_macos),
        ("android", gen_android),
        ("windows", gen_windows),
        ("linux", gen_linux),
    ):
        print(f"{name}:")
        fn()


if __name__ == "__main__":
    main()
