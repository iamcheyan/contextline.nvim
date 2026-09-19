local M = {}
local icons = require("contextline.icons")

M._cache = {}

local function in_range(pos, range)
  local s = range["start"]
  local e = range["end"]
  if not s or not e then
    return false
  end
  if pos.line < s.line or pos.line > e.line then
    return false
  end
  if pos.line == s.line and pos.character < s.character then
    return false
  end
  if pos.line == e.line and pos.character > e.character then
    return false
  end
  return true
end

local function find_enclosing_symbols(symbols, pos, acc)
  for _, sym in ipairs(symbols) do
    local range = sym.range or (sym.location and sym.location.range)
    if range and in_range(pos, range) then
      table.insert(acc, sym)
      if sym.children and #sym.children > 0 then
        find_enclosing_symbols(sym.children, pos, acc)
      end
      break
    end
  end
end

local function get_lsp_clients(bufnr)
  if vim.lsp.get_clients then
    return vim.lsp.get_clients({ bufnr = bufnr })
  elseif vim.lsp.get_active_clients then
    return vim.lsp.get_active_clients({ bufnr = bufnr })
  end
  return {}
end

function M.request_symbols(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local clients = get_lsp_clients(bufnr)
  local symbol_client = nil
  for _, client in ipairs(clients) do
    if client.server_capabilities and client.server_capabilities.documentSymbolProvider then
      symbol_client = client
      break
    end
  end

  if not symbol_client then
    return
  end

  local tick = vim.b[bufnr].changedtick
  local cached = M._cache[bufnr]
  if cached and cached.tick == tick and cached.loading then
    return
  end

  M._cache[bufnr] = M._cache[bufnr] or {}
  M._cache[bufnr].loading = true

  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  symbol_client:request("textDocument/documentSymbol", params, function(err, result, _)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M._cache[bufnr] = nil
      return
    end
    M._cache[bufnr] = {
      tick = vim.b[bufnr].changedtick,
      symbols = (not err and result) and result or nil,
      loading = false,
    }
    if not err and result and #result > 0 then
      vim.schedule(function()
        pcall(vim.cmd, "redrawstatus")
      end)
    end
  end, bufnr)
end

function M.get_info(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local winid = opts.winid or vim.api.nvim_get_current_win()

  -- 1. If nvim-navic is available and attached to buffer, use its synchronous data
  local navic_ok, navic = pcall(require, "nvim-navic")
  if navic_ok and type(navic.is_available) == "function" and navic.is_available(bufnr) then
    local data = type(navic.get_data) == "function" and navic.get_data(bufnr)
    if data and #data > 0 then
      local segments = {}
      for _, item in ipairs(data) do
        local meta = icons.get_symbol_meta(item.kind or item.type)
        table.insert(segments, {
          text = item.name,
          kind = item.type or meta.kind,
          label = (item.type or meta.kind or ""):lower(),
          icon = item.icon or meta.icon,
          icon_hl = meta.hl,
          hl = meta.hl,
          type = "symbol",
        })
      end
      if #segments > 0 then
        return {
          language = vim.bo[bufnr].filetype:upper(),
          segments = segments,
          source = "lsp",
        }
      end
    end
  end

  local cached = M._cache[bufnr]
  local tick = vim.b[bufnr].changedtick

  if not (cached and cached.symbols and #cached.symbols > 0) then
    -- 2. Native LSP documentSymbol query & cache
    local clients = get_lsp_clients(bufnr)
    local has_symbol_provider = false
    for _, client in ipairs(clients) do
      if client.server_capabilities and client.server_capabilities.documentSymbolProvider then
        has_symbol_provider = true
        break
      end
    end

    if not has_symbol_provider then
      return nil
    end

    -- If cache is dirty or missing, trigger update in background
    if not cached or cached.tick ~= tick then
      M.request_symbols(bufnr)
    end

    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local pos = { line = cursor[1] - 1, character = cursor[2] }

  local enclosing = {}
  find_enclosing_symbols(cached.symbols, pos, enclosing)

  if #enclosing == 0 then
    return nil
  end

  local segments = {}
  for _, sym in ipairs(enclosing) do
    local meta = icons.get_symbol_meta(sym.kind)
    local lnum = sym.range and (sym.range["start"].line + 1) or nil
    table.insert(segments, {
      text = sym.name,
      kind = meta.kind or tostring(sym.kind),
      label = meta.label or "symbol",
      icon = meta.icon,
      icon_hl = meta.hl,
      hl = meta.hl,
      lnum = lnum,
      type = "symbol",
    })
  end

  return {
    language = vim.bo[bufnr].filetype:upper(),
    segments = segments,
    source = "lsp",
  }
end

return M
