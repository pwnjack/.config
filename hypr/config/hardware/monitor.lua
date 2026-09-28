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
--
-- A broken file must not take the whole config down, nor leave half a layout
-- behind: it runs in an environment that can only record hl.monitor() calls,
-- and they are applied only once all of it has run. On any failure the
-- catch-all stands and a notification says so. Its text is fixed on purpose:
-- the Lua error comes from file content and must never reach a shell.
local function monitors_failed(reason)
    print("monitors.lua: " .. tostring(reason))
    hl.exec_cmd("notify-send -u critical Displays 'monitors.lua could not be applied; displays use automatic settings'")
end
local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then state_home = (os.getenv("HOME") or "") .. "/.local/state" end
local machine = state_home .. "/hypr/monitors.lua"
local file, open_err, errno = io.open(machine, "r")
if file then
    file:close()
    -- Counted, not appended: hl.monitor(nil) must still be seen and rejected.
    local specs, count = {}, 0
    local chunk, err = loadfile(machine, "t", { hl = { monitor = function(spec) count = count + 1; specs[count] = spec end } })
    local ok = chunk ~= nil
    if ok then ok, err = pcall(chunk) end
    -- Every rule is checked before any is applied. Keys are Hyprland's to
    -- judge (a hand edit may add vrr, bitdepth, reserved, ...); values must be
    -- plain data, so no function or metatable reaches the real hl.monitor().
    local function plain(value)
        local kind = type(value)
        if kind == "string" or kind == "number" or kind == "boolean" then return true end
        if kind ~= "table" or getmetatable(value) ~= nil then return false end
        for key, item in pairs(value) do if type(key) ~= "number" or type(item) ~= "number" then return false end end
        return true
    end
    for index = 1, ok and count or 0 do
        local spec = specs[index]
        if type(spec) ~= "table" or getmetatable(spec) ~= nil or type(spec.output) ~= "string" then
            ok, err = false, "entry " .. index .. " is not a monitor rule"
            break
        end
        for key, value in pairs(spec) do
            if type(key) ~= "string" or not plain(value) then ok, err = false, "entry " .. index .. " has an unsupported " .. tostring(key) break end
        end
        if not ok then break end
    end
    -- Accepted limitation: a well-typed rule with a value Hyprland rejects
    -- (transform 9, a mode string it cannot parse) does not raise here while
    -- the config loads; Hyprland skips that one rule and shows it in its
    -- config-error banner, as for any hand-edited config. The panel only ever
    -- writes values it validated, so this needs a hand edit.
    if ok then ok, err = pcall(function() for index = 1, count do hl.monitor(specs[index]) end end) end
    if not ok then monitors_failed(err) end
elseif errno ~= 2 then -- ENOENT: no file simply means all automatic.
    monitors_failed(open_err)
end
