# Display and RGB LEDs

## LCD protocol and recovered setup

The stock function at `0x4200df1a` sets MOSI=10, MISO=-1, SCLK=1, CS=2, DC=0, RESET=4. It creates an ST7789 panel, 16 bits per pixel, with a 40 MHz configured SPI bus and a 320×240 logical display. The JTAG implementation uses software SPI and does not claim a measured 40 MHz waveform.

The tested initialization is:

| Operation | Command / data |
|---|---|
| Hardware reset | GPIO4 low 20 ms, high, wait 120 ms |
| Sleep out | `0x11`, wait 120 ms |
| RGB565 | `0x3a 0x55` |
| Landscape addressing | `0x36 0x60` |
| Inversion on | `0x21` |
| Normal display mode | `0x13` |
| Display on | `0x29` |
| Column window | `0x2a`, start/end as big-endian 16-bit values |
| Row window | `0x2b`, start/end as big-endian 16-bit values |
| Pixel stream | `0x2c`, then big-endian RGB565 words |

DC is low for a command byte and high for parameters/pixels. CS is active low. Bits are sent MSB first with a mode-0 clock sequence. RGB565 is `((r>>3)<<11) | ((g>>2)<<5) | (b>>3)` for 8-bit RGB inputs. Red, green, blue constants are `0xf800`, `0x07e0`, `0x001f`.

```sh
python esp_control.py --hold 30 display-demo
python esp_control.py --hold 30 display-fill 0x001f
```

`Debugger.display_rectangle(x,y,w,h,color)` is available from Python while the relevant pins are owned by a halted scope. It rejects rectangles outside 320×240. The public CLI currently offers fill/demo; the optional serial firmware also offers rectangles and text.

The first test was not visible after resuming the installed sweep. Repeating it with the original program held paused produced the visible pattern, as confirmed by the user. Keep the controller paused while inspecting output. The LCD retains pixel state, but resuming pin-scanning code can reset or corrupt that state.

There is no recovered MISO connection, so the JTAG tool cannot read back the display RAM or independently verify a rendered frame. Visibility was confirmed by a human, not inferred from the SPI transaction completing. Exact colorimetry, scan timing, panel current, and backlight circuitry are not characterized.

## LED connection and protocol

The six-pixel RGB chain is on **GPIO3**. Sending green there produced green LEDs. The initial GPIO8 hypothesis did not produce the intended LED output and is excluded from the production tool. GPIO8 remains unassigned/strap in the map.

The implemented raw protocol is **GRB byte order**, MSB first, at 800 kHz-class timing. Each pixel occupies 24 bits; six pixels occupy 18 bytes. The RAM helper targets approximately 0.35 µs high for a zero, 0.70 µs high for a one, and 1.25 µs per bit plus loop overhead. Timing uses ESP32-C3's performance counter CSR `0x7e2`, with the PLL clock/divider checked before sending. A low interval before and after the frame latches the data. These are software timing targets; a logic analyzer has not measured the actual waveform. Green in the first wire byte was confirmed. Red/blue order has not been independently confirmed by a person.

```sh
python esp_control.py --hold 30 leds 0 24 0
python esp_control.py --hold 30 leds --index 1 24 0 0
python esp_control.py leds 0 0 0
```

The CLI index is 1–6. Without `--index`, all six receive the color. `ram_io.leds(debugger,3,colors)` accepts six independent `(r,g,b)` tuples. Native firmware's JSON `pixels` array has six entries in chain order.

The maker documents this front-view layout; individual physical positions were not separately calibrated in this session:

```text
          lanyard / top
     1 upper left    2 upper right
     6 middle left   3 middle right
     5 bottom left   4 bottom right
```

The stock Lua API applies a brightness curve and cap. Raw JTAG and optional native firmware send direct channel values and do not reproduce that curve. The examples deliberately use low values. The exact LED part and maximum safe continuous brightness/current are not established.

## Fast output without flashing

Host-driven per-edge JTAG is too slow for full frames or addressable LED timing. `ram_io.py` saves a small existing IRAM region, verifies its known signature, installs a bounded RISC-V helper, executes it with interrupts disabled, waits for its final breakpoint, and restores code, data, and registers. It never programs flash. Read [runtime.md](runtime.md) before adapting it to another firmware.
