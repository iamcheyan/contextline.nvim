local contextline = require("contextline")
local lsp = require("contextline.lsp")

vim.cmd("enew")
vim.bo.filetype = "python"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "class DemoServer:",
  "    def start(self):",
  "        pass",
})

-- 1. Test Fallback: Before LSP is attached / populated, Tree-sitter works as fallback
pcall(vim.treesitter.start, 0, "python")
vim.api.nvim_win_set_cursor(0, { 2, 8 })
local ts_info = contextline.get_info({ bufnr = 0 })
assert(ts_info, "Tree-sitter fallback should provide info")
assert(ts_info.source == "treesitter", "Expected source 'treesitter', got " .. tostring(ts_info.source))
assert(#ts_info.segments == 2, "Expected 2 segments from Tree-sitter")

-- 2. Test LSP priority: Mock an LSP documentSymbol cache
local bufnr = vim.api.nvim_get_current_buf()
lsp._cache[bufnr] = {
  tick = vim.b[bufnr].changedtick,
  loading = false,
  symbols = {
    {
      name = "DemoServer",
      kind = 5, -- Class
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 2, character = 12 },
      },
      children = {
        {
          name = "start",
          kind = 6, -- Method
          range = {
            start = { line = 1, character = 4 },
            ["end"] = { line = 2, character = 12 },
          },
        },
      },
    },
  },
}

-- Now query contextline with LSP cache present
local lsp_info = contextline.get_info({ bufnr = bufnr })
assert(lsp_info, "LSP info should be retrieved")
assert(lsp_info.source == "lsp", "Expected source 'lsp' to take priority over 'treesitter', got " .. tostring(lsp_info.source))
assert(#lsp_info.segments == 2, "Expected 2 segments from LSP")
assert(lsp_info.segments[1].text == "DemoServer")
assert(lsp_info.segments[1].icon == "󰌗", "Expected Class icon 󰌗")
assert(lsp_info.segments[2].text == "start")
assert(lsp_info.segments[2].icon == "󰆧", "Expected Method icon 󰆧")

-- Clean cache
lsp._cache[bufnr] = nil

-- Should seamlessly fall back to Tree-sitter again
local fallback_info = contextline.get_info({ bufnr = bufnr })
assert(fallback_info.source == "treesitter", "Should fall back to treesitter when LSP cache is clear")

print("lsp_spec: OK")
