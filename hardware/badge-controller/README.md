# Badge Controller

Turns the Hack the North 2026 hacker badge (ESP32-C3) into a wireless input
device: eight buttons reported over Bluetooth LE, a pixel-art fighter held on
the LCD, and a rainbow burst on the RGB LEDs whenever a button is pressed.

The badge is already flashed. You only need this if you are setting up a
second machine, changing the firmware, or reading the button data yourself.

```
firmware/badge_controller/   Arduino sketch + the generated LCD image
host/                        Python tools that read the buttons over BLE
```

## Read the buttons from your laptop

Requires **Python 3.9+** and a machine with Bluetooth. macOS ships a suitable
Python at `/usr/bin/python3`; note that Homebrew's Python has no `tkinter`,
which the graphical tester needs.

```sh
cd hardware/badge-controller/host
/usr/bin/python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python badge_cli.py
```

`badge_cli.py` prints each step, so it is the one to run first — it tells you
where it got stuck. Once it says `PRESS BUTTONS NOW`, press buttons and you
will see lines like:

```
12:21:46  raw=0x7e  mask=0x001  held=A
```

`badge_tester.py` is the same thing with a window: a button pad that lights
up, press counters, and an event log. Run it the same way.

**macOS will ask for Bluetooth permission the first time.** If you get
`Bluetooth device is turned off` while Bluetooth is plainly on, that *is* the
permission error: System Settings → Privacy & Security → Bluetooth, enable
your terminal, then fully quit and reopen it. The prompt only appears for a
program a human launched, so this cannot be done for you by a script.

## Build and flash the firmware

Board: **ESP32C3 Dev Module**, **USB CDC On Boot = Enabled**.

Install the ESP32 core plus three libraries — `Adafruit GFX`,
`Adafruit ST7735 and ST7789 Library`, `Adafruit NeoPixel`, and
`NimBLE-Arduino` — then:

```sh
arduino-cli compile -b esp32:esp32:esp32c3:CDCOnBoot=cdc firmware/badge_controller
arduino-cli upload  -b esp32:esp32:esp32c3:CDCOnBoot=cdc -p /dev/cu.usbmodem101 firmware/badge_controller
```

The port name varies between machines; check `ls /dev/cu.usbmodem*`.

**If no port appears**, the badge is probably stuck resetting and USB never
settles. Unplug it, hold **START**, plug it back in while still holding, and
release after about two seconds. START sits on GPIO9, which is a boot strap
pin, so holding it during power-up forces the ROM bootloader and lets you
flash regardless of what the firmware is doing.

Running on batteries instead of USB: switch the batteries **off** before
connecting USB, per the badge's own manual.

## How the hardware actually works

Worth knowing before you change anything, because it is not what you would
guess.

**The buttons are not on individual GPIOs.** Seven of them sit behind a
74HC165 shift register and only START is wired directly:

| Signal | GPIO |
|---|---|
| PL (parallel load) | 20 |
| CP (clock) | 21 |
| Q7 (serial data) | 7 |
| START | 9, active low |
| RGB LEDs (6, GRB order) | 3 |
| LCD: SCLK / MOSI / CS / DC / RESET | 1 / 10 / 2 / 0 / 4 |

Read it by pulsing PL low to latch, then clocking eight bits out of Q7,
reading GPIO7 *before* the first rising edge. Logical codes are
`0=A 1=B 2=HOME 3=DOWN 4=LEFT 5=RIGHT 6=UP 8=START`.

**The resting byte is `0xfe`, not `0xff`.** Raw bit 0 is an unused input that
reads low even with nothing pressed, so it is masked off. This is also why
the older `badge_165_finder` sketch never worked: it accepted a pin guess
only when exactly one bit was low, and that unused input already consumed it.

**UART0 must stay unused** — its pins *are* the button load and clock lines.
That is why the sketch is built with USB CDC on boot and never touches
`Serial0`.

## BLE protocol

- Device name: `HTN Badge Buttons`
- Service: `5f1d0000-9c2b-4e7a-a3d6-0b8e1c4f2a71`
- Characteristic (read + notify): `5f1d0001-9c2b-4e7a-a3d6-0b8e1c4f2a71`
- Payload: 3 bytes — `[mask_lo, mask_hi, raw_shift_byte]`, mask little-endian

The 9-bit mask has one bit per logical code. Notifications fire only on a
debounced change: three stable samples at roughly 200 Hz, so about 15 ms.

This is a **custom GATT service, not BLE HID**, so the badge will not appear
to the OS as a game controller and the flight sim cannot see it directly.
Anything that speaks GATT can read it. Making it a real gamepad means
reflashing with a HID descriptor; the button decoding above would carry over
unchanged.

## Power, and why the LEDs are not always on

`docs/subsystems.md` in the badge research notes warns that the 500 mA USB
figure is a host allocation, *"not a promise that every full-brightness
LED/radio/display combination fits the board's supply limits."*

That turned out to be real. An earlier build with the Bluedroid BLE stack, a
permanently lit LED strip and the LCD powered went into a continuous reset
loop — the image would draw, the radio would start, and the board would
restart. Three changes fixed it:

- **NimBLE instead of Bluedroid**, which uses far less RAM
- **Minimum BLE transmit power** (`setPower(-12)`); the laptop is inches away
- **LEDs dark unless a button was just pressed**

So if you raise `RAINBOW_LEVEL`, extend `SEQUENCE_X_MS`, or switch BLE stacks,
watch for the reset loop coming back. A vanishing `/dev/cu.usbmodem*` port is
the tell.

The LCD has **no MISO connection**, so nothing can read back what is on the
panel. Display output can only be confirmed by looking at it.

## Tuning

All at the top of `badge_controller.ino`:

| Constant | Now | What it does |
|---|---|---|
| `RAINBOW_LEVEL` | 14 | Peak LED channel, 0–255. Stay low; safe continuous current was never measured, and this path bypasses the stock SDK's brightness cap. |
| `ROTATIONS_PER_SEC` | 0.30 | Rainbow rotation speed |
| `SEQUENCE_X_MS` | 3000 | How long the rainbow runs after a press |
| `LED_STEP_MS` | 40 | Animation frame interval (~25 fps) |
| `STABLE_SAMPLES` | 3 | Debounce samples before a change is reported |

To change the LCD image, regenerate `jet_image.h`: a 320×240 RGB565 array,
written as `const uint16_t JET_IMAGE[] PROGMEM`. Drawing it in horizontal
bands keeps any single SPI transfer short.

## Credit

Pin map, button bit order and the power warnings come from the badge research
in `hardware/badge/` on the `codex/badge-hardware-control` branch.
