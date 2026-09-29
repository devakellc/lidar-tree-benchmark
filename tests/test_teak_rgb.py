"""Focused checks for raw RGB comparison and raster grid admission."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

import numpy as np
import rasterio
from rasterio.transform import from_origin

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "compare_teak_rgb.py"
SPEC = importlib.util.spec_from_file_location("teak_rgb", SCRIPT)
RGB = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RGB)


class RGBComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pixels = np.array([[[1, 255], [2, 3]]] * 3, dtype=np.uint8)

    def write(self, name, pixels=None, nodata=None, x=1000, crs="EPSG:32611"):
        path = self.root / name
        with rasterio.open(path, "w", driver="GTiff", width=2, height=2,
                           count=3, dtype="uint8", nodata=nodata, crs=crs,
                           transform=from_origin(x, 2000, 1, 1)) as dataset:
            dataset.write(self.pixels if pixels is None else pixels)
        return str(path)

    def test_nodata_samples_are_not_discarded_from_identity(self):
        published = self.write("published.tif", nodata=255)
        native = self.write("native.tif")
        result = RGB.compare_rgb(published, native)
        self.assertTrue(result["decoded_samples_identical"])
        self.assertEqual(result["sample_count"], 12)
        self.assertEqual(result["published_nodata_samples"], 3)
        self.assertIsNone(result["native_nodata"])
        self.assertFalse(result["acquisition_day_verified"])

    def test_changed_nodata_sample_is_a_real_mismatch(self):
        published = self.write("published.tif", nodata=255)
        changed = self.pixels.copy()
        changed[0, 0, 1] = 254
        result = RGB.compare_rgb(published, self.write("native.tif", changed))
        self.assertFalse(result["decoded_samples_identical"])
        self.assertEqual(result["differing_samples"], 1)

    def test_grid_and_crs_mismatch_are_rejected(self):
        published = self.write("published.tif")
        with self.assertRaisesRegex(ValueError, "pixel grid"):
            RGB.compare_rgb(published, self.write("shifted.tif", x=1000.5))
        with self.assertRaisesRegex(ValueError, "CRS"):
            RGB.compare_rgb(published, self.write("wrong-crs.tif", crs="EPSG:3857"))
        with self.assertRaisesRegex(ValueError, "cover"):
            RGB.compare_rgb(published, self.write("outside.tif", x=1001))


if __name__ == "__main__":
    unittest.main()
