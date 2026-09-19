local M = {}
local treesitter = require("contextline.treesitter")
local navic = require("contextline.navic")

M.config = {
  separator = " | ",
  show_labels = true,
  redraw = true,
  use_navic = true,
  use_treesitter = true,
}
M._providers = {}
M._setup = false

local function filetype(bufnr)
  return vim.bo[bufnr or 0].filetype
end

function M.register(name, provider)
  assert(type(name) == "string", "contextline provider name must be a string")
  assert(type(provider) == "table", "contextline provider must be a table")
  assert(type(provider.get_info) == "function", "contextline provider requires get_info")
  M._providers[name] = provider
  provider.name = provider.name or name
  provider.filetypes = provider.filetypes or {}
  return provider
end

function M.unregister(name)
  M._providers[name] = nil
end

function M.providers()
  return vim.deepcopy(M._providers)
end

local function custom_info(opts)
  local ft = filetype(opts.bufnr)
  for _, provider in pairs(M._providers) do
    if vim.tbl_contains(provider.filetypes, ft) then
      local ok, info = pcall(provider.get_info, opts)
      if ok and info then
        info.provider = provider.name
        return info
      end
    end
  end
  return nil
end

function M.get_info(opts)
  opts = vim.tbl_extend("force", { bufnr = 0, winid = vim.api.nvim_get_current_win() }, opts or {})
  local custom = custom_info(opts)
  if custom then
    return custom
  end
  if M.config.use_navic then
    local ok, info = pcall(navic.get_info, opts)
    if ok and info then
      return info
    end
  end
  if M.config.use_treesitter then
    local ok, info = pcall(treesitter.get_info, opts)
    if ok and info then
      return info
    end
  end
  return nil
end

function M.format(info, opts)
  if not info then
    return ""
  end
  opts = opts or {}
  local separator = opts.separator or M.config.separator
  local parts = {}
  if info.language and info.language ~= "" then
    table.insert(parts, info.language)
  end
  for _, segment in ipairs(info.segments or {}) do
    local text = segment.text
    if M.config.show_labels and segment.label and segment.label ~= "" then
      text = segment.label .. " " .. text
    end
    table.insert(parts, text)
  end
  return table.concat(parts, separator)
end

function M.get(opts)
  return M.format(M.get_info(opts), opts)
end

function M.component(opts)
  return function()
    return M.get(opts)
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M._setup then
    return
  end
  M._setup = true
  if M.config.redraw then
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter", "LspAttach" }, {
      group = vim.api.nvim_create_augroup("ContextlineNvim", { clear = true }),
      callback = function() vim.cmd("redrawstatus") end,
    })
  end
end

return M
