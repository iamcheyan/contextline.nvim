local M = {}

function M.get_info(opts)
  local ok, navic = pcall(require, "nvim-navic")
  if not ok or type(navic.get_location) ~= "function" then
    return nil
  end
  local location = navic.get_location()
  if not location or location == "" then
    return nil
  end
  local segments = {}
  for item in location:gmatch("[^%s]+") do
    table.insert(segments, { text = item, hl = "Identifier" })
  end
  if #segments == 0 then
    return nil
  end
  return {
    language = vim.bo[opts.bufnr or 0].filetype:upper(),
    segments = segments,
    source = "navic",
  }
end

return M
