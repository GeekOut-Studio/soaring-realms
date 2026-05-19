"""Compose a transparent square icon PNG from a white/black background pair.

Usage: python scripts/process-icon.py <white.png> <black.png> <out.png>

For each pixel:
    C_w = alpha * F + (1 - alpha) * (1,1,1)
    C_b = alpha * F + (1 - alpha) * (0,0,0)
=> alpha = 1 - mean(C_w - C_b) across RGB
   F     = C_b / alpha   (clamped; foreground undefined where alpha ~ 0)

Crop tightly to the alpha bounding box with a small uniform padding, then
expand to a square centered on the subject.
"""

import sys

import numpy as np
from PIL import Image

ALPHA_THRESHOLD = 0.05  # pixels with alpha below this are treated as "background" for bbox
PAD_RATIO = 0.04  # fraction of bbox side added on every edge before squaring
MAX_SIDE = 128  # downscale square output to this size; passthrough if already smaller


def main(white_path: str, black_path: str, out_path: str) -> None:
    w = np.asarray(Image.open(white_path).convert("RGB"), dtype=np.float32) / 255.0
    b = np.asarray(Image.open(black_path).convert("RGB"), dtype=np.float32) / 255.0
    if w.shape != b.shape:
        raise SystemExit(f"size mismatch: white={w.shape} black={b.shape}")

    diff = np.clip(w - b, 0.0, 1.0)
    alpha = 1.0 - diff.mean(axis=2)
    alpha = np.clip(alpha, 0.0, 1.0)

    eps = 1e-3
    safe_alpha = np.maximum(alpha, eps)[..., None]
    f = np.clip(b / safe_alpha, 0.0, 1.0)
    f = np.where(alpha[..., None] > eps, f, 0.0)

    rgba = (np.dstack([f, alpha]) * 255.0).round().astype(np.uint8)
    height, width = rgba.shape[:2]

    mask = alpha > ALPHA_THRESHOLD
    if mask.any():
        rows = np.where(mask.any(axis=1))[0]
        cols = np.where(mask.any(axis=0))[0]
        top, bottom = int(rows[0]), int(rows[-1]) + 1
        left, right = int(cols[0]), int(cols[-1]) + 1
    else:
        top, bottom, left, right = 0, height, 0, width

    bbox_side = max(right - left, bottom - top)
    pad = int(round(bbox_side * PAD_RATIO))
    side = bbox_side + 2 * pad
    cx = (left + right) // 2
    cy = (top + bottom) // 2

    # Place the square centered on the subject; nudge inward if it'd run off the source.
    out_left = cx - side // 2
    out_top = cy - side // 2
    out_right = out_left + side
    out_bottom = out_top + side

    # Compose onto a transparent RGBA canvas of size×side; copy whatever overlaps the source.
    canvas = np.zeros((side, side, 4), dtype=np.uint8)
    src_left = max(out_left, 0)
    src_top = max(out_top, 0)
    src_right = min(out_right, width)
    src_bottom = min(out_bottom, height)
    if src_right > src_left and src_bottom > src_top:
        dst_left = src_left - out_left
        dst_top = src_top - out_top
        canvas[
            dst_top : dst_top + (src_bottom - src_top),
            dst_left : dst_left + (src_right - src_left),
        ] = rgba[src_top:src_bottom, src_left:src_right]

    img = Image.fromarray(canvas, "RGBA")
    if img.width > MAX_SIDE:
        img = img.resize((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    img.save(out_path, "PNG")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: process-icon.py <white.png> <black.png> <out.png>")
    main(sys.argv[1], sys.argv[2], sys.argv[3])
