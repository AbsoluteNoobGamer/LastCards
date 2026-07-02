"""Batch-import AI-generated card back / joker cover art into the project.

Takes a folder of freshly generated images (any size, any aspect ratio) and
normalizes them to the correct portrait card aspect ratio before dropping
them into assets/images/cardbackcover or assets/images/jokercover, ready to
show up in the Locker's Card backs / Jokers tabs.

Requires Pillow:
    pip3 install Pillow

Usage:
    # Card backs, cropped to fill the card shape edge-to-edge (default)
    python3 tools/batch_import_cosmetics.py --source ~/Downloads/new_backs --kind backs

    # Joker covers, padded instead of cropped (keeps the whole image, adds
    # a solid border where needed instead of cutting anything off)
    python3 tools/batch_import_cosmetics.py --source ~/Downloads/new_jokers --kind jokers --mode contain

    # Preview what would happen without writing anything
    python3 tools/batch_import_cosmetics.py --source ~/Downloads/new_backs --kind backs --dry-run

Notes:
    - Output filenames become the display label in the Locker (e.g.
      "Midnight Fox.png" shows up as "Midnight Fox"), so name your source
      files the way you want them to read in-game.
    - "cover" mode (default) fills the full card shape with no empty
      margin, cropping some of the top/bottom or sides as needed. This is
      almost always what you want for card backs and joker art meant to
      look like a full-bleed printed card.
    - "contain" mode fits the whole image inside the card shape without
      cropping, padding any leftover space with --pad-color. Use this if
      the source image is precious and you don't want any of it cut off.
    - Existing files are never overwritten; a numeric suffix is added on
      collision (e.g. "Midnight Fox (2).png").
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow is required. Install it with: pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

# Standard poker card ratio (2.5in x 3.5in).
CARD_ASPECT = 2.5 / 3.5

SOURCE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}

KIND_TARGETS = {
    "backs": Path("assets/images/cardbackcover"),
    "jokers": Path("assets/images/jokercover"),
}


def fit_to_card(im: Image.Image, mode: str, target_height: int, pad_color: tuple[int, int, int, int]) -> Image.Image:
    """Return a new image normalized to CARD_ASPECT at the given height."""
    target_w = round(target_height * CARD_ASPECT)
    target_h = target_height

    if im.mode not in ("RGB", "RGBA"):
        im = im.convert("RGBA" if "A" in im.getbands() else "RGB")

    src_w, src_h = im.size
    src_aspect = src_w / src_h

    if mode == "cover":
        # Scale so the image fully covers the target box, then center-crop.
        scale = max(target_w / src_w, target_h / src_h)
        new_w, new_h = round(src_w * scale), round(src_h * scale)
        resized = im.resize((new_w, new_h), Image.LANCZOS)
        left = (new_w - target_w) // 2
        top = (new_h - target_h) // 2
        return resized.crop((left, top, left + target_w, top + target_h))

    # contain: scale so the whole image fits inside the box, pad the rest.
    scale = min(target_w / src_w, target_h / src_h)
    new_w, new_h = round(src_w * scale), round(src_h * scale)
    resized = im.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (target_w, target_h), pad_color)
    canvas.paste(resized, ((target_w - new_w) // 2, (target_h - new_h) // 2), resized if resized.mode == "RGBA" else None)
    return canvas


def unique_destination(target_dir: Path, stem: str, suffix: str) -> Path:
    candidate = target_dir / f"{stem}{suffix}"
    n = 2
    while candidate.exists():
        candidate = target_dir / f"{stem} ({n}){suffix}"
        n += 1
    return candidate


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, help="Folder of freshly generated images to import")
    parser.add_argument("--kind", choices=sorted(KIND_TARGETS), required=True, help="Which Locker category these belong to")
    parser.add_argument("--mode", choices=["cover", "contain"], default="cover", help="cover = fill and crop (default); contain = fit and pad")
    parser.add_argument("--target-height", type=int, default=1200, help="Output pixel height (default 1200, width derived from card aspect ratio)")
    parser.add_argument("--pad-color", default="255,255,255,255", help="R,G,B,A used for padding in contain mode (default opaque white)")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing any files")
    args = parser.parse_args()

    source_dir = Path(args.source).expanduser()
    if not source_dir.is_dir():
        print(f"Source folder not found: {source_dir}", file=sys.stderr)
        sys.exit(1)

    target_dir = KIND_TARGETS[args.kind]
    pad_color = tuple(int(c) for c in args.pad_color.split(","))
    if len(pad_color) != 4:
        print("--pad-color must be R,G,B,A (four numbers)", file=sys.stderr)
        sys.exit(1)

    if not args.dry_run:
        target_dir.mkdir(parents=True, exist_ok=True)

    images = sorted(p for p in source_dir.iterdir() if p.suffix.lower() in SOURCE_EXTENSIONS)
    if not images:
        print(f"No images found in {source_dir} (looked for {', '.join(sorted(SOURCE_EXTENSIONS))})")
        return

    processed = 0
    for src in images:
        try:
            with Image.open(src) as im:
                out = fit_to_card(im, args.mode, args.target_height, pad_color)
        except Exception as e:  # noqa: BLE001 - report and continue with the rest of the batch
            print(f"  SKIP  {src.name}: {e}")
            continue

        dest = unique_destination(target_dir, src.stem, ".png")
        if args.dry_run:
            print(f"  WOULD WRITE  {dest}  ({out.size[0]}x{out.size[1]})")
        else:
            out.save(dest, "PNG")
            print(f"  WROTE  {dest}  ({out.size[0]}x{out.size[1]})")
        processed += 1

    verb = "Would import" if args.dry_run else "Imported"
    print(f"\n{verb} {processed}/{len(images)} image(s) into {target_dir}/")
    if not args.dry_run and processed:
        print("Hot-reload the app to see them in the Locker.")


if __name__ == "__main__":
    main()
