from PIL import Image, ImageDraw
from pathlib import Path


OUT = Path(r"C:\Users\home\Documents\Codex\2026-06-20\new-chat\outputs\VideoRotatePortable")


def make_icon(size: int) -> Image.Image:
    scale = size / 256
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def p(v):
        if isinstance(v, tuple):
            return tuple(int(round(x * scale)) for x in v)
        return int(round(v * scale))

    # Rounded app tile.
    draw.rounded_rectangle(
        [p(20), p(20), p(236), p(236)],
        radius=p(44),
        fill=(24, 28, 38, 255),
        outline=(72, 88, 116, 255),
        width=max(1, p(4)),
    )

    # Video frame.
    draw.rounded_rectangle(
        [p(58), p(78), p(198), p(174)],
        radius=p(18),
        fill=(41, 49, 66, 255),
        outline=(126, 225, 255, 255),
        width=max(2, p(7)),
    )

    # Film perforations.
    for x in (76, 104, 132, 160):
        draw.rounded_rectangle(
            [p(x), p(92), p(x + 13), p(105)],
            radius=p(3),
            fill=(126, 225, 255, 220),
        )
        draw.rounded_rectangle(
            [p(x), p(148), p(x + 13), p(161)],
            radius=p(3),
            fill=(126, 225, 255, 220),
        )

    # Play triangle.
    draw.polygon(
        [p((113, 111)), p((113, 141)), p((143, 126))],
        fill=(255, 255, 255, 245),
    )

    # Rotation arc.
    stroke = max(3, p(13))
    box = [p(52), p(42), p(204), p(208)]
    draw.arc(box, start=30, end=325, fill=(255, 178, 65, 255), width=stroke)

    # Arrow head.
    draw.polygon(
        [p((196, 70)), p((226, 65)), p((211, 94))],
        fill=(255, 178, 65, 255),
    )

    # Small highlight.
    draw.arc([p(68), p(58), p(188), p(192)], start=210, end=280, fill=(255, 224, 142, 210), width=max(2, p(5)))
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    png = make_icon(512)
    png.save(OUT / "RotateIcon.png")
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    png.save(OUT / "RotateIcon.ico", sizes=sizes)


if __name__ == "__main__":
    main()
