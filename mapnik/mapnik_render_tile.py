#!/usr/bin/env python3
"""
Render a single PNG tile with Mapnik to verify your DB/style setup.

Usage (example):
  python3 mapnik_render_tile.py --style opentopomap.xml --out opentopomap_output.png \
    --z 13 --x 1320 --y 2860

Defaults match the old test.
"""

import os
import sys
import argparse
import mapnik


def tile2prjbounds(settings, x, y, z):
    """
    Compute projected bounds (EPSG:3857) for a Z/X/Y tile region.

    :param settings: geometry settings dict
    :param x: tile x
    :param y: tile y
    :param z: tile zoom
    :return: (x0, y0, x1, y1)
    """
    render_size_tx = min(8, settings['aspect_x'] * (1 << z))
    render_size_ty = min(8, settings['aspect_y'] * (1 << z))

    prj_width  = settings['bound_x1'] - settings['bound_x0']
    prj_height = settings['bound_y1'] - settings['bound_y0']

    p0x = settings['bound_x0'] + prj_width  * (float(x) / (settings['aspect_x'] * (1 << z)))
    p0y = settings['bound_y1'] - prj_height * ((float(y) + render_size_ty) / (settings['aspect_y'] * (1 << z)))
    p1x = settings['bound_x0'] + prj_width  * ((float(x) + render_size_tx) / (settings['aspect_x'] * (1 << z)))
    p1y = settings['bound_y1'] - prj_height * (float(y) / (settings['aspect_y'] * (1 << z)))

    return p0x, p0y, p1x, p1y


def register_fonts(extra_dirs=None):
    """Register system fonts (and optional extra dirs) for Mapnik."""
    try:
        # Register distro/system fonts (works on Ubuntu 24.04)
        mapnik.register_system_fonts()
    except Exception:
        # Older Mapniks may not have this helper; ignore if missing
        pass

    # Register additional directories (recursively)
    for d in (extra_dirs or []):
        if os.path.isdir(d):
            try:
                mapnik.register_fonts(d, True)
            except Exception as e:
                print(f"[warn] Could not register fonts in {d}: {e}", file=sys.stderr)

    # Also register common locations explicitly (recursive)
    for d in ("/usr/share/fonts",
              "/usr/local/share/fonts",
              os.path.expanduser("~/.local/share/fonts")):
        if os.path.isdir(d):
            try:
                mapnik.register_fonts(d, True)
            except Exception as e:
                print(f"[warn] Could not register fonts in {d}: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Render a PNG tile with Mapnik.")
    parser.add_argument("--style", "-s", default="opentopomap.xml", help="Mapnik XML stylesheet")
    parser.add_argument("--out", "-o", default="opentopomap_output.png", help="Output PNG path")
    parser.add_argument("--width", type=int, default=2048, help="Image width in pixels")
    parser.add_argument("--height", type=int, default=2048, help="Image height in pixels")
    parser.add_argument("--z", type=int, default=13, help="Zoom")
    parser.add_argument("--x", type=int, default=1320, help="Tile X")
    parser.add_argument("--y", type=int, default=2860, help="Tile Y")
    args = parser.parse_args()

    if not os.path.exists(args.style):
        print(f"[error] Stylesheet not found: {args.style}", file=sys.stderr)
        sys.exit(1)

    register_fonts()

    m = mapnik.Map(args.width, args.height)
    mapnik.load_map(m, args.style)

    # Web Mercator bounds in meters
    geom_settings = {
        'bound_x0': -20037508.3428,
        'bound_x1':  20037508.3428,
        'bound_y0': -20037508.3428,
        'bound_y1':  20037508.3428,
        'aspect_x': 1.0,
        'aspect_y': 1.0,
    }

    p0x, p0y, p1x, p1y = tile2prjbounds(geom_settings, args.x, args.y, args.z)
    bbox = mapnik.Box2d(p0x, p0y, p1x, p1y)
    m.zoom_to_box(bbox)

    print(f"[info] Envelope: {m.envelope()}")
    print(f"[info] Scale: {m.scale()}")

    mapnik.render_to_file(m, args.out)
    print(f"[ok] Wrote {args.out}")


if __name__ == "__main__":
    main()


