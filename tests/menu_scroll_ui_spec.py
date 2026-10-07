import time
from pathlib import Path

import pynvim

root = str(Path(__file__).resolve().parents[1])
n = pynvim.attach('child', argv=['nvim', '--embed', '--headless', '-u', 'NONE'])
try:
    n.ui_attach(100, 30, rgb=True, ext_linegrid=True)
    n.exec_lua('''
      vim.opt.rtp:prepend(...)
      vim.o.mouse = 'a'
      vim.bo.filetype = 'cobol'
      local lines = {'       DATA DIVISION.', '       WORKING-STORAGE SECTION.'}
      for i=1,60 do lines[#lines+1] = string.format('       01 FIELD-%02d PIC X.', i) end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      require('contextline').setup({use_lsp=false,show_diagnostics=false})
      _G.original_guicursor = vim.o.guicursor
      _G.source_win = vim.api.nvim_get_current_win()
      require('contextline.menu').open({winid=source_win,segment_index=1,col=2})
      vim.cmd('redraw')
    ''', root)

    state = n.exec_lua('''
      local m=require('contextline.menu')
      return {win=m.active_win, position=vim.api.nvim_win_get_position(m.active_win),
        view=vim.api.nvim_win_call(m.active_win,vim.fn.winsaveview),
        source=vim.fn.winsaveview(), cursor=vim.api.nvim_win_get_cursor(source_win)}
    ''')
    assert n.exec_lua('return vim.o.guicursor') == 'a:ContextlineHiddenCursor-blinkon0', 'popup should hide the underlying cursor'
    popup_row, popup_col = state['position']
    n.api.input_mouse('wheel', 'down', '', 0, popup_row + 2, popup_col + 4)
    time.sleep(0.05)
    n.command('redraw')

    scrolled = n.exec_lua('''
      local m=require('contextline.menu')
      return {active=m.active_win ~= nil,
        view=vim.api.nvim_win_call(m.active_win,vim.fn.winsaveview),
        cursor=vim.api.nvim_win_get_cursor(m.active_win)[1],
        height=vim.api.nvim_win_get_height(m.active_win),
        count=vim.api.nvim_buf_line_count(m.active_buf),
        source=vim.fn.winsaveview(), source_cursor=vim.api.nvim_win_get_cursor(source_win)}
    ''')
    assert scrolled['active'], 'wheel closed the menu'
    assert scrolled['cursor'] == state['view']['lnum'] + 1, f'wheel did not move the highlighted entry: {state} -> {scrolled}'
    assert scrolled['source'] == state['source'], 'wheel scrolled the source buffer'
    assert scrolled['source_cursor'] == state['cursor'], 'wheel moved the source cursor'
    assert scrolled['view']['topline'] <= max(1, scrolled['count'] - scrolled['height'] + 1), 'menu scrolled past its final rows'
    assert scrolled['view']['topline'] <= scrolled['cursor'] < scrolled['view']['topline'] + scrolled['height'], 'highlighted row left the visible menu viewport'
    n.api.input_mouse('move', '', '', 0, popup_row + 3, popup_col + 4)
    time.sleep(0.05)
    hover_row = n.exec_lua('return vim.api.nvim_win_get_cursor(require("contextline.menu").active_win)[1]')
    assert hover_row == n.exec_lua('return vim.fn.getmousepos().line'), 'hover should select the row under the pointer'
    n.input('<Down>')
    time.sleep(0.05)
    assert n.exec_lua('return vim.api.nvim_win_get_cursor(require("contextline.menu").active_win)[1]') == hover_row + 1
    n.input('<Up>')
    time.sleep(0.05)
    assert n.exec_lua('return vim.api.nvim_win_get_cursor(require("contextline.menu").active_win)[1]') == hover_row
    n.exec_lua('''
      require('contextline.menu').close()
      assert(vim.o.guicursor == original_guicursor, 'closing must restore the original cursor')
      vim.api.nvim_buf_set_lines(0,0,-1,false,{
        '       DATA DIVISION.', '       WORKING-STORAGE SECTION.',
        '       01 FIELD-ONE PIC X.', '       01 FIELD-TWO PIC X.'})
      vim.api.nvim_win_set_cursor(source_win,{1,0})
      vim.cmd('redraw')
    ''')
    n.exec_lua('''
      require('contextline.menu').open({winid=source_win,col=2})
      vim.cmd('redraw')
    ''')
    row, col = n.exec_lua('return vim.api.nvim_win_get_position(require("contextline.menu").active_win)')
    n.api.input_mouse('wheel','down','',0,row+2,col+4)
    time.sleep(0.05)
    n.command('redraw')
    assert n.exec_lua('return vim.api.nvim_win_get_cursor(require("contextline.menu").active_win)[1]') == 2, 'short menu ignored wheel navigation'
    assert n.exec_lua('return vim.api.nvim_win_get_cursor(source_win)[1]') == 1, 'short menu wheel moved source cursor'
    assert n.exec_lua('return vim.o.guicursor') == 'a:ContextlineHiddenCursor-blinkon0', 'wheel must not restore the blinking cursor'
    print('menu_scroll_ui_spec: OK (short and overflowing menus)')
finally:
    try:
        n.command('qa!')
    except (EOFError, OSError):
        pass
