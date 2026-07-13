#!/usr/bin/env python3
"""Render deterministic, privacy-safe media for the MacList Actions README."""

from __future__ import annotations

import math
import hashlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets"
FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_MONO = "/System/Library/Fonts/SFNSMono.ttf"

BG = "#0B1020"
PANEL = "#141B2D"
PANEL_2 = "#1C253A"
TEXT = "#F7F9FC"
MUTED = "#9BA7BC"
LINE = "#2B3853"
GOLD = "#F5C451"
MINT = "#68D5B0"
BLUE = "#73A8FF"


def font(size: int, *, mono: bool = False, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_MONO if mono else FONT_REGULAR
    face = ImageFont.truetype(path, size=size)
    if bold:
        try:
            face.set_variation_by_name("Bold")
        except (AttributeError, OSError):
            pass
    return face


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], radius: int, fill: str, outline: str | None = None, width: int = 1) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, *, size: int, fill: str = TEXT, mono: bool = False, bold: bool = False, anchor: str | None = None) -> None:
    draw.text(xy, text, font=font(size, mono=mono, bold=bold), fill=fill, anchor=anchor)


def pill(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, color: str) -> int:
    face = font(15, mono=True, bold=True)
    width = int(draw.textlength(text, font=face)) + 28
    rounded(draw, (x, y, x + width, y + 32), 16, PANEL_2, color, 1)
    draw.text((x + width // 2, y + 16), text, font=face, fill=color, anchor="mm")
    return width


def search_panel(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, query: str, selected: int = 0, action: str | None = None, complete: bool = False) -> None:
    h = 390
    rounded(draw, (x, y, x + w, y + h), 24, PANEL, LINE, 2)
    draw.ellipse((x + 24, y + 20, x + 36, y + 32), fill="#FF6B6B")
    draw.ellipse((x + 44, y + 20, x + 56, y + 32), fill=GOLD)
    draw.ellipse((x + 64, y + 20, x + 76, y + 32), fill=MINT)

    rounded(draw, (x + 22, y + 54, x + w - 22, y + 108), 14, "#0F1525", LINE, 1)
    draw.ellipse((x + 40, y + 72, x + 56, y + 88), outline=MUTED, width=2)
    draw.line((x + 53, y + 85, x + 61, y + 93), fill=MUTED, width=2)
    label(draw, (x + 72, y + 81), query or "Search files and actions", size=20, fill=TEXT if query else MUTED, anchor="lm")
    label(draw, (x + w - 42, y + 81), "esc", size=13, fill=MUTED, mono=True, anchor="rm")

    files = [
        ("PDF", "Project Atlas - Valve Quote.pdf", "Documents / Atlas", GOLD),
        ("XLSX", "Project Atlas - Datasheet.xlsx", "Documents / Atlas", MINT),
        ("DOCX", "Northwind - Inspection Report.docx", "Documents / Northwind", BLUE),
    ]
    row_y = y + 118
    for index, (kind, name, path, color) in enumerate(files):
        active = selected == index and bool(query)
        if active:
            rounded(draw, (x + 18, row_y - 4, x + w - 18, row_y + 68), 13, PANEL_2, color, 1)
        rounded(draw, (x + 32, row_y + 7, x + 76, row_y + 51), 9, "#0E1424", color, 1)
        label(draw, (x + 54, row_y + 29), kind, size=10, fill=color, mono=True, bold=True, anchor="mm")
        label(draw, (x + 92, row_y + 18), name, size=16, fill=TEXT, bold=active)
        label(draw, (x + 92, row_y + 43), path, size=13, fill=MUTED)
        if active:
            label(draw, (x + w - 38, row_y + 29), "return", size=11, fill=color, mono=True, anchor="rm")
        row_y += 70

    action_y = y + h - 46
    draw.line((x + 22, action_y - 14, x + w - 22, action_y - 14), fill=LINE, width=1)
    if complete:
        draw.ellipse((x + 26, action_y - 2, x + 44, action_y + 16), fill=MINT)
        label(draw, (x + 35, action_y + 7), "✓", size=13, fill=BG, bold=True, anchor="mm")
        label(draw, (x + 54, action_y + 7), "Files copied. Mail opened. You press Send.", size=14, fill=MINT, anchor="lm")
    elif action:
        label(draw, (x + 28, action_y + 7), "ACTION", size=11, fill=MUTED, mono=True, bold=True, anchor="lm")
        label(draw, (x + 104, action_y + 7), action, size=15, fill=GOLD, bold=True, anchor="lm")
        label(draw, (x + w - 28, action_y + 7), "⌘M", size=13, fill=MUTED, mono=True, anchor="rm")
    else:
        label(draw, (x + 28, action_y + 7), "Open  ·  Reveal  ·  Preview  ·  Handoff", size=14, fill=MUTED, anchor="lm")


def social_preview() -> Image.Image:
    image = Image.new("RGB", (1280, 640), BG)
    draw = ImageDraw.Draw(image)

    # Subtle local graph motif, kept behind text for reliable readability.
    for i in range(7):
        cx = 1090 + int(math.cos(i * 0.9) * (90 + i * 11))
        cy = 110 + i * 72
        draw.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), fill=LINE)
        if i:
            px = 1090 + int(math.cos((i - 1) * 0.9) * (90 + (i - 1) * 11))
            py = 110 + (i - 1) * 72
            draw.line((px, py, cx, cy), fill="#22304B", width=2)

    label(draw, (72, 72), "MACLIST ACTIONS", size=17, fill=GOLD, mono=True, bold=True)
    label(draw, (72, 126), "Find the file.", size=62, fill=TEXT, bold=True)
    label(draw, (72, 198), "Hand it off.", size=62, fill=TEXT, bold=True)
    label(draw, (72, 270), "You press Send.", size=62, fill=MINT, bold=True)
    label(draw, (74, 362), "Fast, local-first file handoff for macOS.", size=23, fill=MUTED)
    label(draw, (74, 398), "Now with Apple Mail, Outlook, and a standalone search core.", size=20, fill=MUTED)
    p1 = pill(draw, 72, 466, "LOCAL-FIRST", MINT)
    p2 = pill(draw, 72 + p1 + 12, 466, "NO AUTO-SEND", GOLD)
    pill(draw, 72 + p1 + p2 + 24, 466, "OPEN SOURCE", BLUE)
    label(draw, (74, 544), "github.com/xffighting/maclist-actions", size=17, fill="#7888A4", mono=True)

    search_panel(draw, 700, 116, 500, "atlas quote", selected=0, action="Apple Mail")
    return image


def demo_frame(frame: int, total: int = 120) -> Image.Image:
    image = Image.new("RGB", (960, 540), BG)
    draw = ImageDraw.Draw(image)
    label(draw, (42, 34), "MACLIST ACTIONS", size=15, fill=GOLD, mono=True, bold=True)
    label(draw, (918, 34), "SYNTHETIC DEMO · NO PERSONAL DATA", size=12, fill=MUTED, mono=True, anchor="ra")

    query_text = "atlas quote"
    if frame < 10:
        query = ""
    elif frame < 38:
        chars = max(0, min(len(query_text), (frame - 10) // 2 + 1))
        query = query_text[:chars]
    else:
        query = query_text

    selected = 0
    action = None
    complete = False
    if 58 <= frame < 88:
        action = "Apple Mail"
    elif frame >= 88:
        complete = True

    search_panel(draw, 180, 76, 600, query, selected=selected, action=action, complete=complete)

    if frame < 10:
        rounded(draw, (327, 461, 633, 509), 18, PANEL_2, LINE, 1)
        label(draw, (480, 485), "Press your launcher hotkey", size=17, fill=TEXT, anchor="mm")
    elif 38 <= frame < 58:
        label(draw, (480, 485), "1 result in 1.3 ms", size=15, fill=MUTED, mono=True, anchor="mm")
    elif 58 <= frame < 88:
        label(draw, (480, 485), "Choose a handoff action", size=16, fill=GOLD, anchor="mm")
    else:
        label(draw, (480, 485), "Recipient and Send stay under your control", size=16, fill=MINT, anchor="mm")

    return image


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)

    preview = social_preview()
    preview.save(ASSETS / "social-preview.png", optimize=True)

    frames = [demo_frame(i) for i in range(120)]
    frames[0].save(
        ASSETS / "maclist-demo.gif",
        save_all=True,
        append_images=frames[1:],
        duration=100,
        loop=0,
        optimize=True,
        disposal=2,
    )
    frames[42].save(ASSETS / "demo-poster.png", optimize=True)

    with Image.open(ASSETS / "social-preview.png") as rendered_preview:
        assert rendered_preview.size == (1280, 640)
    with Image.open(ASSETS / "maclist-demo.gif") as rendered_demo:
        assert rendered_demo.size == (960, 540)
        durations = []
        for frame_index in range(rendered_demo.n_frames):
            rendered_demo.seek(frame_index)
            durations.append(rendered_demo.info.get("duration", 0))
        assert rendered_demo.n_frames >= 10
        assert sum(durations) == 12_000

    for asset in ("social-preview.png", "maclist-demo.gif", "demo-poster.png"):
        path = ASSETS / asset
        digest = hashlib.sha256(path.read_bytes()).hexdigest()[:12]
        print(f"{asset}: {path.stat().st_size} bytes sha256:{digest}")


if __name__ == "__main__":
    main()
