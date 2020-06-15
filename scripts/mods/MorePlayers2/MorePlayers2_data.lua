-- luacheck: globals get_mod
local mod = get_mod("MorePlayers2")

return {
  name = "[BETA] BTMP",
  description = mod:localize("mod_description"),
  is_togglable = false,
  custom_gui_textures = {
    ui_renderer_injections = {
      {
        "ingame_ui",
        "materials/ui/ui_1080p_store_menu",
      },
    },
  },
  options = {
    widgets = {
      {
        setting_id = "show_player_list",
        type = "checkbox",
        default_value = true,
      },
      {
        setting_id    = "font",
        type          = "dropdown",
        default_value = 2,
        options = {
          {text = "arial", value = 1 },
          {text = "hell_shark_body",   value = 2 },
          {text = "hell_shark_header", value = 3 },
        },
      },
      {
        setting_id = "font_size",
        type = "numeric",
        range = {0, 255},
        default_value = 18,
      },
      {
        setting_id = "use_mmo_names_colors",
        type = "checkbox",
        default_value = false
      },
    },
  },
}
