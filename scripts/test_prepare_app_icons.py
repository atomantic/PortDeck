"""Deployment regression: icons are opaque and conversion is repeatable."""
import tempfile
import unittest
from pathlib import Path
from PIL import Image
from prepare_app_icons import prepare_icons


class PrepareIconsTests(unittest.TestCase):
    def test_deploy_converts_transparency_and_preserves_existing_rgb(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            Image.new("RGBA", (2, 2), (255, 0, 0, 128)).save(root / "alpha.png")
            Image.new("RGB", (2, 2), (1, 2, 3)).save(root / "rgb.png")
            original = (root / "rgb.png").read_bytes()
            self.assertEqual(prepare_icons(root), 1)
            with Image.open(root / "alpha.png") as image:
                self.assertEqual(image.mode, "RGB")
                self.assertEqual(image.getpixel((0, 0)), (128, 0, 0))
            self.assertEqual((root / "rgb.png").read_bytes(), original)
            self.assertEqual(prepare_icons(root), 0)
