-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.

-- For example, changing the initial geometry for new windows:
config.initial_cols = 120
config.initial_rows = 28

-- or, changing the font size and color scheme.
config.font = wezterm.font("Hack Nerd Font Mono", { weight = "Regular", stretch = "Normal", style = "Normal" })
config.font_size = 16

-- These are configuration options (top level)
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

config.color_scheme = "Decaf (base16)"
config.enable_kitty_keyboard = true

config.keys = {
  {
    key = "W",
    mods = "CMD|SHIFT",
    action = wezterm.action.CloseCurrentPane { confirm = true },
  },
}

-- Finally, return the configuration to wezterm:
return config
