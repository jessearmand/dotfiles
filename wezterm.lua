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
    action = wezterm.action.CloseCurrentPane({ confirm = true }),
  },
}

local act = wezterm.action

config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "CTRL",
    action = act.OpenLinkAtMouseCursor,
  },
  -- Disable the 'Down' event of CTRL-Click to avoid weird program behaviors
  {
    event = { Down = { streak = 1, button = "Left" } },
    mods = "CTRL",
    action = act.Nop,
  },
}

local function is_shell(foreground_process_name)
  local shell_names = { "bash", "zsh", "fish", "sh", "ksh", "dash" }
  local process = string.match(foreground_process_name, "[^/\\]+$") or foreground_process_name
  for _, shell in ipairs(shell_names) do
    if process == shell then
      return true
    end
  end
  return false
end

wezterm.on("open-uri", function(window, pane, uri)
  local editor = "nvim"

  if uri:find("^file:") == 1 and not pane:is_alt_screen_active() then
    -- We're processing an hyperlink and the uri format should be: file://[HOSTNAME]/PATH[#linenr]
    -- Also the pane is not in an alternate screen (an editor, less, etc)
    local url = wezterm.url.parse(uri)
    if is_shell(pane:get_foreground_process_name()) then
      -- A shell has been detected. Wezterm can check the file type directly
      -- figure out what kind of file we're dealing with
      local success, stdout, _ = wezterm.run_child_process({
        "file",
        "--brief",
        "--mime-type",
        url.file_path,
      })
      if success then
        if stdout:find("directory") then
          pane:send_text(wezterm.shell_join_args({ "cd", url.file_path }) .. "\r")
          pane:send_text(wezterm.shell_join_args({
            "ls",
            "-a",
            "-p",
            "--group-directories-first",
          }) .. "\r")
          return false
        end

        if stdout:find("text") then
          if url.fragment then
            pane:send_text(wezterm.shell_join_args({
              editor,
              "+" .. url.fragment,
              url.file_path,
            }) .. "\r")
          else
            pane:send_text(wezterm.shell_join_args({ editor, url.file_path }) .. "\r")
          end
          return false
        end
      end
    else
      -- No shell detected, we're probably connected with SSH, use fallback command
      local edit_cmd = url.fragment and editor .. " +" .. url.fragment .. ' "$_f"' or editor .. ' "$_f"'
      local cmd = '_f="'
        .. url.file_path
        .. '"; { test -d "$_f" && { cd "$_f" ; ls -a -p --hyperlink --group-directories-first; }; } '
        .. '|| { test "$(file --brief --mime-type "$_f" | cut -d/ -f1 || true)" = "text" && '
        .. edit_cmd
        .. "; }; echo"
      pane:send_text(cmd .. "\r")
      return false
    end
  end

  -- without a return value, we allow default actions
end)

-- Finally, return the configuration to wezterm:
return config
