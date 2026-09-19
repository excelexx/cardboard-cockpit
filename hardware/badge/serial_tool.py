#!/usr/bin/env python3
"""Talk to the optional standalone USB bridge firmware, not the stock badge.

Checks firmware identity before sending a requested command. JSON state frames
can be recorded independently; there is no game connection or network server.
"""
import argparse
import json
import time
import uuid


def frames(port, seconds):
    buffer = bytearray()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        buffer.extend(port.read(4096))
        if len(buffer) > 32768:
            buffer.clear()
        while b"\n" in buffer:
            line, _, rest = buffer.partition(b"\n")
            buffer = bytearray(rest)
            try:
                frame = json.loads(line)
                if isinstance(frame, dict):
                    yield frame
            except (ValueError, UnicodeError):
                pass  # ROM banners and non-JSON serial diagnostics.


def request(port, command, timeout):
    command = dict(command)
    identifier = uuid.uuid4().hex[:16]
    command["id"] = identifier
    encoded = (
        json.dumps(command, separators=(",", ":"), allow_nan=False).encode() + b"\n"
    )
    if len(encoded) > 2047:
        raise ValueError("Command exceeds firmware line limit")
    port.write(encoded)
    port.flush()
    for frame in frames(port, timeout):
        if frame.get("type") == "result" and frame.get("id") == identifier:
            return frame
    raise TimeoutError(
        "No matching bridge response; confirm the optional firmware is installed"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument(
        "--command", default='{"cmd":"info"}', help="One JSON command object"
    )
    parser.add_argument(
        "--listen",
        type=float,
        default=0,
        help="Print subsequent JSON frames for this many seconds",
    )
    parser.add_argument("--timeout", type=float, default=5)
    args = parser.parse_args()
    command = json.loads(args.command)
    if not isinstance(command, dict) or not isinstance(command.get("cmd"), str):
        parser.error("Expected an object containing cmd")
    import serial

    port = serial.Serial(port=None, baudrate=115200, timeout=0.1)
    port.dtr = True
    port.rts = False
    port.port = args.port
    port.open()
    try:
        identity = request(port, {"cmd": "info"}, args.timeout)
        if identity.get("firmware") != "badge-control-bridge-1":
            raise RuntimeError(
                "Connected firmware is not the standalone badge-control bridge"
            )
        result = (
            identity
            if command == {"cmd": "info"}
            else request(port, command, args.timeout)
        )
        print(json.dumps(result), flush=True)
        for frame in frames(port, args.listen):
            print(json.dumps(frame), flush=True)
    finally:
        port.close()


if __name__ == "__main__":
    main()
