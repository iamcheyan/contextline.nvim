local M = {}

local language_names = {
  bash = "BASH",
  c = "C",
  cpp = "C++",
  go = "GO",
  html = "HTML",
  java = "JAVA",
  javascript = "JAVASCRIPT",
  lua = "LUA",
  python = "PYTHON",
  ruby = "RUBY",
  rust = "RUST",
  sql = "SQL",
  tsx = "TSX",
  xml = "XML",
  typescript = "TYPESCRIPT",
}

local symbol_nodes = {
  class = true,
  class_declaration = true,
  class_definition = true,
  class_specifier = true,
  namespace_definition = true,
  package_clause = true,
  record_declaration = true,
  enum_declaration = true,
  enum_item = true,
  enum_specifier = true,
  function_declaration = true,
  function_definition = true,
  function_item = true,
  function_literal = true,
  impl_item = true,
  interface_declaration = true,
  method_declaration = true,
  method_definition = true,
  method = true,
  namespace_declaration = true,
  ["function"] = true,
  element = true,
  singleton_method = true,
  cte = true,
  create_table = true,
  select_statement = true,
  struct_item = true,
  struct_specifier = true,
  trait_item = true,
  type_declaration = true,
  type_alias_declaration = true,
}

local function short_text(node, bufnr)
  local text = vim.treesitter.get_node_text(node, bufnr):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #text > 72 then
    text = text:sub(1, 69) .. "..."
  end
  return text
end

local function first_descendant(node, wanted)
  for child in node:iter_children() do
    if child:type() == wanted then
      return child
    end
    local descendant = first_descendant(child, wanted)
    if descendant then
      return descendant
    end
  end
  return nil
end

local function name_node(node)
  if node:type() == "element" then
    return first_descendant(node, "tag_name") or node
  end
  for _, field in ipairs({ "name", "declarator", "type" }) do
    local values = node:field(field)
    if values and values[1] then
      return values[1]
    end
  end
  return node
end

local function is_nested_in_type(node)
  local parent = node:parent()
  while parent do
    local kind = parent:type()
    if kind:match("class") or kind:match("struct") or kind:match("interface") or kind:match("trait") or kind:match("impl") then
      return true
    end
    parent = parent:parent()
  end
  return false
end

local function symbol_label(node)
  local kind = node:type()
  if kind == "element" then return "element" end
  if kind:match("class") then return "class" end
  if kind:match("record") then return "record" end
  if kind:match("interface") then return "interface" end
  if kind:match("struct") then return "struct" end
  if kind:match("trait") then return "trait" end
  if kind:match("enum") then return "enum" end
  if kind:match("namespace") or kind == "module" then return "namespace" end
  if kind == "package_clause" then return "package" end
  if kind:match("type_alias") or kind == "type_declaration" then return "type" end
  if kind == "cte" then return "cte" end
  if kind == "select_statement" then return "query" end
  if kind == "create_table" then return "table" end
  if kind:match("method") or (kind:match("function") and is_nested_in_type(node)) then return "method" end
  if kind:match("function") or kind:match("declaration") or kind:match("definition") or kind:match("item") then
    return "function"
  end
  return "symbol"
end

local function node_kind(node)
  local kind = node:type()
  if kind:match("class") or kind:match("struct") or kind:match("interface") or kind:match("trait") or kind:match("enum") or kind:match("record") then
    return "Type"
  end
  if kind:match("function") or kind:match("method") or kind:match("declaration") or kind:match("definition") or kind:match("item") then
    return "Function"
  end
  return "Identifier"
end

function M.get_info(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local winid = opts.winid or vim.api.nvim_get_current_win()
  local ft = vim.bo[bufnr].filetype
  local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if parser_ok and parser then
    pcall(parser.parse, parser)
  end
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = bufnr,
    winnr = winid,
  })
  if not ok or not node then
    return nil
  end

  local nodes = {}
  local current = node
  while current do
    if symbol_nodes[current:type()] then
      table.insert(nodes, 1, current)
    end
    current = current:parent()
  end
  if #nodes == 0 then
    return nil
  end

  local segments = {}
  local seen = {}
  for _, symbol in ipairs(nodes) do
    local name = short_text(name_node(symbol), bufnr)
    if name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(segments, {
        text = name,
        label = symbol_label(symbol),
        hl = node_kind(symbol),
        lnum = symbol:start() + 1,
        kind = symbol:type(),
      })
    end
  end
  if #segments == 0 then
    return nil
  end
  return {
    language = language_names[ft] or ft:upper(),
    segments = segments,
    source = "treesitter",
  }
end

return M
