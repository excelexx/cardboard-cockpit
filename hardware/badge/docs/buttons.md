# Buttons: physical bits, codes, and events

All eight physical buttons were pressed and released in a user-directed sequence. The raw capture is in `../evidence/button-calibration.jsonl`; automated tests replay it.

The capture predates unused-bit filtering, so its historical held-mask/code fields include code 7. Tests decode the raw byte and START level again using the final decoder. Two recording windows have separate relative elapsed-time origins.

| Label | Logical code | Held mask | Raw 74HC165 bit cleared | Raw byte when pressed alone |
|---|---:|---:|---:|---:|
| A | 0 | `0x001` | 7 | `0x7e` |
| B | 1 | `0x002` | 6 | `0xbe` |
| HOME | 2 | `0x004` | 5 | `0xde` |
| DOWN | 3 | `0x008` | 4 | `0xee` |
| LEFT | 4 | `0x010` | 3 | `0xf6` |
| RIGHT | 5 | `0x020` | 2 | `0xfa` |
| UP | 6 | `0x040` | 1 | `0xfc` |
| AUX1 / unused | 7 | `0x080` | 0 | Low even at rest; filter it |
| START | 8 | `0x100` | Not on shift register | Shift byte remains `0xfe`; GPIO9 becomes low |

At rest the shift byte is `0xfe`, not `0xff`. Logical code values match the recovered stock bit order and the independently observed physical sequence. Stock Lua `KIND` numeric values were not read from a running stock runtime; this tool emits the strings `pressed` and `released` instead of inventing numeric event kinds.

## Read sequence

1. Hold clock GPIO21 low.
2. Pulse GPIO20 low to load all parallel button levels, then high to latch.
3. Read GPIO7 before the first rising clock edge. This is raw bit 7.
4. Pulse GPIO21 high then low, and repeat until eight bits have been collected.
5. Read GPIO9 separately for START.

The retained stock function uses approximately 1 µs waits; the replacement pin-finder uses 5 µs. JTAG command overhead comfortably exceeds those minimum waits, at a much lower read rate. The optional native firmware uses 1 µs waits.

Equivalent decoding:

```python
held = 0
for code in range(7):
    if not raw_byte & (1 << (7 - code)):
        held |= 1 << code
if start_gpio_level == 0:
    held |= 0x100
```

The general stock transformation also includes the unused bit, giving `0x080` at rest. `decode_buttons()` retains that as `raw_held_mask` but exposes physical `held_mask = raw_held_mask & 0x17f`.

## Host output

```sh
python esp_control.py buttons
python esp_control.py watch-buttons --seconds 60
```

Example physical A press:

```json
{"shift_raw":"0x7e","raw_held_mask":"0x081","held_mask":"0x001","held_codes":[0],"held_buttons":["A"],"start":false}
```

The watcher adds elapsed seconds and the newly pressed/released names. Simultaneous keys are bitwise combinations. Raw polling does not provide a formal debouncer; applications needing exactly one event per physical click should require stable samples or add a 10–30 ms debounce policy. Do not collapse a whole mask into a single key number.

## Why the installed pin finder fails

The recovered sketch searches all distinct triples from `0,1,2,3,4,5,6,7,8,10,20,21`. It accepts a result only when two reads match and the inverted byte has exactly one set bit. The unused low input already consumes that one bit. Pressing A produces `0x7e`, whose inverted byte is `0x81`: two bits. The correct wiring is rejected.

Its normal UART0 also shares GPIO20/21 with the load/clock signals, and the sweep reconfigures display and LED pins. The broad sweep is therefore unnecessary and disruptive now that the wiring is known. `investigation/recovered_pin_finder.cpp` is explanatory reconstruction, not recommended firmware.

START is also a boot strap. Holding it during reset/power-up can enter the ROM loader; it is an ordinary input while the application is running. HOME is not a hardware reset button.
