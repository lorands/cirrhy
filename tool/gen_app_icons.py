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

Geometry comes from the Penpot library, page `08 · Brand & Logo`, card
`App icon`. Measured off the 112px artboard:

    tile corner radius   25 / 112      = 22.32% of the tile
    mark width           67.2 / 112    = 60%    of the tile
    mark left inset      22.4 / 112    = 20%    of the tile
    mark top inset       24.64 / 112   = 22%    of the tile

The mark sits a hair below centre — that is the design, not a rounding error;
the hands reach up and to the right, so optical centre is below geometric.

Each variant's tile is a top-left → bottom-right gradient between two stops of
the brand ramp in `app/lib/theme/tokens.dart` (a flat tile read as a plain
green blob at launcher sizes, 2026-08-15):

    light   #E8F7F0 → #C7EBDC tile, #0B8560 mark    iOS light appearance
    dark    #182822 → #0B1512 tile, #34D399 mark    iOS dark appearance
    solid   #2FB588 → #065F46 tile, #FFFFFF mark    everything with one slot

Desktops and the Android launcher get `solid`: green reads on both a light and
a dark shelf, where the pale `light` tile vanishes on white and `dark` vanishes
on black. iOS is the one target that genuinely swaps, so it carries all three
(plus the greyscale `tinted` appearance iOS 18 composites the user's colour
onto — that one stays flat, iOS wants luminance range there, not brand).

Alongside every plain icon the script emits its **running-timer** companions —
the same tile with a red recording dot in the lower-right corner — for the
platforms that badge by swapping an image: the Linux hicolor tree gains
`<id>-running` icons, macOS an `AppIconRunning` imageset for the dock, and
Windows a `badge_overlay.ico` for the taskbar overlay (that one is the dot
alone; Windows composites it over the live icon itself).

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
# ones that cross a stroke square-on). As an app icon those hairlines are built
# up to a constant optical weight of LINE_UNITS (~3.4% of the mark's width) by
# stroking the path in its own fill colour. Constant, not tapered by raster
# size: an xxxhdpi launcher icon is 192px yet physically ten millimetres, so
# pixel count stopped predicting how thick a line looks — the earlier px-tapered
# boost left every launcher a green blob with a faint scribble on it
# (2026-08-15). MIN_STROKE_PX stays as a floor for favicon-class sizes where
# even LINE_UNITS falls under a pixel.
HAIRLINE_UNITS = 0.9
LINE_UNITS = 2.2
MIN_STROKE_PX = 0.75

# The running-timer badge: a recording dot (the theme's danger red) ringed in
# white so it separates from the tile, tucked into the lower-right corner. All
# fractions of the tile.
BADGE_CENTER = 0.79
BADGE_RADIUS = 0.145
BADGE_RING = 0.045
BADGE_FILL = "#DC2626"
BADGE_RING_FILL = "#FFFFFF"


@dataclass(frozen=True)
class Variant:
    """A tile as a (top-left, bottom-right) gradient pair — equal stops mean
    flat — and the mark's colour."""

    tile: tuple[str, str]
    mark: str


VARIANTS = {
    "light": Variant(tile=("#E8F7F0", "#C7EBDC"), mark="#0B8560"),
    "dark": Variant(tile=("#182822", "#0B1512"), mark="#34D399"),
    "solid": Variant(tile=("#2FB588", "#065F46"), mark="#FFFFFF"),
    # iOS composites the user's tint over this one, so it wants maximum
    # luminance range rather than brand colour — flat black, no gradient.
    "tinted": Variant(tile=("#000000", "#000000"), mark="#FFFFFF"),
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
    badge: bool = False,
    px: int | None = None,
) -> str:
    """Builds one square icon as SVG.

    `body` is the tile's rect within the canvas, defaulting to the whole
    canvas. `radius` is a fraction of the body's width; pass 0 for the
    full-bleed square iOS and the Play Store want. `draw_tile=False` emits the
    mark alone on transparency, which is what an Android adaptive foreground
    and its monochrome sibling are. `badge` adds the running-timer dot. `px`
    is the pixel size the result will be rasterised at, and only affects the
    MIN_STROKE_PX floor; leave it unset for output that stays vector.
    """
    bx, by, bw, bh = body if body else (0.0, 0.0, canvas, canvas)

    mw = bw * MARK_W
    mh = mw * MARK_ASPECT
    mx = bx + bw * MARK_LEFT
    my = by + bh * MARK_TOP

    defs = ""
    tile = ""
    if draw_tile:
        top, bottom = variant.tile
        if top == bottom:
            fill = top
        else:
            fill = "url(#tile)"
            defs = (
                '<defs><linearGradient id="tile" x1="0" y1="0" x2="1" y2="1">'
                f'<stop offset="0" stop-color="{top}"/>'
                f'<stop offset="1" stop-color="{bottom}"/>'
                "</linearGradient></defs>"
            )
        rx = f' rx="{bw * radius:.4f}" ry="{bw * radius:.4f}"' if radius else ""
        tile = (
            f'<rect x="{bx:.4f}" y="{by:.4f}" width="{bw:.4f}" '
            f'height="{bh:.4f}"{rx} fill="{fill}"/>'
        )

    mark = MARK_BODY.replace("fill:#000000", f"fill:{variant.mark}")

    boost = LINE_UNITS - HAIRLINE_UNITS
    if px:
        mark_px = mw / canvas * px
        line_px = LINE_UNITS / MARK_VB_W * mark_px
        if line_px < MIN_STROKE_PX:
            boost += (MIN_STROKE_PX - line_px) * MARK_VB_W / mark_px
    mark = thicken(mark, variant.mark, boost)

    dot = ""
    if badge:
        cx = bx + bw * BADGE_CENTER
        cy = by + bh * BADGE_CENTER
        dot = (
            f'<circle cx="{cx:.4f}" cy="{cy:.4f}" '
            f'r="{bw * BADGE_RADIUS:.4f}" fill="{BADGE_FILL}" '
            f'stroke="{BADGE_RING_FILL}" stroke-width="{bw * BADGE_RING:.4f}"/>'
        )

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{canvas:g}" '
        f'height="{canvas:g}" viewBox="0 0 {canvas:g} {canvas:g}">'
        f"{defs}{tile}"
        f'<svg x="{mx:.4f}" y="{my:.4f}" width="{mw:.4f}" height="{mh:.4f}" '
        f'viewBox="0 0 {MARK_VB_W} {MARK_VB_H}">{mark}</svg>'
        f"{dot}</svg>"
    )


def compose_glyph(canvas: float, colour: str, *, width_frac: float,
                  line_units: float, px: int | None = None) -> str:
    """The mark alone, centred — Android's status-bar notification icon.

    Its own composition rather than `compose(draw_tile=False)`: the adaptive
    foreground sits inside the 72dp safe zone and status-bar icons are drawn
    at 24dp, where that inset leaves an unreadable speck. `line_units` is
    passed in because a silhouette this small wants more weight than the app
    icon's LINE_UNITS.
    """
    mw = canvas * width_frac
    mh = mw * MARK_ASPECT
    mx = (canvas - mw) / 2
    my = (canvas - mh) / 2

    mark = MARK_BODY.replace("fill:#000000", f"fill:{colour}")
    boost = line_units - HAIRLINE_UNITS
    if px:
        mark_px = mw / canvas * px
        line_px = line_units / MARK_VB_W * mark_px
        if line_px < MIN_STROKE_PX:
            boost += (MIN_STROKE_PX - line_px) * MARK_VB_W / mark_px
    mark = thicken(mark, colour, boost)

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{canvas:g}" '
        f'height="{canvas:g}" viewBox="0 0 {canvas:g} {canvas:g}">'
        f'<svg x="{mx:.4f}" y="{my:.4f}" width="{mw:.4f}" height="{mh:.4f}" '
        f'viewBox="0 0 {MARK_VB_W} {MARK_VB_H}">{mark}</svg></svg>'
    )


def compose_overlay(canvas: float) -> str:
    """The badge dot alone, for Windows' taskbar overlay slot.

    Windows draws the overlay over the taskbar icon itself, so unlike the
    badged icons this is just the dot, sized to fill the (16px-class) canvas.
    """
    c = canvas / 2
    ring = canvas * 0.11
    r = canvas * 0.42 - ring / 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{canvas:g}" '
        f'height="{canvas:g}" viewBox="0 0 {canvas:g} {canvas:g}">'
        f'<circle cx="{c:g}" cy="{c:g}" r="{r:.4f}" fill="{BADGE_FILL}" '
        f'stroke="{BADGE_RING_FILL}" stroke-width="{ring:.4f}"/></svg>'
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

    # The dock icon the runner swaps in while a timer runs
    # (macos/Runner/MainFlutterWindow.swift). An image set rather than a
    # second app-icon set: NSImage(named:) is how it is looked up.
    running = d.parent / "AppIconRunning.imageset"
    badged = lambda px: compose(1024, VARIANTS["solid"], body=body, badge=True, px=px)
    render(badged, running / "app_icon_running_256.png", 256)
    render(badged, running / "app_icon_running_512.png", 512)
    (running / "Contents.json").write_text(
        '{\n  "images" : [\n'
        '    {\n      "filename" : "app_icon_running_256.png",\n'
        '      "idiom" : "universal",\n      "scale" : "1x"\n    },\n'
        '    {\n      "filename" : "app_icon_running_512.png",\n'
        '      "idiom" : "universal",\n      "scale" : "2x"\n    }\n'
        "  ],\n"
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n',
        encoding="utf-8",
    )
    print(f"  {d.relative_to(ROOT)}/ — 7 sizes, solid + AppIconRunning")


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
    mono_variant = Variant(tile=("#000000", "#000000"), mark="#FFFFFF")
    monochrome = lambda px: compose(ADAPTIVE_CANVAS, mono_variant, body=safe,
                                    draw_tile=False, px=px)
    for bucket, size in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                         ("xxhdpi", 324), ("xxxhdpi", 432)):
        render(foreground, res / f"mipmap-{bucket}" / "ic_launcher_foreground.png", size)
        render(monochrome, res / f"mipmap-{bucket}" / "ic_launcher_monochrome.png", size)

    # The adaptive background is the tile gradient as a drawable — a colour
    # resource can only be flat. Angle 315 is Android's top-left → bottom-right.
    stale_colour = res / "values" / "ic_launcher_background.xml"
    if stale_colour.exists():
        stale_colour.unlink()
    (res / "drawable").mkdir(parents=True, exist_ok=True)
    (res / "drawable" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android">\n'
        "    <gradient\n"
        f'        android:startColor="{solid.tile[0]}"\n'
        f'        android:endColor="{solid.tile[1]}"\n'
        '        android:angle="315" />\n'
        "</shape>\n",
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
        '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )

    # Status-bar icon for the running-timer notification (TimerBadge.kt):
    # white silhouette on transparency, as the status bar requires.
    stat = lambda px: compose_glyph(1024, "#FFFFFF", width_frac=0.92,
                                    line_units=3.5, px=px)
    for bucket, size in (("mdpi", 24), ("hdpi", 36), ("xhdpi", 48),
                         ("xxhdpi", 72), ("xxxhdpi", 96)):
        render(stat, res / f"drawable-{bucket}" / "ic_stat_timer.png", size)

    # Play Console listing icon: 512 square, no transparency, no baked mask.
    render(lambda px: compose(1024, solid, radius=0, px=px),
           ICON_DIR / "play-store-512.png", 512, opaque=True)
    print("  app/android/.../res/ — legacy, adaptive, monochrome, ic_stat_timer"
          " + play-store-512.png")


def gen_windows() -> None:
    """A multi-resolution .ico; Windows picks the size, and never masks."""
    d = APP / "windows" / "runner" / "resources"
    d.mkdir(parents=True, exist_ok=True)

    def ico(out: Path, svg_for: Callable[[int], str], sizes: tuple[int, ...]) -> None:
        staged = [render(svg_for, out.parent / f".ico-{s}.png", s) for s in sizes]
        run(["magick", *[str(p) for p in staged], str(out)])
        for p in staged:
            p.unlink()

    ico(d / "app_icon.ico", lambda px: compose(1024, VARIANTS["solid"], px=px),
        (16, 20, 24, 32, 40, 48, 64, 128, 256))
    # The running-timer overlay the runner hands to ITaskbarList3 — the badge
    # dot alone, in the small-icon sizes the overlay slot is drawn at.
    ico(d / "badge_overlay.ico", lambda px: compose_overlay(1024),
        (16, 20, 24, 32))
    print(f"  {d.relative_to(ROOT)}/ — app_icon.ico (9 sizes), badge_overlay.ico (4)")


def gen_linux() -> None:
    """A hicolor tree the runner reads at run time and a package can install."""
    d = APP / "linux" / "runner" / "resources"
    # The plain icon and its running-timer companion; my_application.cc swaps
    # the window icon between the two by name.
    for name, badge in ((APPLICATION_ID, False), (f"{APPLICATION_ID}-running", True)):
        svg_for = lambda px, b=badge: compose(1024, VARIANTS["solid"], badge=b, px=px)
        for size in (16, 22, 24, 32, 48, 64, 128, 256, 512):
            render(svg_for, d / "icons" / "hicolor" / f"{size}x{size}" / "apps"
                   / f"{name}.png", size)
        scalable = d / "icons" / "hicolor" / "scalable" / "apps" / f"{name}.svg"
        scalable.parent.mkdir(parents=True, exist_ok=True)
        scalable.write_text(compose(512, VARIANTS["solid"], badge=badge),
                            encoding="utf-8")

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
    print(f"  {d.relative_to(ROOT)}/ — hicolor 16–512 + -running, scalable, .desktop")


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
