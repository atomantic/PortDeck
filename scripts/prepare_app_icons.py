"""Remove App Store icon alpha using the deployment environment's Pillow."""
import sys
from pathlib import Path
from PIL import Image


def prepare_icons(directory):
    changed = 0
    for path in Path(directory).glob("*.png"):
        with Image.open(path) as image:
            if image.mode == "RGB":
                continue
            rgba = image.convert("RGBA")
            background = Image.new("RGB", image.size, (0, 0, 0))
            background.paste(rgba, mask=rgba.getchannel("A"))
            background.save(path)
            changed += 1
    return changed


if __name__ == "__main__":
    print(f"Prepared {prepare_icons(sys.argv[1])} App Store icons")
