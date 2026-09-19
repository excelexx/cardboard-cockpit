import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from serial_tool import frames, request


class FakePort:
    def __init__(self, chunks=()):
        self.chunks = list(chunks)

    def read(self, n):
        return self.chunks.pop(0) if self.chunks else b""

    def write(self, data):
        command = json.loads(data)
        self.chunks = [
            b"ESP-ROM: boot log\r\n",
            b'{"type":"state"}\n',
            (
                json.dumps({"type": "result", "id": command["id"], "ok": True}) + "\n"
            ).encode(),
        ]

    def flush(self):
        pass


class SerialFramingTests(unittest.TestCase):
    def test_fragmented_frame_and_non_json_banner(self):
        port = FakePort([b'boot text\n{"type":', b'"state","held_mask":1}\n'])
        iterator = frames(port, 0.1)
        self.assertEqual(next(iterator), {"type": "state", "held_mask": 1})
        iterator.close()

    def test_request_matches_result_identifier(self):
        result = request(FakePort(), {"cmd": "info"}, 0.1)
        self.assertTrue(result["ok"])
        self.assertEqual(result["type"], "result")

    def test_oversized_command_rejected_before_write(self):
        with self.assertRaises(ValueError):
            request(FakePort(), {"cmd": "text", "text": "x" * 3000}, 0.1)

    def test_timeout(self):
        class Silent(FakePort):
            def write(self, data):
                pass

        with self.assertRaises(TimeoutError):
            request(Silent(), {"cmd": "info"}, 0.001)


if __name__ == "__main__":
    unittest.main()
