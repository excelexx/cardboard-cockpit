import importlib.util
import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "investigation"))


@unittest.skipUnless(
    importlib.util.find_spec("littlefs"),
    "install requirements.txt for filesystem checks",
)
class FilesystemTests(unittest.TestCase):
    def fixture(self):
        from littlefs import LittleFS

        fs = LittleFS(block_size=4096, block_count=16, mount=False)
        fs.format()
        fs.mount()
        fs.makedirs("/apps/demo")
        with fs.open("/apps/demo/main.lua", "w") as f:
            f.write("return 42")
        with fs.open("/private.json", "w") as f:
            f.write('{"secret":"fixture-only"}')
        fs.unmount()
        return bytes(fs.context.buffer)

    def test_summary_does_not_export_paths_or_values(self):
        from filesystem import inspect_volume

        before = self.fixture()
        summary, inventory = inspect_volume(before)
        self.assertEqual(summary["file_count"], 2)
        self.assertEqual(summary["installed_app_lua_sources"], 1)
        self.assertTrue(summary["source_buffer_unchanged"])
        self.assertNotIn("fixture-only", str(summary))
        self.assertNotIn("/private.json", str(summary))
        self.assertEqual(len(inventory), 2)

    def test_explicit_extraction_and_no_overwrite(self):
        from filesystem import inspect_volume

        with tempfile.TemporaryDirectory() as directory:
            summary, _ = inspect_volume(self.fixture(), extract_to=directory)
            self.assertEqual(
                (Path(directory) / "apps/demo/main.lua").read_text(), "return 42"
            )
            with self.assertRaises(ValueError):
                inspect_volume(self.fixture(), extract_to=directory)

    def test_blank_image_is_not_formatted(self):
        from filesystem import inspect_volume
        from littlefs.errors import LittleFSError

        with self.assertRaises(LittleFSError):
            inspect_volume(b"\xff" * 65536)


class PartitionLayoutTests(unittest.TestCase):
    def rows(self):
        lines = (ROOT / "firmware/partitions.csv").read_text().splitlines()
        return [
            {"name": r[0], "type": r[1], "offset": int(r[3], 0), "size": int(r[4], 0)}
            for r in csv.reader(
                line for line in lines if line and not line.startswith("#")
            )
        ]

    def test_recovered_filesystem_extent_is_preserved(self):
        rows = self.rows()
        volume = next(r for r in rows if r["name"] == "littlefs")
        observed = json.loads((ROOT / "evidence/filesystem-summary.json").read_text())
        self.assertEqual(volume["offset"], int(observed["flash_offset"], 16))
        self.assertEqual(volume["size"], observed["volume_bytes"])
        ordered = sorted(rows, key=lambda r: r["offset"])
        for left, right in zip(ordered, ordered[1:]):
            self.assertLessEqual(left["offset"] + left["size"], right["offset"])
        self.assertLessEqual(
            ordered[-1]["offset"] + ordered[-1]["size"], 4 * 1024 * 1024
        )

    def test_recorded_firmware_image_fits_new_slot(self):
        app = next(r for r in self.rows() if r["type"] == "app")
        build = json.loads((ROOT / "evidence/firmware-build.json").read_text())
        self.assertLessEqual(build["artifacts"]["firmware.bin"]["bytes"], app["size"])


if __name__ == "__main__":
    unittest.main()
