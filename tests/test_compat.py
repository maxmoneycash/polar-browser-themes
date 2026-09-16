import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("compat", ROOT / "native/compat.py")
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)


class Compatibility(unittest.TestCase):
    def test_unknown_build_is_rejected_before_any_patch(self):
        source = b"not a supported Polar executable"
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            compat.patched_bytes(source)
        self.assertEqual(source, b"not a supported Polar executable")

    def test_patch_points_are_unique_aligned_and_bounded(self):
        addresses = [item[0] for item in compat.PATCHES]
        self.assertEqual(len(addresses), len(set(addresses)))
        for address, before, after, _ in compat.PATCHES:
            self.assertEqual(address % 4, 0)
            self.assertNotEqual(before, after)
            self.assertLess(before, 2 ** 32)
            self.assertLess(after, 2 ** 32)


if __name__ == "__main__":
    unittest.main()
