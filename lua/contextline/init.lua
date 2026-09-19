local M = {}
local treesitter = require("contextline.treesitter")
local lsp = require("contextline.lsp")
local navic = require("contextline.navic")
local path_util = require("contextline.path")

M.config = {
  separator = "  ",
  show_path = true,
  max_path_depth = 3,
  show_file = true,
  show_icons = true,
  show_labels = false,
  use_lsp = true,
  use_navic = true,
  use_treesitter = true,
  hl_mode = true,
  redraw = true,
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
  if opts.bufnr == 0 then
    opts.bufnr = vim.api.nvim_get_current_buf()
  end

  local info = nil

  -- 1. Priority: Custom registered provider (e.g. COBOL, Batch)
  info = custom_info(opts)

  -- 2. Priority: LSP (Native LSP documentSymbol cache / navic)
  if not info and M.config.use_lsp then
    local ok, lsp_info = pcall(lsp.get_info, opts)
    if ok and lsp_info and lsp_info.segments and #lsp_info.segments > 0 then
      info = lsp_info
    end
  end

  -- 3. Priority: nvim-navic (if enabled and not caught by LSP)
  if not info and M.config.use_navic then
    local ok, navic_info = pcall(navic.get_info, opts)
    if ok and navic_info and navic_info.segments and #navic_info.segments > 0 then
      info = navic_info
    end
  end

  -- 4. Priority: Tree-sitter (保底方案)
  if not info and M.config.use_treesitter then
    local ok, ts_info = pcall(treesitter.get_info, opts)
    if ok and ts_info and ts_info.segments and #ts_info.segments > 0 then
      info = ts_info
    end
  end

  -- If neither provided segments, create a minimal base info if buffer is a valid file
  if not info then
    local ft = filetype(opts.bufnr)
    if ft and ft ~= "" then
      info = {
        language = ft:upper(),
        segments = {},
        source = "file",
      }
    else
      return nil
    end
  end

  -- Attach path and file segments
  local path_data = path_util.get_path_info({
    bufnr = opts.bufnr,
    max_path_depth = opts.max_path_depth or M.config.max_path_depth,
  })

  if path_data then
    info.path = path_data.path_segments
    info.file = path_data.file_segment
  end

  -- Assemble combined `all` segment list for rich breadcrumb rendering
  local all = {}
  local show_path = opts.show_path ~= nil and opts.show_path or M.config.show_path
  if show_path and info.path then
    for _, p in ipairs(info.path) do
      table.insert(all, p)
    end
  end

  local show_file = opts.show_file ~= nil and opts.show_file or M.config.show_file
  if show_file and info.file then
    table.insert(all, info.file)
  end

  if info.segments then
    for _, s in ipairs(info.segments) do
      table.insert(all, s)
    end
  end

  info.all = all
  return info
end

function M.format(info, opts)
  if not info then
    return ""
  end
  opts = opts or {}

  -- Legacy / Plain text format (for specs or plain statuslines)
  if opts.plain or (opts.show_icons == false and opts.show_labels == true) then
    local separator = opts.separator or " | "
    local parts = {}
    if info.language and info.language ~= "" then
      table.insert(parts, info.language)
    end
    for _, segment in ipairs(info.segments or {}) do
      local text = segment.text
      if segment.label and segment.label ~= "" and (opts.show_labels ~= false) then
        text = segment.label .. " " .. text
      end
      table.insert(parts, text)
    end
    return table.concat(parts, separator)
  end

  local separator = opts.separator or M.config.separator
  local show_icons = opts.show_icons ~= nil and opts.show_icons or M.config.show_icons
  local show_labels = opts.show_labels ~= nil and opts.show_labels or M.config.show_labels
  local hl_mode = opts.hl_mode ~= nil and opts.hl_mode or M.config.hl_mode

  local segments = info.all or info.segments or {}
  if #segments == 0 then
    return ""
  end

  local formatted_parts = {}
  for i, seg in ipairs(segments) do
    local piece = ""
    local is_leaf = (i == #segments)

    if show_icons and seg.icon and seg.icon ~= "" then
      if hl_mode and seg.icon_hl then
        piece = string.format("%%#%s#%s%%*", seg.icon_hl, seg.icon) .. " "
      else
        piece = seg.icon .. " "
      end
    end

    local text = seg.text or ""
    if show_labels and seg.label and seg.label ~= "" and seg.type == "symbol" then
      text = seg.label .. " " .. text
    end

    if hl_mode then
      local hl = is_leaf and (seg.hl or "Bold") or (seg.hl or "Normal")
      piece = piece .. string.format("%%#%s#%s%%*", hl, text)
    else
      piece = piece .. text
    end

    table.insert(formatted_parts, piece)
  end

  local sep_str = hl_mode and string.format("%%#Comment#%s%%*", separator) or separator
  return table.concat(formatted_parts, sep_str)
end

function M.get(opts)
  return M.format(M.get_info(opts), opts)
end

function M.component(opts)
  return function()
    return M.get(opts)
  end
end

-- First-class Heirline component factory with per-segment highlights and clean separation
function M.heirline_component(opts)
  opts = opts or {}
  local sep_text = opts.separator or M.config.separator
  return {
    condition = function()
      if vim.bo.buftype ~= "" then
        return false
      end
      return M.get_info(opts) ~= nil
    end,
    init = function(self)
      local info = M.get_info(opts)
      self.child = nil
      if not info or not info.all or #info.all == 0 then
        return
      end

      local children = {}
      local total = #info.all
      for i, seg in ipairs(info.all) do
        local is_leaf = (i == total)
        local child = {
          {
            condition = function()
              return seg.icon ~= nil and seg.icon ~= ""
            end,
            provider = seg.icon and (seg.icon .. " ") or "",
            hl = seg.icon_hl or seg.hl or "Normal",
          },
          {
            provider = seg.text or "",
            hl = is_leaf and { fg = "fg", bold = true } or (seg.hl or "Normal"),
          },
        }

        table.insert(children, child)

        if i < total then
          table.insert(children, {
            provider = sep_text,
            hl = "Comment",
          })
        end
      end
      self.child = self:new(children, 1)
    end,
    provider = function(self)
      return self.child and self.child:eval() or ""
    end,
    update = { "CursorMoved", "CursorMovedI", "BufEnter" },
  }
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M._setup then
    return
  end
  M._setup = true

  local group = vim.api.nvim_create_augroup("ContextlineNvim", { clear = true })

  if M.config.redraw then
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
      group = group,
      callback = function()
        vim.cmd("redrawstatus")
      end,
    })
  end

  if M.config.use_lsp then
    vim.api.nvim_create_autocmd({ "LspAttach", "BufWritePost" }, {
      group = group,
      callback = function(args)
        pcall(lsp.request_symbols, args.buf)
      end,
    })
  end
end

return M
