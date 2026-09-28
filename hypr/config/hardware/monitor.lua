-- Deliberately host-neutral: no connector is named here, so a fresh checkout
-- is correct on any hardware.
--
-- `highres@highrr`, not `preferred` or bare `highrr`. On this machine's
-- 144 Hz panel, `preferred` selected 2560x1440@59.951 while this combined form
-- selected 2560x1440@143.998. Hyprland parses the two keywords around `@`.
hl.monitor({ output = "", mode = "highres@highrr", position = "auto", scale = 1 })

-- Per-machine displays live outside the repo, written by the Super+I Displays
-- page to ${XDG_STATE_HOME:-~/.local/state}/hypr/monitors.lua. A named output
-- beats the catch-all above regardless of order; no file means all automatic.
-- A broken file must not take the whole config down, so it is loaded under
-- pcall and the catch-all stands.
local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then state_home = (os.getenv("HOME") or "") .. "/.local/state" end
local machine = state_home .. "/hypr/monitors.lua"
local file = io.open(machine, "r")
if file then
    file:close()
    local ok, err = pcall(dofile, machine)
    if not ok then
        print("monitors.lua: " .. tostring(err))
        hl.exec_cmd("notify-send -u critical Displays 'monitors.lua failed to load; displays use automatic settings'")
    end
end
