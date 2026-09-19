local contextline = require("contextline")

vim.cmd("enew")
vim.bo.filetype = "python"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "class Demo:",
  "    def run(self):",
  "        return 1",
})

local ok = pcall(vim.treesitter.start, 0, "python")
if not ok then
  print("treesitter_spec: SKIP (python parser is not installed)")
  return
end
vim.api.nvim_win_set_cursor(0, { 2, 5 })
local info = contextline.get_info({ bufnr = 0, winid = 0 })
assert(info and info.language == "PYTHON", "Tree-sitter provider did not detect Python")
assert(#info.segments == 2, "Python class and method hierarchy was not preserved")
assert(info.segments[1].text == "Demo", "Python class name was not detected")
assert(info.segments[1].kind == "class_definition", "Python class node kind was not preserved")
assert(info.segments[1].label == "class", "Python class label was not assigned")
assert(info.segments[1].lnum == 1, "Python class line was not preserved")
assert(info.segments[2].text == "run", "Python method was not detected")
assert(info.segments[2].label == "method", "Python method label was not assigned")
assert(contextline.format(info, { plain = true, show_labels = true }) == "PYTHON | class Demo | method run", "Python hierarchy formatting is incomplete")

-- Verify rich icons and symbol metadata
assert(info.segments[1].icon ~= nil and info.segments[1].icon ~= "", "Class icon was not assigned")
assert(info.segments[2].icon ~= nil and info.segments[2].icon ~= "", "Method icon was not assigned")

print("treesitter_spec: OK")
