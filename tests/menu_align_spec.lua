local contextline = require("contextline")
local menu = require("contextline.menu")

contextline.setup({
  redraw = false,
  separator = "  ",
  show_path = false,
  show_file = false,
  show_icons = true,
  show_labels = false,
  show_diagnostics = false,
  show_scope_lines = false,
  hl_mode = true,
  clickable = true,
})

contextline.register("align-test", {
  filetypes = { "cobol" },
  get_info = function()
    return {
      language = "COBOL",
      segments = {
        { text = "ONE", icon = "󰅪", icon_hl = "Identifier", hl = "Identifier", type = "symbol" },
        { text = "TWO", icon = "󰆧", icon_hl = "Function", hl = "Function", type = "symbol" },
        { text = "THREE", icon = "󰎠", icon_hl = "Number", hl = "Number", type = "symbol" },
      },
      source = "align-test",
    }
  end,
})

vim.o.lines = 24
vim.o.columns = 80
vim.o.showtabline = 0
vim.o.cmdheight = 1
vim.o.laststatus = 2
vim.o.number = true
vim.o.signcolumn = "yes"

vim.cmd("enew")
vim.bo.filetype = "cobol"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "       WORKING-STORAGE SECTION.",
  "       01  ONE PIC X.",
  "       01  TWO PIC X.",
  "       01  THREE PIC X.",
})

local win = vim.api.nvim_get_current_win()
-- Heirline-style leading pad in front of the contextline component.
vim.wo[win].winbar = " %{%v:lua.require'contextline'.get()%}"

local function highlight_col(winid, segment_index)
  contextline._active_menu_segment = segment_index
  contextline._active_menu_win = winid
  local ev = vim.api.nvim_eval_statusline(vim.wo[winid].winbar, {
    winid = winid,
    use_winbar = true,
    highlights = true,
  })
  for _, h in ipairs(ev.highlights or {}) do
    local groups = h.groups or { h.group }
    for _, g in ipairs(groups) do
      if g == "ContextlineActiveMenu" then
        return vim.fn.strdisplaywidth(ev.str:sub(1, h.start)), ev.str
      end
    end
  end
  return nil, ev.str
end

local function cfg_col(cfg)
  local actual = cfg.col
  if type(actual) == "table" then
    actual = actual[false] or actual[1]
  end
  return tonumber(actual)
end

for _, seg in ipairs({ 1, 2, 3 }) do
  local expected, winbar_str = highlight_col(win, seg)
  assert(expected ~= nil, "ContextlineActiveMenu missing for segment " .. seg .. ": " .. tostring(winbar_str))

  menu.open({ bufnr = 0, winid = win, segment_index = seg })
  assert(menu.active_win and vim.api.nvim_win_is_valid(menu.active_win), "menu did not open for segment " .. seg)

  local actual = cfg_col(vim.api.nvim_win_get_config(menu.active_win))
  assert(
    actual == expected,
    string.format(
      "segment %d dropdown col %s is not left-aligned (expected %s). winbar=[%s]",
      seg,
      tostring(actual),
      tostring(expected),
      tostring(winbar_str)
    )
  )
  menu.close()
end

-- Fallback path: winbar has padding but does not re-evaluate the active chip.
-- win_col_for_segment must still add the pad and keep flush-left alignment.
contextline._active_menu_segment = 2
contextline._active_menu_win = win
local expected_two, _ = highlight_col(win, 2)
vim.wo[win].winbar = " %{%v:lua.require'contextline'.get()%}"
-- Simulate a cached inactive winbar by measuring with the helper after
-- swapping in a static evaluated prefix + inactive contextline string.
contextline._active_menu_segment = nil
local inactive = vim.api.nvim_eval_statusline(require("contextline").get({ winid = win }), {
  winid = win,
  use_winbar = true,
}).str
vim.wo[win].winbar = " " .. inactive:gsub("%%", "%%%%")
contextline._active_menu_segment = 2
contextline._active_menu_win = win
local fallback_col = menu.win_col_for_segment(win)
assert(
  fallback_col == expected_two,
  string.format("fallback col %s ~= highlight col %s", tostring(fallback_col), tostring(expected_two))
)

-- Restore a live winbar for the remaining checks.
vim.wo[win].winbar = " %{%v:lua.require'contextline'.get()%}"

-- First click vs second click: Heirline evaluates get() with no winid while
-- the dropdown float is current. The chip must still render for the source
-- window, using g:statusline_winid (the window whose winbar is being drawn).
menu.open({ bufnr = 0, winid = win, segment_index = 2 })
assert(menu.active_win and vim.api.nvim_win_is_valid(menu.active_win), "menu did not open")
assert(vim.api.nvim_get_current_win() == menu.active_win, "expected to be inside the dropdown float")

vim.g.statusline_winid = win
local painted = contextline.get({ separator = "  " })
assert(
  painted:find("ContextlineActiveMenu", 1, true),
  "winbar chip vanished after the float stole focus; first click would show no selection. got: " .. painted
)

-- A different window's winbar must not inherit the chip.
local other = vim.api.nvim_open_win(0, false, {
  relative = "editor",
  row = 2,
  col = 2,
  width = 20,
  height = 5,
  style = "minimal",
})
vim.g.statusline_winid = other
local other_painted = contextline.get({ separator = "  " })
assert(
  not other_painted:find("ContextlineActiveMenu", 1, true),
  "chip leaked onto another window's winbar"
)
vim.api.nvim_win_close(other, true)

menu.close()
print("menu_align_spec: OK")
