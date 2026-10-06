local M = {}
local icons = require("contextline.icons")
local treesitter = require("contextline.treesitter")

-- Active popup state
M.active_win = nil
M.active_buf = nil
M._source_mappings = nil
M._autocmd_group = nil

local function map_flag(value)
  return value == true or value == 1
end

local function install_source_mappings(bufnr, handlers)
  local saved = {}
  for lhs, callback in pairs(handlers) do
    saved[lhs] = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if mapping.lhs == lhs then
        table.insert(saved[lhs], mapping)
      end
    end
    vim.keymap.set("n", lhs, callback, {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = "Contextline menu navigation",
    })
  end
  M._source_mappings = { bufnr = bufnr, saved = saved }
end

local function restore_source_mappings()
  local state = M._source_mappings
  M._source_mappings = nil
  if not state or not vim.api.nvim_buf_is_valid(state.bufnr) then return end

  for lhs, mappings in pairs(state.saved) do
    pcall(vim.keymap.del, "n", lhs, { buffer = state.bufnr })
    for _, mapping in ipairs(mappings) do
      local rhs = mapping.callback or mapping.rhs
      if rhs ~= nil then
        pcall(vim.keymap.set, "n", mapping.lhs or lhs, rhs, {
          buffer = state.bufnr,
          expr = map_flag(mapping.expr),
          nowait = map_flag(mapping.nowait),
          silent = map_flag(mapping.silent),
          remap = not map_flag(mapping.noremap),
          desc = mapping.desc,
        })
      end
    end
  end
end

local function short_text(node, bufnr)
  if not node then return "" end
  local text = vim.treesitter.get_node_text(node, bufnr):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #text > 45 then
    text = text:sub(1, 42) .. "..."
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

local function collect_cobol(bufnr)
  local items = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, raw_line in ipairs(lines) do
    local line = raw_line:gsub("^%d%d%d%d%d%d[ %*]", ""):gsub("%*>.*$", "")
    local upper = line:upper():gsub("^%s+", "")
    if upper:match("^[A-Z0-9%-]+%s+DIVISION") then
      local div = upper:match("^[A-Z0-9%-]+%s+DIVISION")
      table.insert(items, { name = div, label = "module", icon = "󰌗", icon_hl = "Include", lnum = lnum, depth = 0 })
    elseif upper:match("^[A-Z0-9%-]+%s+SECTION") then
      local sec = upper:match("^[A-Z0-9%-]+%s+SECTION")
      table.insert(items, { name = sec, label = "package", icon = "󰏗", icon_hl = "Type", lnum = lnum, depth = 1 })
    elseif upper:match("^01%s+([A-Z0-9%-]+)") then
      local data = upper:match("^01%s+([A-Z0-9%-]+)")
      table.insert(items, { name = "01 " .. data, label = "field", icon = "󰅪", icon_hl = "Identifier", lnum = lnum, depth = 2 })
    elseif upper:match("^(%d%d%d%d%-[A-Z0-9%-]+)") then
      local para = upper:match("^(%d%d%d%d%-[A-Z0-9%-]+)")
      table.insert(items, { name = para, label = "function", icon = "󰅪", icon_hl = "Function", lnum = lnum, depth = 2 })
    end
  end
  return items
end

local function collect_batch(bufnr)
  local items = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for lnum, line in ipairs(lines) do
    local label = line:match("^%s*(:[%w%-_]+)")
    if label then
      table.insert(items, { name = label, label = "function", icon = "󰊕", icon_hl = "Function", lnum = lnum, depth = 0 })
    end
  end
  return items
end

local ts_symbols = {
  class_definition = true,
  class_declaration = true,
  function_definition = true,
  function_declaration = true,
  async_function_definition = true,
  method_definition = true,
  method_declaration = true,
  interface_declaration = true,
  type_alias_declaration = true,
  type_alias_statement = true,
  enum_declaration = true,
  enum_assignment = true,
  struct_item = true,
  enum_item = true,
  trait_item = true,
  impl_item = true,
  constructor_declaration = true,
  public_field_definition = true,
  property_signature = true,
  field_declaration = true,
  while_statement = true,
  for_statement = true,
  case_statement = true,
}

local function collect_ts(node, bufnr, depth, items)
  for child in node:iter_children() do
    local ctype = child:type()
    if ctype == "export_statement" or ctype == "decorated_definition" or ctype == "redirected_statement" then
      collect_ts(child, bufnr, depth, items)
    elseif ts_symbols[ctype] then
      local name = ""
      local name_node = child:field("name")[1] or child:field("declarator")[1]
      if name_node then
        name = short_text(name_node, bufnr)
      elseif ctype == "while_statement" then
        local cond = child:field("condition")[1]
        name = "while " .. (cond and short_text(cond, bufnr) or "")
      elseif ctype == "for_statement" then
        local var = child:field("variable")[1]
        name = "for " .. (var and short_text(var, bufnr) or "")
      elseif ctype == "case_statement" then
        local val = child:field("value")[1]
        name = "case " .. (val and short_text(val, bufnr) or "")
      end

      if name ~= "" then
        local label = treesitter.symbol_label(child)
        local meta = icons.get_symbol_meta(label)
        local srow, _, erow, _ = child:range()
        table.insert(items, {
          name = name,
          kind = ctype,
          label = label,
          icon = meta.icon,
          icon_hl = meta.hl,
          lnum = srow + 1,
          end_lnum = erow + 1,
          depth = depth,
        })
        local body = child:field("body")[1] or first_descendant(child, "block") or first_descendant(child, "class_body") or first_descendant(child, "declaration_list")
        if body then
          collect_ts(body, bufnr, depth + 1, items)
        end
      end
    end
  end
end

function M.get_symbols(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype

  if ft == "cobol" or ft == "cbl" or ft == "cob" then
    return collect_cobol(bufnr)
  end
  if ft == "dosbatch" or ft == "batch" then
    return collect_batch(bufnr)
  end

  local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if parser_ok and parser then
    local tree = parser:parse()[1]
    if tree then
      local items = {}
      collect_ts(tree:root(), bufnr, 0, items)
      if #items > 0 then
        return items
      end
    end
  end

  return {}
end

---Filter items based on clicked segment index and current cursor row
local function filter_by_segment(all_items, cur_row, segment_index, info)
  if not info or not info.segments or #info.segments <= 1 or not segment_index or segment_index <= 1 then
    return all_items, " 󰅩 Code Hierarchy "
  end

  local total_segs = #info.segments
  local clicked_seg = info.segments[segment_index]
  if not clicked_seg then
    return all_items, " 󰅩 Code Hierarchy "
  end

  -- Find the active item in all_items corresponding to cur_row
  local active_item = nil
  local active_idx = nil
  for i, it in ipairs(all_items) do
    if it.lnum <= cur_row and (not it.end_lnum or it.end_lnum >= cur_row) then
      active_item = it
      active_idx = i
    end
  end

  -- 1. If clicked the leaf segment (e.g. method or property):
  -- Show only the direct siblings inside the enclosing parent container
  if segment_index == total_segs and active_item then
    local parent_item = nil
    local parent_idx = nil
    if (active_item.depth or 0) > 0 then
      for i = (active_idx or 1) - 1, 1, -1 do
        if (all_items[i].depth or 0) == (active_item.depth or 0) - 1 then
          parent_item = all_items[i]
          parent_idx = i
          break
        end
      end
    end

    if parent_item and parent_idx then
      local siblings = {}
      for i = parent_idx + 1, #all_items do
        local it = all_items[i]
        if (it.depth or 0) < (active_item.depth or 0) then
          break
        end
        if (it.depth or 0) == (active_item.depth or 0) then
          local cloned = vim.deepcopy(it)
          cloned.depth = 0
          table.insert(siblings, cloned)
        end
      end
      if #siblings > 0 then
        return siblings, string.format(" %s %s ", parent_item.icon or "󰅩", parent_item.name)
      end
    end
  end

  -- 2. If clicked an intermediate container segment:
  -- Find the item matching clicked_seg.text
  local target_depth = 0
  for _, it in ipairs(all_items) do
    if it.name:find(clicked_seg.text, 1, true) or clicked_seg.text:find(it.name, 1, true) then
      target_depth = it.depth or 0
      break
    end
  end

  local filtered = {}
  for _, it in ipairs(all_items) do
    local d = it.depth or 0
    if d == target_depth then
      local cloned = vim.deepcopy(it)
      cloned.depth = 0
      table.insert(filtered, cloned)
    elseif d == target_depth + 1 then
      local cloned = vim.deepcopy(it)
      cloned.depth = 1
      table.insert(filtered, cloned)
    end
  end

  if #filtered > 0 then
    return filtered, string.format(" %s %s ", clicked_seg.icon or "󰅩", clicked_seg.text or "Outline")
  end

  return all_items, " 󰅩 Code Hierarchy "
end

local function refresh_winbar()
  -- Heirline caches winbar components until CursorMoved/BufEnter. A winbar
  -- click fires neither, so the chip would stay stale until the second click
  -- unless we drop that cache ourselves.
  pcall(function()
    local heirline = require("heirline")
    if heirline.winbar and heirline.winbar.broadcast then
      heirline.winbar:broadcast(function(self)
        self._win_cache = nil
      end)
    end
  end)
  pcall(vim.cmd, "redrawstatus")
end

function M.close()
  if M._autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, M._autocmd_group)
    M._autocmd_group = nil
  end
  restore_source_mappings()
  local cl_ok, cl = pcall(require, "contextline")
  if cl_ok then
    cl._active_menu_segment = nil
    cl._active_menu_win = nil
    refresh_winbar()
  end
  if M.active_win and vim.api.nvim_win_is_valid(M.active_win) then
    vim.api.nvim_win_close(M.active_win, true)
  end
  M.active_win = nil
  M.active_buf = nil
end

local ACTIVE_HL = "ContextlineActiveMenu"

local function eval_winbar(src_win, str)
  return vim.api.nvim_eval_statusline(str, {
    winid = src_win,
    use_winbar = true,
    highlights = true,
  })
end

local function highlight_display_col(ev, hl_name)
  if not ev or not ev.highlights then
    return nil
  end
  for _, h in ipairs(ev.highlights) do
    local groups = h.groups or { h.group }
    for _, g in ipairs(groups) do
      if g == hl_name then
        return vim.fn.strdisplaywidth(ev.str:sub(1, h.start))
      end
    end
  end
  return nil
end

---Window-relative 0-based column of the active winbar chip (flush left).
function M.win_col_for_segment(src_win)
  src_win = src_win or vim.api.nvim_get_current_win()
  local cl = require("contextline")

  local winbar = vim.wo[src_win].winbar
  if winbar == nil or winbar == "" then
    winbar = vim.o.winbar
  end

  if winbar ~= "" then
    local col = highlight_display_col(eval_winbar(src_win, winbar), ACTIVE_HL)
    if col then
      return col
    end
  end

  local cl_ev = eval_winbar(src_win, cl.get({ winid = src_win }))
  local inner = highlight_display_col(cl_ev, ACTIVE_HL) or 0
  if winbar == "" then
    return inner
  end

  -- Heirline (and similar) may pad before the contextline component. Measure
  -- that prefix against the inactive rendering so the extra chip spaces do
  -- not break the substring search.
  local saved_seg = cl._active_menu_segment
  local saved_win = cl._active_menu_win
  cl._active_menu_segment = nil
  cl._active_menu_win = nil
  local plain = vim.api.nvim_eval_statusline(cl.get({ winid = src_win }), {
    winid = src_win,
    use_winbar = true,
  }).str
  local full = vim.api.nvim_eval_statusline(winbar, {
    winid = src_win,
    use_winbar = true,
  }).str
  cl._active_menu_segment = saved_seg
  cl._active_menu_win = saved_win

  local p = vim.fn.stridx(full, plain)
  local prefix = 0
  if p > 0 then
    prefix = vim.fn.strdisplaywidth(full:sub(1, p))
  end
  return prefix + inner
end

function M.open(opts)
  opts = opts or {}
  local src_win = opts.winid or vim.api.nvim_get_current_win()
  local src_buf = opts.bufnr or vim.api.nvim_win_get_buf(src_win)

  -- Close existing
  M.close()

  local cl = require("contextline")
  if opts.segment_index then
    cl._active_menu_segment = opts.segment_index
    cl._active_menu_win = src_win
    refresh_winbar()
  end

  local all_items = M.get_symbols(src_buf)
  if #all_items == 0 then
    vim.notify("Contextline: No outline symbols found in current file", vim.log.levels.INFO)
    return
  end

  local cl = require("contextline")
  local info = cl.get_info({ bufnr = src_buf, winid = src_win })
  local cur_row = vim.api.nvim_win_get_cursor(src_win)[1]

  local items, menu_title = filter_by_segment(all_items, cur_row, opts.segment_index, info)

  -- Determine active item closest to cursor row
  local active_idx = 1
  for i, item in ipairs(items) do
    if item.lnum <= cur_row then
      active_idx = i
      if item.end_lnum and cur_row <= item.end_lnum then
        active_idx = i
      end
    end
  end

  -- Standalone users retain their theme; the dotfiles adapter supplies Fresh.
  for name, fallback in pairs({ FreshMenu = "Pmenu", FreshMenuSelected = "PmenuSel",
    FreshMenuBorder = "Pmenu", FreshMenuMuted = "Comment" }) do
    vim.api.nvim_set_hl(0, name, { default = true, link = fallback })
  end

  -- Format display lines (with 1 space left padding for borderless dropdown)
  local display_lines = {}
  local highlights = {}
  local max_len = 25
  for i, item in ipairs(items) do
    local indent = string.rep("  ", item.depth or 0)
    local line_str = string.format(" %s%s %s", indent, item.icon or "󰘦", item.name)
    local lnum_str = string.format(":%d", item.lnum)
    table.insert(display_lines, line_str)
    local visual = vim.fn.strdisplaywidth(line_str) + vim.fn.strdisplaywidth(lnum_str)
    if visual > max_len then
      max_len = visual
    end


  end

  -- Pad right side with line numbers
  local final_lines = {}
  for i, text in ipairs(display_lines) do
    local pad = string.rep(" ", math.max(2, max_len - vim.fn.strdisplaywidth(text) + 2))
    local lnum_str = string.format(":%d", items[i].lnum)
    local full_line = text .. pad .. lnum_str .. " "
    table.insert(final_lines, full_line)

    -- Highlight line number with Comment
    local lnum_start = #text + #pad
    local lnum_end = lnum_start + #lnum_str
    table.insert(highlights, {
      hl_group = "FreshMenuMuted",
      line = i - 1,
      col_start = lnum_start,
      col_end = lnum_end,
    })
  end

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, final_lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "contextline_menu"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  -- Apply syntax highlights
  local ns = vim.api.nvim_create_namespace("contextline_menu")
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, h.hl_group, h.line, h.col_start, h.col_end)
  end

  local col_offset = opts.col
  if not col_offset then
    col_offset = M.win_col_for_segment(src_win)
  end

  local wininfo = vim.fn.getwininfo(src_win)[1]
  local screen_left = col_offset
  if wininfo then
    screen_left = (wininfo.wincol - 1) + col_offset
  end
  local win_width = math.min(max_len + 4, vim.o.columns - 4)
  if screen_left + win_width > vim.o.columns - 2 then
    win_width = math.max(8, vim.o.columns - 2 - screen_left)
  end
  local win_height = math.min(#final_lines, math.floor(vim.o.lines * 0.55))

  -- row = 0 attaches the floating window directly to the bottom of the winbar with 0 gap
  -- Leave focus in the source window.  Focusing the unlisted popup buffer
  -- makes Neovim mark the source winbar inactive and changes BufferLine's
  -- selected tab while the user is only opening the hierarchy menu.
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = src_win,
    row = 0,
    col = col_offset,
    width = win_width,
    height = win_height,
    style = "minimal",
    border = "single",
    zindex = 250,
  })

  vim.wo[win].cursorline = true
  vim.wo[win].cursorcolumn = false
  vim.wo[win].winbar = ""
  vim.wo[win].scrolloff = 0
  vim.wo[win].sidescrolloff = 0
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = "NormalFloat:FreshMenu,FloatBorder:FreshMenuBorder,CursorLine:FreshMenuSelected"

  -- Set initial cursor on current active symbol
  local buf_lines = vim.api.nvim_buf_line_count(buf)
  local valid_active_idx = math.max(1, math.min(active_idx, buf_lines))
  pcall(vim.api.nvim_win_set_cursor, win, { valid_active_idx, 0 })

  M.active_win = win
  M.active_buf = buf

  -- Keymaps for selection and exit
  local function jump()
    local ok, cur = pcall(vim.api.nvim_win_get_cursor, win)
    local row = (ok and cur) and cur[1] or 1
    local target = items[row]
    M.close()
    if target and target.lnum and vim.api.nvim_win_is_valid(src_win) then
      vim.api.nvim_set_current_win(src_win)
      local total_src_lines = vim.api.nvim_buf_line_count(src_buf)
      local clamped_lnum = math.max(1, math.min(target.lnum, total_src_lines))
      pcall(vim.api.nvim_win_set_cursor, src_win, { clamped_lnum, 0 })
      vim.cmd("normal! zz")
    end
  end

  local kmopts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", jump, kmopts)
  vim.keymap.set("n", "<Space>", jump, kmopts)
  local function mouse_select()
    local mouse_pos = vim.fn.getmousepos()
    if mouse_pos and mouse_pos.winid == win then
      if mouse_pos.line >= 1 and mouse_pos.line <= #final_lines then
        pcall(vim.api.nvim_win_set_cursor, win, { mouse_pos.line, 0 })
        jump()
      end
    else
      M.close()
      -- Replay the click after restoring the user's mappings so the editor,
      -- tabs, and other windows still receive their normal mouse action.
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true), "m", false)
    end
  end

  local function mouse_scroll(delta, key)
    local mouse_pos = vim.fn.getmousepos()
    local popup_pos = vim.api.nvim_win_get_position(win)
    local popup_row, popup_col = popup_pos[1], popup_pos[2]
    local inside_popup = mouse_pos and mouse_pos.screenrow >= popup_row + 1
      and mouse_pos.screenrow <= popup_row + win_height
      and mouse_pos.screencol >= popup_col + 1
      and mouse_pos.screencol <= popup_col + win_width

    if inside_popup then
      -- A wheel event over a fully visible menu should not scroll the source
      -- buffer behind it. Move the popup viewport only when rows overflow.
      if #final_lines <= win_height then return end

      local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
      local max_topline = math.max(1, #final_lines - win_height + 1)
      local topline = math.max(1, math.min(max_topline, view.topline + delta * 3))
      view.topline = topline
      view.topfill = 0
      vim.api.nvim_win_call(win, function() vim.fn.winrestview(view) end)

      -- Keep the highlighted menu selection visible after moving its viewport.
      local cursor = vim.api.nvim_win_get_cursor(win)
      local last_visible = math.min(#final_lines, topline + win_height - 1)
      local row = math.max(topline, math.min(last_visible, cursor[1]))
      if row ~= cursor[1] then
        pcall(vim.api.nvim_win_set_cursor, win, { row, 0 })
      end
      return
    end

    -- The source buffer owns focus while the popup is open, so replay wheel
    -- events outside the popup after removing our temporary mapping.
    M.close()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "m", false)
  end

  vim.keymap.set("n", "<LeftMouse>", mouse_select, kmopts)
  vim.keymap.set("n", "<ScrollWheelUp>", function() mouse_scroll(-1, "<ScrollWheelUp>") end, kmopts)
  vim.keymap.set("n", "<ScrollWheelDown>", function() mouse_scroll(1, "<ScrollWheelDown>") end, kmopts)
  vim.keymap.set("n", "q", M.close, kmopts)
  vim.keymap.set("n", "<Esc>", M.close, kmopts)

  -- The popup does not take focus, so forward the usual menu keys from the
  -- source buffer to its cursor until the user chooses a row or closes it.
  local function move_selection(delta)
    if not M.active_win or not vim.api.nvim_win_is_valid(M.active_win) then return end
    local row = vim.api.nvim_win_get_cursor(M.active_win)[1]
    local count = vim.api.nvim_buf_line_count(M.active_buf)
    row = math.max(1, math.min(count, row + delta))
    pcall(vim.api.nvim_win_set_cursor, M.active_win, { row, 0 })
  end

  install_source_mappings(src_buf, {
    ["<Up>"] = function() move_selection(-1) end,
    ["k"] = function() move_selection(-1) end,
    ["<Down>"] = function() move_selection(1) end,
    ["j"] = function() move_selection(1) end,
    ["<CR>"] = jump,
    ["<Space>"] = jump,
    ["q"] = M.close,
    ["<Esc>"] = M.close,
    ["<LeftMouse>"] = mouse_select,
    ["<ScrollWheelUp>"] = function() mouse_scroll(-1, "<ScrollWheelUp>") end,
    ["<ScrollWheelDown>"] = function() mouse_scroll(1, "<ScrollWheelDown>") end,
  })

  -- The source keeps focus, so lifecycle events must watch that source,
  -- rather than a popup that was never entered. Remove them on every close.
  M._autocmd_group = vim.api.nvim_create_augroup("ContextlineMenuLifetime", { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "InsertEnter", "CursorMoved" }, {
    group = M._autocmd_group,
    buffer = src_buf,
    callback = M.close,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = M._autocmd_group,
    pattern = tostring(win),
    callback = M.close,
  })
end

function M.toggle(opts)
  if M.active_win and vim.api.nvim_win_is_valid(M.active_win) then
    M.close()
  else
    M.open(opts)
  end
end

return M
