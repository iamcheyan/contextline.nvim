local contextline = require("contextline")

vim.cmd("enew")
vim.bo.filetype = "python"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "from dataclasses import dataclass",
  "",
  "@dataclass",
  "class Transaction:",
  "    account: str",
  "    amount: int",
  "",
  "class Bank:",
  "    @property",
  "    def balance(self):",
  "        return 100",
  "",
  "    async def transfer(self, amount: int):",
  "        pass",
})

local ok = pcall(vim.treesitter.start, 0, "python")
if not ok then
  print("python_spec: SKIP (python parser is not installed)")
  return
end

-- Test 1: Dataclass field extraction
vim.api.nvim_win_set_cursor(0, { 5, 5 }) -- cursor on `account: str`
local info_field = contextline.get_info({ bufnr = 0, winid = 0 })
assert(info_field, "Contextline should detect python dataclass field")
assert(#info_field.segments == 2, "Expected 2 segments: Class and Field, got " .. #info_field.segments)
assert(info_field.segments[1].text == "Transaction", "Expected class Transaction, got " .. info_field.segments[1].text)
assert(info_field.segments[1].icon == "󰌗", "Expected Class icon 󰌗, got " .. tostring(info_field.segments[1].icon))
assert(info_field.segments[2].text == "account", "Expected field account, got " .. info_field.segments[2].text)
assert(info_field.segments[2].label == "field" or info_field.segments[2].label == "property", "Expected field label")
assert(info_field.segments[2].icon == "󰅪", "Expected Property/Field icon 󰅪, got " .. tostring(info_field.segments[2].icon))

-- Test 2: @property method extraction
vim.api.nvim_win_set_cursor(0, { 10, 10 }) -- cursor inside `balance`
local info_prop = contextline.get_info({ bufnr = 0, winid = 0 })
assert(info_prop, "Contextline should detect python @property")
assert(#info_prop.segments == 2, "Expected 2 segments: Bank and balance")
assert(info_prop.segments[1].text == "Bank")
assert(info_prop.segments[2].text == "balance")
assert(info_prop.segments[2].label == "property", "Expected property label for @property")
assert(info_prop.segments[2].icon == "󰅪", "Expected Property icon 󰅪")

-- Test 3: async method extraction
vim.api.nvim_win_set_cursor(0, { 13, 15 }) -- cursor inside `async def transfer`
local info_async = contextline.get_info({ bufnr = 0, winid = 0 })
assert(info_async, "Contextline should detect python async method")
assert(#info_async.segments == 2, "Expected 2 segments: Bank and transfer")
assert(info_async.segments[2].text == "transfer")
assert(info_async.segments[2].icon == "󰆧", "Expected Method icon 󰆧")

print("python_spec: OK")
