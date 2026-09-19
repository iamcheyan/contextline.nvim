local M = {}
local icons = require("contextline.icons")

function M.get_path_info(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" or vim.bo[bufnr].buftype ~= "" then
    return nil
  end

  local root = opts.root
  if not root or root == "" then
    -- Detect git root, workspace root, or cwd
    local git_dir = vim.fs.root(bufnr, { ".git", ".hg", "package.json", "pyproject.toml", "Makefile" })
    root = git_dir or vim.fn.getcwd()
  end

  -- Normalize paths
  bufname = vim.fs.normalize(bufname)
  root = vim.fs.normalize(root)

  local rel_path = bufname
  if bufname:sub(1, #root) == root then
    rel_path = bufname:sub(#root + 2)
  end

  local parts = vim.split(rel_path, "/", { trimempty = true })
  if #parts == 0 then
    return nil
  end

  local filename = parts[#parts]
  local dir_parts = {}
  for i = 1, #parts - 1 do
    table.insert(dir_parts, parts[i])
  end

  local max_depth = opts.max_path_depth or 3
  local path_segments = {}
  if #dir_parts > max_depth then
    table.insert(path_segments, { text = dir_parts[1], type = "path", hl = "Comment" })
    table.insert(path_segments, { text = "…", type = "path", hl = "Comment" })
    for i = #dir_parts - (max_depth - 2), #dir_parts do
      table.insert(path_segments, { text = dir_parts[i], type = "path", hl = "Comment" })
    end
  else
    for _, dir in ipairs(dir_parts) do
      table.insert(path_segments, { text = dir, type = "path", hl = "Comment" })
    end
  end

  local ext = vim.fn.fnamemodify(filename, ":e")
  local file_icon, file_icon_hl = icons.get_file_icon(filename, ext)

  local file_segment = {
    text = filename,
    type = "file",
    icon = file_icon,
    icon_hl = file_icon_hl,
    hl = "Bold",
  }

  return {
    path_segments = path_segments,
    file_segment = file_segment,
  }
end

return M
