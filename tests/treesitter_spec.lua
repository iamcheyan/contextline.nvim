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
assert(info.segments[#info.segments].text == "run", "Python method was not detected")
print("treesitter_spec: OK")
