"""Exercise the real service and two local clients, never a camera."""
import asyncio
import json
from pathlib import Path
import socket
import sys
import time
import unittest

try:
    from websockets.asyncio.client import connect
except ImportError:
    connect = None


@unittest.skipIf(connect is None, "Optional websockets package not installed")
class WebSocketTests(unittest.IsolatedAsyncioTestCase):
    async def test_simulated_service_packet_cadence_and_reconnection(self):
        with socket.socket() as temporary:
            temporary.bind(("127.0.0.1", 0))
            port = temporary.getsockname()[1]
        root = Path(__file__).resolve().parents[2]
        process = await asyncio.create_subprocess_exec(
            sys.executable, "vision/tracker.py", "--simulate", "--port", str(port), "--duration", "5",
            cwd=str(root), stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        try:
            announcement = await asyncio.wait_for(process.stdout.readline(), 5)
            self.assertIn(b"SIMULATED", announcement)
            url = "ws://127.0.0.1:%d" % port
            async with connect(url, proxy=None, close_timeout=1) as first, connect(url, proxy=None, close_timeout=1) as second:
                packets = []
                start = time.monotonic()
                for _ in range(20):
                    packet = json.loads(await asyncio.wait_for(first.recv(), 2))
                    peer = json.loads(await asyncio.wait_for(second.recv(), 2))
                    self.assertEqual(peer["sequence"], packet["sequence"])
                    packets.append(packet)
                    self.assertEqual(packet["version"], 1)
                    self.assertTrue(packet["tracking"])
                    self.assertTrue(-1 <= packet["yoke"]["roll"] <= 1)
                    self.assertTrue(0 <= packet["throttle"]["value"] <= 1)
                elapsed = time.monotonic() - start
                self.assertGreater(elapsed, .4)
                self.assertLess(elapsed, 1.6)
                self.assertEqual([p["sequence"] for p in packets], sorted(set(p["sequence"] for p in packets)))
            async with connect(url, proxy=None, close_timeout=1) as reconnected:
                packet = json.loads(await asyncio.wait_for(reconnected.recv(), 2))
                self.assertGreater(packet["sequence"], packets[-1]["sequence"])
        finally:
            if process.returncode is None:
                process.terminate()
            await asyncio.wait_for(process.communicate(), 5)


if __name__ == "__main__":
    unittest.main()
