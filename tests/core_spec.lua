local contextline = require("contextline")

contextline.setup({ redraw = false })
contextline.register("test-language", {
  filetypes = { "testft" },
  get_info = function()
    return {
      language = "Test",
      segments = {
        { text = "class Demo", hl = "Type" },
        { text = "method run", hl = "Function" },
      },
    }
  end,
})

vim.bo.filetype = "testft"
local info = contextline.get_info({ bufnr = 0, winid = 0 })
assert(info.language == "Test", "custom provider was not selected")
assert(#info.segments == 2, "provider segments were not preserved")
assert(contextline.format(info, { plain = true }) == "Test | class Demo | method run", "plain context formatting is incorrect")
local vscode_fmt = contextline.format(info, { hl_mode = false })
assert(vscode_fmt:find("Demo") and vscode_fmt:find("run"), "vscode context formatting is missing symbols")

print("core_spec: OK")

-- A file with no provider result must not produce a language-only context
-- component; Heirline uses nil to decide whether the bar is visible.
vim.bo.filetype = "plain_no_context"
assert(contextline.get_info({ bufnr = 0, winid = 0 }) == nil, "empty context should be hidden")

print("empty_context_spec: OK")
