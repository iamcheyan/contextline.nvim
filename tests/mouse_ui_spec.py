from pathlib import Path
import time
import pynvim

root = str(Path(__file__).resolve().parents[1])
n = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE'])
try:
    n.ui_attach(100, 30, rgb=True, ext_linegrid=True)
    n.exec_lua('''
      vim.opt.rtp:prepend(...)
      vim.o.mouse = 'a'
      vim.o.showtabline = 0
      vim.o.winbar = "%{%v:lua.require'contextline'.get({fixed_palette=true})%}"
      vim.bo.filetype = 'cobol'
      vim.api.nvim_buf_set_lines(0,0,-1,false,{
        '       IDENTIFICATION DIVISION.',
        '       PROGRAM-ID. TEST.',
        '       DATA DIVISION.',
        '       WORKING-STORAGE SECTION.',
        '       01 VALUE-ONE PIC X.',
        '       PROCEDURE DIVISION.',
        '       1000-MAIN.',
        '           DISPLAY VALUE-ONE.',
      })
      require('contextline').setup({use_lsp=false,show_diagnostics=false})
      _G.source_win = vim.api.nvim_get_current_win()
      require('contextline.menu').open({winid=source_win,segment_index=1,col=2})
      vim.cmd('redraw')
    ''', root)
    popup_row, popup_col = n.exec_lua('return vim.api.nvim_win_get_position(require("contextline.menu").active_win)')
    popup_cursor = n.exec_lua('return vim.api.nvim_win_get_cursor(require("contextline.menu").active_win)')
    source_view = n.exec_lua('return vim.fn.winsaveview()')
    n.api.input_mouse('wheel', 'down', '', 0, popup_row + 1, popup_col + 4)
    time.sleep(0.05)
    n.command('redraw')
    assert n.exec_lua('return require("contextline.menu").active_win ~= nil'), 'wheel over a fitting menu closed it'
    assert n.exec_lua('return vim.api.nvim_win_get_cursor(require("contextline.menu").active_win)') == [min(popup_cursor[0] + 1, 6), 0], 'wheel did not move selection in a fitting menu'
    assert n.exec_lua('return vim.fn.winsaveview()') == source_view, 'wheel over a fitting menu scrolled the source buffer'
    n.exec_lua('''
      local lines = {'       DATA DIVISION.', '       WORKING-STORAGE SECTION.'}
      for i=1,30 do lines[#lines+1] = string.format('       01 FIELD-%02d PIC X.', i) end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.cmd('redraw')
    ''')
    overflow = n.exec_lua('''
      require('contextline.menu').open({winid=source_win,segment_index=1,col=2})
      local m=require('contextline.menu')
      return {active=m.active_win or false,position=vim.api.nvim_win_get_position(m.active_win),valid=vim.api.nvim_win_is_valid(m.active_win),view=vim.api.nvim_win_call(m.active_win,vim.fn.winsaveview)}
    ''')
    assert overflow['active'], f'could not open overflowing outline menu: {overflow}'
    popup_row, popup_col = overflow['position']
    popup_view = overflow['view']
    source_cursor = n.exec_lua('return vim.api.nvim_win_get_cursor(source_win)')
    n.api.input_mouse('wheel', 'down', '', 0, popup_row + 1, popup_col + 4)
    time.sleep(0.05)
    n.command('redraw')
    scrolled_view = n.exec_lua('local m=require("contextline.menu"); return vim.api.nvim_win_call(m.active_win,vim.fn.winsaveview)')
    assert scrolled_view['lnum'] == popup_view['lnum'] + 1, f'wheel did not move the menu selection: before={popup_view}, after={scrolled_view}'
    assert n.exec_lua('return vim.api.nvim_win_get_cursor(source_win)') == source_cursor, 'scrolling menu moved the source cursor'
    assert n.exec_lua('local m=require("contextline.menu"); return vim.wo[m.active_win].winhighlight') == 'NormalFloat:FreshMenu,FloatBorder:FreshMenuBorder,CursorLine:FreshMenuSelected', 'scrolling changed menu colors'
    n.exec_lua('''
      require('contextline.menu').close()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        '       IDENTIFICATION DIVISION.', '       PROGRAM-ID. TEST.',
        '       DATA DIVISION.', '       WORKING-STORAGE SECTION.',
        '       01 VALUE-ONE PIC X.', '       PROCEDURE DIVISION.',
        '       1000-MAIN.', '           DISPLAY VALUE-ONE.',
      })
      vim.cmd('redraw')
    ''')
    n.exec_lua('require("contextline.menu").open({winid=source_win,segment_index=1,col=2}); vim.cmd("redraw")')
    n.api.input_mouse('left', 'press', '', 0, 20, 70)
    time.sleep(0.05)
    n.command('redraw')
    state = n.exec_lua('return {active=require("contextline.menu").active_win or false,current=vim.api.nvim_get_current_win(),source=source_win}')
    assert state['active'] is False, f'outside click left menu open: {state}'
    assert state['current'] == state['source'], f'outside click changed source focus: {state}'
    # Clicking the same cursor cell must dismiss too; no CursorMoved event
    # occurs, so this exercises the mouse handler rather than lifecycle hooks.
    n.exec_lua('require("contextline.menu").open({winid=source_win,segment_index=1,col=2}); vim.cmd("redraw")')
    pos = n.exec_lua('local c=vim.api.nvim_win_get_cursor(source_win); return vim.fn.screenpos(source_win,c[1],c[2]+1)')
    n.api.input_mouse('left', 'press', '', 0, pos['row'] - 1, pos['col'] - 1)
    time.sleep(0.05)
    n.command('redraw')
    assert n.exec_lua('return require("contextline.menu").active_win == nil'), 'same-cell outside click left menu open'
    n.exec_lua('require("contextline.menu").open({winid=source_win,segment_index=1,col=2}); vim.cmd("redraw")')
    row, col = n.exec_lua('return vim.api.nvim_win_get_position(require("contextline.menu").active_win)')
    displayed = n.exec_lua('local m=require("contextline.menu"); return {view=vim.api.nvim_win_call(m.active_win,vim.fn.winsaveview),lines=vim.api.nvim_buf_get_lines(m.active_buf,0,-1,false)}')
    n.api.input_mouse('left', 'press', '', 0, row + 1, col + 8)
    time.sleep(0.05)
    n.command('redraw')
    state = n.exec_lua('return {active=require("contextline.menu").active_win or false,current=vim.api.nvim_get_current_win(),source=source_win}')
    assert state['active'] is False, f'menu click did not choose row: {state}'
    assert state['current'] == state['source'], f'menu click stole source focus: {state}'
    cursor = n.exec_lua('return vim.api.nvim_win_get_cursor(source_win)')
    assert cursor[0] == 3, f'menu click did not jump to DATA DIVISION: cursor={cursor}, popup_position={(row, col)}, displayed={displayed}'
    n.exec_lua('vim.cmd("vsplit"); _G.other_win=vim.api.nvim_get_current_win(); vim.api.nvim_set_current_win(source_win); require("contextline.menu").open({winid=source_win,segment_index=1,col=2}); vim.cmd("redraw")')
    row, col = n.exec_lua('return vim.api.nvim_win_get_position(other_win)')
    n.api.input_mouse('left', 'press', '', 0, row + 15, col + 5)
    time.sleep(0.05)
    n.command('redraw')
    assert n.exec_lua('return require("contextline.menu").active_win == nil'), 'other-window click left menu open'
    assert n.exec_lua('return vim.api.nvim_get_current_win() == other_win'), 'outside click was not forwarded to the other window'
    print('mouse_ui_spec: OK (outside click, same-cell click, selection, window focus)')
finally:
    try:
        n.command('qa!')
    except (EOFError, OSError):
        pass
