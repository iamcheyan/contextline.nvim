local M = {}
local icons = require("contextline.icons")

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
  -- Python
  class_definition = true,
  function_definition = true,
  async_function_definition = true,
  type_alias_statement = true,
  -- TypeScript / JavaScript
  class_declaration = true,
  interface_declaration = true,
  type_alias_declaration = true,
  enum_declaration = true,
  enum_assignment = true,
  method_definition = true,
  public_field_definition = true,
  property_signature = true,
  function_declaration = true,
  -- Rust
  struct_item = true,
  enum_item = true,
  trait_item = true,
  impl_item = true,
  function_item = true,
  type_item = true,
  -- Go
  type_spec = true,
  -- Java / C / C++
  class_specifier = true,
  struct_specifier = true,
  enum_specifier = true,
  record_declaration = true,
  namespace_definition = true,
  namespace_declaration = true,
  package_clause = true,
  -- SQL & HTML
  element = true,
  cte = true,
  create_table = true,
  select_statement = true,
}

local function short_text(node, bufnr)
  if not node then
    return ""
  end
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

local function is_python_property(node)
  local parent = node:parent()
  -- Check decorated definition for @property
  while parent do
    if parent:type() == "decorated_definition" then
      for child in parent:iter_children() do
        if child:type() == "decorator" then
          local dec_text = vim.treesitter.get_node_text(child, 0)
          if dec_text:match("property") then
            return true
          end
        end
      end
    elseif parent:type() == "class_definition" then
      break
    end
    parent = parent:parent()
  end
  return false
end

local function is_class_field_assignment(node)
  if node:type() ~= "assignment" then
    return false
  end
  local parent = node:parent()
  while parent do
    local pt = parent:type()
    if pt == "class_definition" or pt == "class_body" or pt == "block" then
      local gp = parent:parent()
      if gp and (gp:type() == "class_definition" or gp:type() == "class_body") then
        return true
      end
    end
    if pt:match("function") or pt:match("method") then
      return false
    end
    parent = parent:parent()
  end
  return false
end

local function unwrap_decorated(node)
  if node:type() == "decorated_definition" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "class_definition" or ct == "function_definition" or ct == "async_function_definition" then
        return child
      end
    end
  end
  return node
end

local function name_node(node)
  local ntype = node:type()
  if ntype == "element" then
    return first_descendant(node, "tag_name") or node
  end
  if ntype == "assignment" then
    local left = node:field("left")[1]
    if left then
      return left
    end
  end
  if ntype == "variable_declarator" then
    local name = node:field("name")[1]
    if name then
      return name
    end
  end
  if ntype == "impl_item" then
    local tr = node:field("trait")[1]
    local tp = node:field("type")[1]
    if tr and tp then
      return node -- formatted specially in symbol_name
    elseif tp then
      return tp
    end
  end
  for _, field in ipairs({ "name", "declarator", "type" }) do
    local values = node:field(field)
    if values and values[1] then
      return values[1]
    end
  end
  return node
end

local function symbol_label(node)
  local kind = node:type()
  if kind == "element" then return "element" end
  if kind:match("class") then return "class" end
  if kind:match("record") then return "record" end
  if kind:match("interface") then return "interface" end
  if kind:match("struct") then return "struct" end
  if kind:match("trait") then return "trait" end
  if kind == "impl_item" then return "impl" end
  if kind:match("enum_assignment") or kind == "enum_item" then return "enum_member" end
  if kind:match("enum") then return "enum" end
  if kind:match("namespace") or kind == "module" then return "namespace" end
  if kind == "package_clause" then return "package" end
  if kind:match("type_alias") or kind == "type_declaration" or kind == "type_spec" or kind == "type_item" then
    return "type"
  end
  if kind == "property_signature" or kind == "public_field_definition" then return "property" end
  if kind == "assignment" then return "field" end
  if kind == "cte" then return "cte" end
  if kind == "select_statement" then return "query" end
  if kind == "create_table" then return "table" end
  if is_python_property(node) then return "property" end
  if kind:match("method") or (kind:match("function") and is_nested_in_type(node)) then return "method" end
  if kind:match("function") or kind:match("declaration") or kind:match("definition") or kind:match("item") then
    return "function"
  end
  return "symbol"
end

function M.get_info(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
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
    local cur = unwrap_decorated(current)
    local ctype = cur:type()
    if symbol_nodes[ctype] then
      table.insert(nodes, 1, cur)
    elseif is_class_field_assignment(cur) then
      table.insert(nodes, 1, cur)
    elseif ctype == "variable_declarator" then
      -- Variable assigned to arrow function or class
      local value = cur:field("value")[1]
      if value and (value:type() == "arrow_function" or value:type() == "function_expression" or value:type() == "class_expression") then
        table.insert(nodes, 1, cur)
      end
    end
    current = current:parent()
  end

  if #nodes == 0 then
    return nil
  end

  local segments = {}
  local seen = {}
  for _, symbol in ipairs(nodes) do
    local label = symbol_label(symbol)
    local meta = icons.get_symbol_meta(label)
    local name = short_text(name_node(symbol), bufnr)
    if name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(segments, {
        text = name,
        kind = symbol:type(),
        symbol_kind = meta.kind or label,
        label = label,
        icon = meta.icon,
        icon_hl = meta.hl,
        hl = meta.hl,
        lnum = symbol:start() + 1,
        type = "symbol",
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
