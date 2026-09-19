# Stock badge software surface

The maker's [Badge IDE guide](https://badge.hackthenorth.com/ide/README.md), accessed through the IDE editor, describes a Lua app runtime. That is useful reference information, but the connected unit is currently running the pin-finder sketch, so these APIs cannot be called on it now.

The guide is not a GPIO schematic and does not grant raw MCU control. The JTAG/native tools in this package operate at a different layer.

## Documented API families

| Family | Documented functions / role | Boundary |
|---|---|---|
| Lifecycle | `on_enter(root)`, `on_tick()`, `on_button(button,kind)`, `on_exit()` | Foreground app lifecycle |
| `badge.ui` | Labels, boxes and other bound widgets, styles, positions | 320×240; supported bindings, not arbitrary native LVGL/canvas |
| `badge.input` | `BUTTON`, `KIND`, `is_down()`, `held()` | Numeric constants; HOME interception affects event/held behavior |
| `badge.led` | `set`, `set_all`, `clear`, `show`, `count` | Six pixels, 1-based indexing; writes staged until show |
| `badge.sensor` | `accel`, `shake`, `tap`, `orientation` | Cached motion; unavailable hardware must be handled |
| `badge.nfc` | `enable`, `disable`, `card`, `read_text`, `clear` | UID/NDEF reader, no Lua tag-writing API |
| `badge.radio` | `enable`, `disable`, `send`, `on_recv`, `mac` | Restricted Lua channel; 1–44 byte payloads, not arbitrary GATT/network |
| `badge.sys` | `ms`, `uptime`, `log`, `random`, heap/stats, version, wake lock | Runtime utilities |
| `badge.store` | Typed or generic get/set | App-scoped persisted keys |
| `badge.fs` | Read/write/list/remove/mkdir relative to app | Sandboxed files and quotas |
| `badge.me` | Badge ID/name/role/color/provisioned | Curated identity, not all private provisioning fields |
| `badge.contacts` | Count/read curated records | Restricted read-only contact surface |
| `badge.app` | Slug/name/exit | Deferred return to launcher |

The guide documents named buttons `A B HOME DOWN LEFT RIGHT UP AUX1 START` and pressed/released kinds. This investigation independently established physical logical IDs 0,1,2,3,4,5,6,8. The stock runtime's numeric `KIND` values should be read from the runtime, not guessed.

`examples/stock_diagnostics.lua` prints the runtime's own constants and displays button/motion state. It is a separate, unexecuted reference app for a badge still running stock firmware. It has no networking, identity collection, game connection, or persistent writes.

## Stock IDE and console

The current public IDE exposes Import app, Download app, Connect, Push, Reboot, and Ctrl-C. The guide describes files under `/littlefs/apps/<slug>/`, `manifest.cfg` plus `main.lua`, with `reload` refreshing app discovery. Documented diagnostic console commands include `apps`, `heap`, and `uitree`.

Those commands were **not** sent to the pin finder, and this package does not implement the stock upload protocol or claim to restore the stock application. Importing Lua does not replace MCU firmware or make APIs available on a non-stock image.

## Runtime constraints relevant to future apps

The September 16 guide update documents bounded callbacks, a normal 48 KiB Lua quota (96 KiB opt-in), and a separate native-widget cap. These are ceilings, not a guarantee of free heap or frame latency. The exact allowances vary by installed stock firmware version. The example avoids blocking loops, updates at a modest cadence, and uses a small number of widgets.

The source guide also states that stock LEDs apply a brightness curve/cap, NFC is enabled on demand, HOME normally exits, and radio messages are restricted to the Lua application channel. Do not equate those sandbox restrictions with the physical MCU's capabilities.
