-- Previous/next workspace for the keybinds, bounded to the row the Waybar
-- workspace module draws: 1-5 always, 6-10 only while they exist. Stepping
-- stops at either end rather than wrapping; Hyprland's relative "r+1" would
-- count on through 11, 12, ... where no slot exists. The bar's own scroll
-- applies the same rule in waybar/workspaces/model.c (ws_step).

local M = {}

local COUNT, ALWAYS = 10, 5

-- The visible slot one step from active in direction dir (-1 or +1), or nil
-- at either end (and for dir 0). exists(id) says whether workspace id exists.
-- From outside the row (a special workspace, or an id above 10), +1 enters at
-- the first slot and -1 at the last visible one. Pure, so it is tested
-- without Hyprland.
function M.step(active, exists, dir)
    if dir == 0 then return nil end
    dir = dir < 0 and -1 or 1
    local from = active
    if not (type(active) == "number" and active >= 1 and active <= COUNT) then
        from = dir > 0 and 0 or COUNT + 1
    end
    local id = from + dir
    while id >= 1 and id <= COUNT do
        if id <= ALWAYS or exists(id) then return id end
        id = id + dir
    end
    return nil
end

local function target(dir)
    local ws = hl.get_active_workspace()
    return M.step(ws and ws.id, function(id) return hl.get_workspace(id) ~= nil end, dir)
end

-- Bind actions: focus, or move the focused window and follow it.
function M.focus(dir)
    return function()
        local id = target(dir)
        if id then hl.dispatch(hl.dsp.focus({ workspace = id })) end
    end
end

function M.move(dir)
    return function()
        local id = target(dir)
        if id then hl.dispatch(hl.dsp.window.move({ workspace = id, follow = true })) end
    end
end

return M
