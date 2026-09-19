import importlib.util
import json
from pathlib import Path
import socket
import signal
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from esp_control import Debugger, decode_buttons, crc_a, GPIO, IOMUX
import ram_io
from setup_tools import asset_name


class ButtonCalibrationTests(unittest.TestCase):
    def test_recorded_physical_sequence(self):
        events = [
            json.loads(line)
            for line in (ROOT / "evidence/button-calibration.jsonl")
            .read_text()
            .splitlines()
        ]
        presses = []
        for event in events:
            decoded = decode_buttons(int(event["shift_raw"], 16), event["start"])
            if decoded["held_buttons"]:
                presses.append(decoded["held_buttons"])
        self.assertEqual(
            presses,
            [["UP"], ["DOWN"], ["LEFT"], ["RIGHT"], ["HOME"], ["START"], ["B"], ["A"]],
        )

    def test_unused_parallel_input_is_filtered(self):
        result = decode_buttons(0xFE, False)
        self.assertEqual(result["raw_held_mask"], "0x080")
        self.assertEqual(result["held_mask"], "0x000")
        self.assertEqual(result["held_buttons"], [])

    def test_simultaneous_buttons(self):
        self.assertEqual(
            decode_buttons(0x3E, True)["held_buttons"], ["A", "B", "START"]
        )

    def test_invalid_inputs(self):
        for raw, start in [(-1, False), (256, False), (True, False), (0xFE, 1)]:
            with self.assertRaises(ValueError):
                decode_buttons(raw, start)


class RecoveryTests(unittest.TestCase):
    def test_interrupt_waits_for_rpc_reply_before_cleanup(self):
        class InterruptingSocket:
            def sendall(self, data):
                pass

            def recv(self, size):
                signal.getsignal(signal.SIGINT)(signal.SIGINT, None)
                return b"0 {0x1}\x1a"

        debugger = Debugger.__new__(Debugger)
        debugger.sock = InterruptingSocket()
        handler = signal.getsignal(signal.SIGINT)
        with self.assertRaises(KeyboardInterrupt):
            debugger.command("read_memory 0 32 1")
        self.assertIs(signal.getsignal(signal.SIGINT), handler)

    def test_pin_configuration_is_restored_after_failure(self):
        class Fake(Debugger):
            def __init__(self):
                self.resume_allowed = True
                self.resume_address = None
                self.calls = []
                self.memory = {GPIO + 4: 0x200108, GPIO + 0x20: 0x300008}
                for pin in (7, 9, 20, 21):
                    for offset, address in enumerate(
                        (
                            IOMUX + 4 + pin * 4,
                            GPIO + 0x74 + pin * 4,
                            GPIO + 0x554 + pin * 4,
                        )
                    ):
                        self.memory[address] = 0x100 + pin + offset

            def command(self, text):
                self.calls.append(text)
                return (
                    "0* esp32c3 esp32c3 little esp32c3.tap0 running"
                    if text == "targets"
                    else ""
                )

            def read(self, address, count=1):
                return [self.memory.get(address + i * 4, 0) for i in range(count)]

            def write(self, address, value):
                if address == GPIO + 8:
                    self.memory[GPIO + 4] |= value
                elif address == GPIO + 12:
                    self.memory[GPIO + 4] &= ~value
                elif address == GPIO + 0x24:
                    self.memory[GPIO + 0x20] |= value
                elif address == GPIO + 0x28:
                    self.memory[GPIO + 0x20] &= ~value
                else:
                    self.memory[address] = value

        debugger = Fake()
        before = dict(debugger.memory)
        with self.assertRaisesRegex(RuntimeError, "interrupted"):
            with debugger.pins({20: 1, 21: 0}, [7, 9]):
                raise RuntimeError("interrupted")
        self.assertEqual(debugger.memory, before)
        self.assertEqual(debugger.calls[-1], "resume")

    def test_unknown_firmware_is_rejected_before_ram_write(self):
        class Fake(Debugger):
            def __init__(self):
                self.resume_allowed = True
                self.resume_address = None
                self.calls = []

            def command(self, text):
                self.calls.append(text)
                return (
                    "0* esp32c3 esp32c3 little esp32c3.tap0 running"
                    if text == "targets"
                    else ""
                )

            def read(self, address, count=1):
                return [0] * count

        debugger = Fake()
        with self.assertRaisesRegex(RuntimeError, "does not match"):
            ram_io.run(debugger, [0x00100073], {})
        self.assertFalse(any("write_memory" in c for c in debugger.calls))
        self.assertEqual(debugger.calls[-1], "resume")

    def test_memory_validation_happens_before_transport(self):
        debugger = Debugger.__new__(Debugger)
        with self.assertRaises(ValueError):
            debugger.read(3)
        with self.assertRaises(ValueError):
            debugger.read(0, 0)
        with self.assertRaises(ValueError):
            debugger.write(0, -1)

    def test_reserved_usb_and_flash_pins_are_rejected(self):
        debugger = Debugger.__new__(Debugger)
        for pin in range(11, 20):
            with self.assertRaises(ValueError):
                with debugger.pins({pin: 0}, []):
                    pass

    def test_halted_scope_resumes_after_exception(self):
        debugger = Debugger.__new__(Debugger)
        debugger.resume_allowed = True
        debugger.resume_address = None
        calls = []

        def command(text):
            calls.append(text)
            return (
                "0* esp32c3 esp32c3 little esp32c3.tap0 running"
                if text == "targets"
                else ""
            )

        debugger.command = command
        with self.assertRaisesRegex(RuntimeError, "probe failed"):
            with debugger.halted():
                raise RuntimeError("probe failed")
        self.assertEqual(calls, ["targets", "halt", "resume"])

    def test_failed_ram_recovery_does_not_resume(self):
        debugger = Debugger.__new__(Debugger)
        debugger.resume_allowed = True
        debugger.resume_address = None
        calls = []
        debugger.command = lambda text: calls.append(text) or (
            "0* esp32c3 esp32c3 little esp32c3.tap0 running"
            if text == "targets"
            else ""
        )
        with debugger.halted():
            debugger.resume_allowed = False
        self.assertNotIn("resume", calls)

    def test_already_halted_target_stays_halted(self):
        debugger = Debugger.__new__(Debugger)
        debugger.resume_allowed = True
        debugger.resume_address = None
        calls = []
        debugger.command = (
            lambda text: calls.append(text)
            or "0* esp32c3 esp32c3 little esp32c3.tap0 halted"
        )
        with debugger.halted():
            pass
        self.assertEqual(calls, ["targets"])

    def test_exclusive_local_device_lock(self):
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        first = None
        try:
            first = Debugger(server.getsockname()[1])
            peer, _ = server.accept()
            try:
                with self.assertRaisesRegex(RuntimeError, "owns this device"):
                    Debugger(server.getsockname()[1])
            finally:
                peer.close()
        finally:
            if first:
                first.close()
            server.close()


class CRCTests(unittest.TestCase):
    def test_standard_crc_a_vector(self):
        self.assertEqual(crc_a(b"123456789"), 0xBF05)
        self.assertEqual(crc_a(b""), 0x6363)


class ToolchainTests(unittest.TestCase):
    def test_native_host_selection(self):
        self.assertIn("macos-arm64", asset_name("Darwin", "arm64"))
        self.assertIn("linux-arm64", asset_name("Linux", "aarch64"))
        self.assertIn("win64", asset_name("Windows", "AMD64"))

    def test_locked_assets_cover_supported_hosts(self):
        assets = json.loads((ROOT / "toolchain-lock.json").read_text())["assets"]
        for system, machine in [
            ("Darwin", "arm64"),
            ("Darwin", "x86_64"),
            ("Linux", "x86_64"),
            ("Linux", "aarch64"),
            ("Windows", "AMD64"),
        ]:
            selected = assets[asset_name(system, machine)]
            self.assertEqual(len(selected["sha256"]), 64)
            self.assertTrue(selected["url"].startswith("https://github.com/espressif/"))


@unittest.skipUnless(
    importlib.util.find_spec("capstone"),
    "install requirements.txt for machine-code checks",
)
class MachineCodeTests(unittest.TestCase):
    def test_all_instructions_decode_and_branches_stay_in_helper(self):
        from capstone import Cs, CS_ARCH_RISCV, CS_MODE_RISCV32

        decoder = Cs(CS_ARCH_RISCV, CS_MODE_RISCV32)
        for words in [ram_io.fill_program(), ram_io.led_program()]:
            payload = b"".join(word.to_bytes(4, "little") for word in words)
            instructions = list(decoder.disasm(payload, 0))
            self.assertEqual(len(instructions), len(words))
            self.assertEqual(instructions[-1].mnemonic, "ebreak")
            for index, word in enumerate(words):
                if word & 0x7F == 0x63:
                    imm = (
                        ((word >> 31) << 12)
                        | (((word >> 7) & 1) << 11)
                        | (((word >> 25) & 63) << 5)
                        | (((word >> 8) & 15) << 1)
                    )
                    if imm & 0x1000:
                        imm -= 0x2000
                    self.assertIn(index * 4 + imm, range(0, len(payload), 4))
                if word & 0x7F == 0x23:
                    self.assertEqual((word >> 15) & 31, 5)  # only GPIO base t0
                    offset = ((word >> 25) << 5) | ((word >> 7) & 31)
                    self.assertIn(offset, (8, 12))

    def test_cycle_counter_matches_esp32c3(self):
        reads = [
            word >> 20
            for word in ram_io.led_program()
            if word & 0x7F == 0x73 and (word >> 12) & 7 == 2
        ]
        self.assertEqual(reads, [0x7E2, 0x7E2, 0x7E2])


if __name__ == "__main__":
    unittest.main()
