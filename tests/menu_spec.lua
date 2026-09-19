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

-- 4. Test menu open & close
menu.open({ bufnr = 0, winid = vim.api.nvim_get_current_win() })
assert(menu.active_win ~= nil and vim.api.nvim_win_is_valid(menu.active_win), "Menu float window did not open")
menu.close()
assert(menu.active_win == nil, "Menu float window did not close cleanly")

print("menu_spec: OK")
