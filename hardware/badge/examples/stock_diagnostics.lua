--[==[badge-app
slug=hardware_probe
name=Hardware Probe
icon=IO
api=2
heap_kb=48
wake_lock=1
]==]

-- Stock firmware only. Reference app; not deployed/tested in this investigation.
-- No storage, identity, radio, or NFC use. Logs go only to the local console.
local input_line, motion_line, next_update
local button_names = {"A", "B", "HOME", "DOWN", "LEFT", "RIGHT", "UP", "AUX1", "START"}

function on_enter(root)
  local title = badge.ui.label(root, "Badge Hardware Probe")
  title:align("top_mid", 0, 12)
  input_line = badge.ui.label(root, "Press a button")
  input_line:align("center", 0, -25)
  motion_line = badge.ui.label(root, "Motion: waiting")
  motion_line:align("center", 0, 20)
  local hint = badge.ui.label(root, "A/B: green/off LEDs   HOME: exit")
  hint:style({text_font=14})
  hint:align("bottom_mid", 0, -14)
  next_update = 0
  for _, name in ipairs(button_names) do
    badge.sys.log("BUTTON " .. name .. "=" .. tostring(badge.input.BUTTON[name]))
  end
  badge.sys.log("PRESSED=" .. tostring(badge.input.KIND.PRESSED))
  badge.sys.log("RELEASED=" .. tostring(badge.input.KIND.RELEASED))
end

function on_button(button, kind)
  input_line:set_text("code=" .. tostring(button) .. " kind=" .. tostring(kind))
  badge.sys.log("button=" .. tostring(button) .. " kind=" .. tostring(kind))
  if kind ~= badge.input.KIND.PRESSED then return end
  if button == badge.input.BUTTON.A then
    badge.led.set_all(0, 96, 0)
    badge.led.show()
  elseif button == badge.input.BUTTON.B then
    badge.led.clear()
    badge.led.show()
  end
end

function on_tick()
  local now = badge.sys.ms()
  if now < next_update then return end
  next_update = now + 250
  local x,y,z = badge.sensor.accel()
  if x == nil then
    motion_line:set_text("Motion unavailable")
  else
    motion_line:set_text(string.format("XYZ mg: %.0f %.0f %.0f", x,y,z))
  end
end

function on_exit()
  badge.led.clear()
  badge.led.show()
end
