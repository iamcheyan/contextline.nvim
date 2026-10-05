local contextline = require("contextline")
local info = { segments = { { text = "DATA", type = "symbol", hl = "Type" } } }
vim.api.nvim_set_hl(0, "WinBar", { fg = "#ffd700", bg = "#000087" })
contextline.format(info, { fixed_palette = true })

-- A delayed UI adapter can update WinBar after Heirline has cached the text.
-- Existing breadcrumb groups must follow immediately, without another click.
vim.api.nvim_set_hl(0, "WinBar", { fg = "#000087", bg = "#5fffff" })
local bar = vim.api.nvim_get_hl(0, { name = "WinBar", link = false })
for _, name in ipairs({ "ContextlineText", "ContextlineActiveMenu" }) do
  local h = vim.api.nvim_get_hl(0, { name = name, link = false })
  assert(h.fg == bar.fg and h.bg == bar.bg, name .. " retained the previous winbar palette")
end
print("winbar_theme_sync_spec: OK")
