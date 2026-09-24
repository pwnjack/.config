--
-- HYPRLAND CONFIGURATION
-- Modern dark theme - Pywal dynamic colors
--
-- Hyprland 0.55+ loads this file instead of hyprland.conf. Keeping the
-- configuration split into modules also contains errors: Hyprland evaluates
-- each require() in its own protected scope.
--

local apps = require("config.apptype")
local colors = require("config.colors")

require("config.hardware.monitor")
require("config.hardware.input")

require("config.setup.envvars")(apps.cursorTheme)
require("config.setup.autostart")(apps)

require("config.looks.decor")(colors)
require("config.looks.animations")

require("config.software.general")
require("config.software.keybinds")(apps)
require("config.software.rules")

-- Panel-managed overrides must stay last so they win over tracked defaults.
require("config.overrides")
