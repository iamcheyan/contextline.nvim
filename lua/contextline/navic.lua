local M = {}
local icons = require("contextline.icons")

function M.get_info(opts)
  local ok, navic = pcall(require, "nvim-navic")
  if not ok then
    return nil
  end

  local bufnr = opts.bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if type(navic.is_available) == "function" and not navic.is_available(bufnr) then
    return nil
  end

  -- Preferred: structured data with LSP kind & symbol names
  if type(navic.get_data) == "function" then
    local data = navic.get_data(bufnr)
    if data and #data > 0 then
      local segments = {}
      for _, item in ipairs(data) do
        local meta = icons.get_symbol_meta(item.kind or item.type)
        table.insert(segments, {
          text = item.name,
          kind = item.type or meta.kind,
          symbol_kind = meta.kind or item.type,
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
          source = "navic",
        }
      end
    end
  end

  -- Fallback: parse get_location
  if type(navic.get_location) == "function" then
    local location = navic.get_location()
    if location and location ~= "" then
      local segments = {}
      for item in location:gmatch("[^%s]+") do
        table.insert(segments, {
          text = item,
          kind = "symbol",
          label = "symbol",
          icon = "󰘦",
          icon_hl = "Identifier",
          hl = "Identifier",
          type = "symbol",
        })
      end
      if #segments > 0 then
        return {
          language = vim.bo[bufnr].filetype:upper(),
          segments = segments,
          source = "navic",
        }
      end
    end
  end

  return nil
end

return M
