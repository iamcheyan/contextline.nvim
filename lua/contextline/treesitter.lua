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
  json = "JSON",
  lua = "LUA",
  markdown = "MARKDOWN",
  python = "PYTHON",
  ruby = "RUBY",
  rust = "RUST",
  sql = "SQL",
  sh = "SH",
  zsh = "ZSH",
  toml = "TOML",
  tsx = "TSX",
  typescript = "TYPESCRIPT",
  xml = "XML",
  yaml = "YAML",
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
  -- Java
  constructor_declaration = true,
  method_declaration = true,
  field_declaration = true,
  record_declaration = true,
  -- Go
  type_spec = true,
  -- Ruby
  class = true,
  module = true,
  method = true,
  singleton_method = true,
  -- Rust
  mod_item = true,
  struct_item = true,
  enum_item = true,
  trait_item = true,
  impl_item = true,
  function_item = true,
  type_item = true,
  -- C / C++
  class_specifier = true,
  struct_specifier = true,
  enum_specifier = true,
  namespace_definition = true,
  namespace_declaration = true,
  package_clause = true,
  package_declaration = true,
  function_definition = true,
  -- SQL & HTML
  element = true,
  cte = true,
  create_table = true,
  create_view = true,
  select_statement = true,
  -- Structured configs & Docs
  pair = true,
  block_mapping_pair = true,
  table = true,
  section = true,
  -- Control flow & loop statements (Shell, Python, etc.)
  while_statement = true,
  for_statement = true,
  if_statement = true,
  case_statement = true,
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
    if kind:match("class") or kind:match("struct") or kind:match("interface") or kind:match("trait") or kind:match("impl") or kind:match("record") then
      return true
    end
    parent = parent:parent()
  end
  return false
end

local function is_python_property(node)
  local parent = node:parent()
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

local function html_element_text(node, bufnr)
  local tag_name = ""
  local id_val = ""
  local class_val = ""

  for child in node:iter_children() do
    local ctype = child:type()
    if ctype == "start_tag" or ctype == "self_closing_tag" then
      for c in child:iter_children() do
        local ct = c:type()
        if ct == "tag_name" then
          tag_name = vim.treesitter.get_node_text(c, bufnr)
        elseif ct == "attribute" then
          local an, av
          for ac in c:iter_children() do
            local act = ac:type()
            if act == "attribute_name" then
              an = vim.treesitter.get_node_text(ac, bufnr)
            elseif act == "quoted_attribute_value" or act == "attribute_value" then
              av = vim.treesitter.get_node_text(ac, bufnr):gsub("[\"']", "")
            end
          end
          if an == "id" and av and id_val == "" then
            id_val = av
          elseif an == "class" and av and class_val == "" then
            class_val = av:match("%S+") or av
          end
        end
      end
      break
    end
  end

  if tag_name == "html" or tag_name == "body" or tag_name == "head" then
    return nil -- Skip boring top-level boilerplate
  end

  if id_val ~= "" then
    return tag_name .. "#" .. id_val
  elseif class_val ~= "" then
    return tag_name .. "." .. class_val
  end
  return tag_name
end

local function go_method_text(node, bufnr)
  local name_node = node:field("name")[1]
  local name = name_node and vim.treesitter.get_node_text(name_node, bufnr) or ""
  local recv = node:field("receiver")[1]
  if recv then
    local recv_type = first_descendant(recv, "type_identifier")
    if recv_type then
      local rt = vim.treesitter.get_node_text(recv_type, bufnr)
      return "(" .. rt .. ")." .. name
    end
  end
  return name
end

local function c_function_text(node, bufnr)
  local decl = node:field("declarator")[1]
  while decl and (decl:type() == "function_declarator" or decl:type() == "pointer_declarator") do
    local inner = decl:field("declarator")[1]
    if not inner then break end
    decl = inner
  end
  if decl then
    return vim.treesitter.get_node_text(decl, bufnr)
  end
  return nil
end

local function markdown_section_text(node, bufnr)
  for child in node:iter_children() do
    if child:type() == "atx_heading" then
      local hc = child:field("heading_content")[1]
      if hc then
        return short_text(hc, bufnr)
      end
    end
  end
  return nil
end

local function key_value_text(node, bufnr)
  local ntype = node:type()
  if ntype == "pair" or ntype == "block_mapping_pair" then
    local k = node:field("key")[1]
    if k then
      local raw = vim.treesitter.get_node_text(k, bufnr):gsub('^["\']', ''):gsub('["\']$', '')
      return raw:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end
  end
  if ntype == "table" then
    local k = first_descendant(node, "bare_key")
    if k then
      return vim.treesitter.get_node_text(k, bufnr)
    end
  end
  return nil
end

local function name_node(node, bufnr)
  local ntype = node:type()
  if ntype == "element" then
    return html_element_text(node, bufnr)
  end
  if ntype == "section" then
    return markdown_section_text(node, bufnr)
  end
  if ntype == "pair" or ntype == "block_mapping_pair" or ntype == "table" then
    local t = key_value_text(node, bufnr)
    if t then return t end
  end
  if ntype == "function_definition" then
    local c_fn = c_function_text(node, bufnr)
    if c_fn then return c_fn end
  end
  if ntype == "method_declaration" and vim.bo[bufnr].filetype == "go" then
    return go_method_text(node, bufnr)
  end
  if ntype == "cte" then
    for _, child in ipairs(node:named_children()) do
      if child:type() == "identifier" then
        return child
      end
    end
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
  if ntype == "field_declaration" then
    local decl = first_descendant(node, "variable_declarator")
    if decl then
      local n = decl:field("name")[1]
      if n then return n end
    end
  end
  if ntype == "impl_item" then
    local tr = node:field("trait")[1]
    local tp = node:field("type")[1]
    if tr and tp then
      return "impl " .. short_text(tr, bufnr) .. " for " .. short_text(tp, bufnr)
    elseif tp then
      return "impl " .. short_text(tp, bufnr)
    end
  end
  if ntype == "while_statement" then
    local cond = node:field("condition")[1]
    if cond then
      return "while " .. short_text(cond, bufnr)
    end
    return "while"
  end
  if ntype == "for_statement" then
    local var = node:field("variable")[1]
    if var then
      return "for " .. short_text(var, bufnr)
    end
    return "for"
  end
  if ntype == "if_statement" then
    local cond = node:field("condition")[1]
    if cond then
      return "if " .. short_text(cond, bufnr)
    end
    return "if"
  end
  if ntype == "case_statement" then
    local val = node:field("value")[1]
    if val then
      return "case " .. short_text(val, bufnr)
    end
    return "case"
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
  if kind == "section" then return "heading" end
  if kind == "pair" or kind == "block_mapping_pair" then return "key" end
  if kind == "table" then return "table" end
  if kind:match("class") then return "class" end
  if kind:match("record") then return "record" end
  if kind:match("interface") then return "interface" end
  if kind:match("struct") then return "struct" end
  if kind:match("trait") then return "trait" end
  if kind == "impl_item" then return "impl" end
  if kind:match("enum_assignment") or kind == "enum_item" then return "enum_member" end
  if kind:match("enum") then return "enum" end
  if kind:match("namespace") or kind == "module" or kind == "mod_item" then return "namespace" end
  if kind:match("package") then return "package" end
  if kind:match("type_alias") or kind == "type_declaration" or kind == "type_spec" or kind == "type_item" then
    return "type"
  end
  if kind == "property_signature" or kind == "public_field_definition" then return "property" end
  if kind == "assignment" or kind == "field_declaration" then return "field" end
  if kind == "constructor_declaration" then return "constructor" end
  if kind == "cte" then return "cte" end
  if kind == "select_statement" then return "query" end
  if kind == "create_table" then return "table" end
  if kind == "create_view" then return "view" end
  if is_python_property(node) then return "property" end
  if kind:match("^while") or kind:match("^for") then return "loop" end
  if kind:match("^if") or kind:match("^case") or kind:match("^select") then return "condition" end
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
    if ctype == "module" then
      if cur:field("name")[1] then
        table.insert(nodes, 1, cur)
      end
    elseif symbol_nodes[ctype] then
      table.insert(nodes, 1, cur)
    elseif is_class_field_assignment(cur) then
      table.insert(nodes, 1, cur)
    elseif ctype == "variable_declarator" then
      local value = cur:field("value")[1]
      if value and (value:type() == "arrow_function" or value:type() == "function_expression" or value:type() == "class_expression") then
        table.insert(nodes, 1, cur)
      end
    end
    current = current:parent()
  end

  if #nodes == 0 then
    local total_lines = vim.api.nvim_buf_line_count(bufnr)
    return {
      language = language_names[ft] or ft:upper(),
      segments = {
        {
          text = "(root)",
          kind = "root",
          symbol_kind = "Root",
          label = "root",
          icon = "󰅩",
          icon_hl = "Comment",
          hl = "Comment",
          lnum = 1,
          end_lnum = total_lines,
          lines = total_lines,
          type = "symbol",
        },
      },
      source = "treesitter",
    }
  end

  local segments = {}
  local seen = {}
  for _, symbol in ipairs(nodes) do
    local label = symbol_label(symbol)
    local meta = icons.get_symbol_meta(label)
    local extracted = name_node(symbol, bufnr)
    local name = ""
    if type(extracted) == "string" then
      name = extracted
    elseif extracted and type(extracted) ~= "table" or (extracted and extracted.type) then
      name = short_text(extracted, bufnr)
    end

    if name ~= "" and not seen[name] then
      seen[name] = true
      local start_row, _, end_row, _ = symbol:range()
      local line_count = (end_row - start_row) + 1
      table.insert(segments, {
        text = name,
        kind = symbol:type(),
        symbol_kind = meta.kind or label,
        label = label,
        icon = meta.icon,
        icon_hl = meta.hl,
        hl = meta.hl,
        lnum = start_row + 1,
        end_lnum = end_row + 1,
        lines = line_count,
        type = "symbol",
      })
    end
  end

  if #segments == 0 then
    return nil
  end

  if nodes[1] and nodes[1]:type():match("_statement") then
    local total_lines = vim.api.nvim_buf_line_count(bufnr)
    table.insert(segments, 1, {
      text = "(root)",
      kind = "root",
      symbol_kind = "Root",
      label = "root",
      icon = "󰅩",
      icon_hl = "Comment",
      hl = "Comment",
      lnum = 1,
      end_lnum = total_lines,
      lines = total_lines,
      type = "symbol",
    })
  end

  return {
    language = language_names[ft] or ft:upper(),
    segments = segments,
    source = "treesitter",
  }
end

M.symbol_label = symbol_label

return M
