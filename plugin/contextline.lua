if vim.g.loaded_contextline_nvim then
  return
end
vim.g.loaded_contextline_nvim = true
require("contextline").setup()
