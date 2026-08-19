local home = os.getenv("HOME") or ""
local file = io.open(home .. "/.config/options/cursortheme", "r")
if not file then
    return "Bibata-Modern-Classic"
end

local theme = file:read("*l")
file:close()
return theme and theme ~= "" and theme or "Bibata-Modern-Classic"
