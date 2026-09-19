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
assert(contextline.format(info) == "Test | class Demo | method run", "context formatting is incorrect")

print("core_spec: OK")
