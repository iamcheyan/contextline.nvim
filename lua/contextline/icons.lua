local M = {}

-- Standard LSP SymbolKind icons and highlight groups (Codicons / Nerd Font)
M.lsp_kinds = {
  [1] = { kind = "File", label = "file", icon = "󰈙", hl = "Constant" },
  [2] = { kind = "Module", label = "module", icon = "󰏗", hl = "Include" },
  [3] = { kind = "Namespace", label = "namespace", icon = "󰌗", hl = "Include" },
  [4] = { kind = "Package", label = "package", icon = "󰏗", hl = "Include" },
  [5] = { kind = "Class", label = "class", icon = "󰌗", hl = "Type" },
  [6] = { kind = "Method", label = "method", icon = "󰆧", hl = "Function" },
  [7] = { kind = "Property", label = "property", icon = "󰅪", hl = "Identifier" },
  [8] = { kind = "Field", label = "field", icon = "󰅪", hl = "Identifier" },
  [9] = { kind = "Constructor", label = "constructor", icon = "󰆧", hl = "Function" },
  [10] = { kind = "Enum", label = "enum", icon = "󰏿", hl = "Type" },
  [11] = { kind = "Interface", label = "interface", icon = "󰠱", hl = "Type" },
  [12] = { kind = "Function", label = "function", icon = "󰊕", hl = "Function" },
  [13] = { kind = "Variable", label = "variable", icon = "󰀫", hl = "Identifier" },
  [14] = { kind = "Constant", label = "constant", icon = "󰏿", hl = "Constant" },
  [15] = { kind = "String", label = "string", icon = "󰀬", hl = "String" },
  [16] = { kind = "Number", label = "number", icon = "󰎠", hl = "Number" },
  [17] = { kind = "Boolean", label = "boolean", icon = "󰨙", hl = "Boolean" },
  [18] = { kind = "Array", label = "array", icon = "󰅨", hl = "Type" },
  [19] = { kind = "Object", label = "object", icon = "󰅩", hl = "Type" },
  [20] = { kind = "Key", label = "key", icon = "󰌋", hl = "Identifier" },
  [21] = { kind = "Null", label = "null", icon = "󰟢", hl = "Special" },
  [22] = { kind = "EnumMember", label = "enum_member", icon = "󰏿", hl = "Constant" },
  [23] = { kind = "Struct", label = "struct", icon = "󰌗", hl = "Type" },
  [24] = { kind = "Event", label = "event", icon = "󰉁", hl = "Special" },
  [25] = { kind = "Operator", label = "operator", icon = "󰆕", hl = "Operator" },
  [26] = { kind = "TypeParameter", label = "type_param", icon = "󰊄", hl = "Type" },
}

-- Mapping semantic labels / Tree-sitter kinds to icons and highlights
M.symbol_map = {
  class = { icon = "󰌗", hl = "Type" },
  record = { icon = "󰌗", hl = "Type" },
  struct = { icon = "󰌗", hl = "Type" },
  interface = { icon = "󰠱", hl = "Type" },
  trait = { icon = "󰠱", hl = "Type" },
  ["enum"] = { icon = "󰏿", hl = "Type" },
  enum_member = { icon = "󰏿", hl = "Constant" },
  ["type"] = { icon = "󰊄", hl = "Type" },
  namespace = { icon = "󰌗", hl = "Include" },
  package = { icon = "󰏗", hl = "Include" },
  module = { icon = "󰏗", hl = "Include" },
  ["function"] = { icon = "󰊕", hl = "Function" },
  method = { icon = "󰆧", hl = "Function" },
  constructor = { icon = "󰆧", hl = "Function" },
  property = { icon = "󰅪", hl = "Identifier" },
  field = { icon = "󰅪", hl = "Identifier" },
  variable = { icon = "󰀫", hl = "Identifier" },
  constant = { icon = "󰏿", hl = "Constant" },
  element = { icon = "󰅴", hl = "Tag" },
  table = { icon = "", hl = "Type" },
  query = { icon = "󰆼", hl = "Keyword" },
  cte = { icon = "󰆼", hl = "Keyword" },
  key = { icon = "󰌋", hl = "Identifier" },
  mapping = { icon = "󰅩", hl = "Type" },
  heading = { icon = "󰉫", hl = "Title" },
  section = { icon = "󰉫", hl = "Title" },
  impl = { icon = "󰠱", hl = "Type" },
  view = { icon = "󰈈", hl = "Type" },
}

function M.get_symbol_meta(kind_or_label)
  if type(kind_or_label) == "number" then
    return M.lsp_kinds[kind_or_label] or { kind = "Symbol", label = "symbol", icon = "󰘦", hl = "Identifier" }
  end
  local key = tostring(kind_or_label or ""):lower()
  if M.symbol_map[key] then
    return M.symbol_map[key]
  end
  return { icon = "󰘦", hl = "Identifier" }
end

function M.get_file_icon(filename, extension)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local icon, icon_hl = devicons.get_icon(filename, extension, { default = true })
    if icon then
      return icon, icon_hl or "DevIconDefault"
    end
  end
  return "󰈙", "Directory"
end

return M
