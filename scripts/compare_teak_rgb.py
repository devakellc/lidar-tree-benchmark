"""Compare decoded RGB samples without discarding a TIFF's nodata value."""

import argparse
import json

import numpy as np
import rasterio
from rasterio.windows import Window


def compare_rgb(published_path, native_path):
    with rasterio.open(published_path) as published, rasterio.open(native_path) as native:
        if published.crs is None or published.crs != native.crs:
            raise ValueError("RGB CRS is missing or differs")
        if published.count != 3 or native.count != 3:
            raise ValueError("Expected three RGB bands")
        if published.transform.b != 0 or published.transform.d != 0:
            raise ValueError("Rotated published RGB is unsupported")
        if native.transform.b != 0 or native.transform.d != 0:
            raise ValueError("Rotated native RGB is unsupported")
        window = native.window(*published.bounds)
        terms = np.array([window.col_off, window.row_off, window.width, window.height])
        if not np.allclose(terms, np.round(terms), atol=1e-6, rtol=0):
            raise ValueError("Published RGB does not lie on the native pixel grid")
        col, row, width, height = np.round(terms).astype(int)
        if col < 0 or row < 0 or col + width > native.width or row + height > native.height:
            raise ValueError("Native RGB does not cover published RGB")
        win = Window(col, row, width, height)
        if not np.allclose(tuple(native.window_transform(win)),
                           tuple(published.transform), atol=1e-7, rtol=0):
            raise ValueError("RGB transforms disagree")
        a = published.read(masked=False)
        b = native.read(window=win, masked=False)
        if a.shape != b.shape or a.dtype != b.dtype or a.dtype != np.uint8:
            raise ValueError("Expected equal RGB uint8 shapes")
        return {
            "sample_count": int(a.size),
            "differing_samples": int(np.count_nonzero(a != b)),
            "decoded_samples_identical": bool(np.array_equal(a, b)),
            "published_nodata": published.nodata,
            "native_nodata": native.nodata,
            "published_nodata_samples": int(np.count_nonzero(a == published.nodata)),
            "native_processing_datetime": native.tags().get("TIFFTAG_DATETIME"),
            "acquisition_day_verified": False,
            "rasterio_version": rasterio.__version__,
            "numpy_version": np.__version__,
        }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("published")
    parser.add_argument("native")
    parser.add_argument("output")
    args = parser.parse_args()
    result = compare_rgb(args.published, args.native)
    with open(args.output, "x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write("\n")
