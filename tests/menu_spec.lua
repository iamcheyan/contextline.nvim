local contextline = require("contextline")
local menu = require("contextline.menu")

-- 1. Test Python symbol collection
vim.cmd("enew")
vim.bo.filetype = "python"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "class Runner:",
  "    def start(self):",
  "        pass",
  "    def finish(self):",
  "        pass",
})
pcall(vim.treesitter.start, 0, "python")

local py_symbols = menu.get_symbols(0)
assert(#py_symbols >= 3, "Python symbols were not collected: " .. #py_symbols)
assert(py_symbols[1].name:match("Runner"), "Class Runner was not collected")
assert(py_symbols[2].name:match("start"), "Method start was not collected")
assert(py_symbols[3].name:match("finish"), "Method finish was not collected")

-- 2. Test COBOL symbol collection
vim.cmd("enew")
vim.bo.filetype = "cobol"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "       IDENTIFICATION DIVISION.",
  "       DATA DIVISION.",
  "       WORKING-STORAGE SECTION.",
  "       01  WS-ACCOUNT PIC X(10).",
  "       PROCEDURE DIVISION.",
  "       1000-PROCESS.",
  "           DISPLAY 'OK'.",
})

local cob_symbols = menu.get_symbols(0)
assert(#cob_symbols >= 4, "COBOL symbols were not collected: " .. #cob_symbols)
assert(cob_symbols[1].name:match("IDENTIFICATION DIVISION"), "IDENTIFICATION DIVISION missing")
assert(cob_symbols[2].name:match("DATA DIVISION"), "DATA DIVISION missing")

-- 3. Test Windows Batch symbol collection
vim.cmd("enew")
vim.bo.filetype = "dosbatch"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "@echo off",
  ":start",
  "echo running",
  ":cleanup",
  "echo done",
})

local bat_symbols = menu.get_symbols(0)
assert(#bat_symbols == 2, "Batch symbols count mismatch: " .. #bat_symbols)
assert(bat_symbols[1].name == ":start", "Batch :start missing")
assert(bat_symbols[2].name == ":cleanup", "Batch :cleanup missing")

-- 4. Test menu open & close with segment filtering
local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
vim.keymap.set("n", "j", function() end, {
  buffer = source_buf,
  desc = "menu_spec original j mapping",
})
local function buffer_maps(bufnr, lhs)
  local result = {}
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if mapping.lhs == lhs then table.insert(result, mapping) end
  end
  return result
end
local source_j_maps = buffer_maps(source_buf, "j")
menu.open({ bufnr = 0, winid = source_win, segment_index = 1 })
assert(menu.active_win ~= nil and vim.api.nvim_win_is_valid(menu.active_win), "Menu float window did not open for segment 1")
assert(vim.api.nvim_get_current_win() == source_win, "Opening the menu must keep focus in the source window")
assert(vim.api.nvim_get_current_buf() == source_buf, "Opening the menu must keep the source buffer current")
local initial_menu_row = vim.api.nvim_win_get_cursor(menu.active_win)[1]
vim.api.nvim_feedkeys("j", "x", false)
assert(vim.api.nvim_win_get_cursor(menu.active_win)[1] == initial_menu_row + 1, "j should move the popup selection without moving the source cursor")
assert(vim.api.nvim_get_current_win() == source_win, "Menu navigation must not change the focused window")
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
assert(menu.active_win == nil, "Escape should close the popup while focus stays in the source window")
local restored_j_maps = buffer_maps(source_buf, "j")
assert(
  #restored_j_maps == #source_j_maps,
  string.format("Closing the menu must restore source-buffer j mappings: before=%s after=%s", vim.inspect(source_j_maps), vim.inspect(restored_j_maps))
)
assert(restored_j_maps[1].desc == "menu_spec original j mapping", "Closing the menu must restore the original source-buffer mapping")

menu.open({ bufnr = 0, winid = source_win, segment_index = 1 })
assert(menu.active_win ~= nil and vim.api.nvim_win_is_valid(menu.active_win), "Menu should reopen after Escape")
menu.close()
assert(menu.active_win == nil, "Menu float window did not close cleanly")

menu.open({ bufnr = 0, winid = source_win, segment_index = 2 })
assert(menu.active_win ~= nil and vim.api.nvim_win_is_valid(menu.active_win), "Menu float window did not open for segment 2")

-- 5. Test mouse boundary safety (line 0 or out of range shouldn't throw)
local win = menu.active_win
local buf = menu.active_buf
assert(win and buf, "Expected active menu win and buf")
assert(contextline._active_menu_segment == 2, "Active menu segment should be 2")
local cfg = vim.api.nvim_win_get_config(win)
assert(cfg.row == 0, "Floating window should be tightly anchored at row 0")
menu.close()
assert(contextline._active_menu_segment == nil, "Active menu segment should be nil after close")
assert(vim.api.nvim_get_current_win() == source_win, "Closing the popup must leave focus in the source window")

print("menu_spec: OK")
