local contextline = require("contextline")

vim.cmd("enew")
vim.bo.filetype = "typescript"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "interface JobResult {",
  "  jobId: string;",
  "  status: string;",
  "}",
  "",
  "class NightJob {",
  "  validateInput(path: string): JobResult {",
  "    return { jobId: '1', status: 'OK' };",
  "  }",
  "}",
})

local ok = pcall(vim.treesitter.start, 0, "typescript")
if not ok then
  print("typescript_spec: SKIP (typescript parser is not installed)")
  return
end

-- Test 1: Interface and Property
vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- cursor on `jobId: string;`
local info_prop = contextline.get_info({ bufnr = 0, winid = 0 })
assert(info_prop, "Contextline should detect TS interface & property")
assert(#info_prop.segments == 2, "Expected 2 segments: Interface and Property, got " .. #info_prop.segments)
assert(info_prop.segments[1].text == "JobResult")
assert(info_prop.segments[1].icon == "󰠱", "Expected Interface icon 󰠱")
assert(info_prop.segments[2].text == "jobId")
assert(info_prop.segments[2].icon == "󰅪", "Expected Property icon 󰅪")

-- Test 2: Class and Method
vim.api.nvim_win_set_cursor(0, { 7, 6 }) -- cursor inside `validateInput`
local info_method = contextline.get_info({ bufnr = 0, winid = 0 })
assert(info_method, "Contextline should detect TS class & method")
assert(#info_method.segments == 2, "Expected 2 segments: Class and Method")
assert(info_method.segments[1].text == "NightJob")
assert(info_method.segments[1].icon == "󰌗", "Expected Class icon 󰌗")
assert(info_method.segments[2].text == "validateInput")
assert(info_method.segments[2].icon == "󰆧", "Expected Method icon 󰆧")

print("typescript_spec: OK")
