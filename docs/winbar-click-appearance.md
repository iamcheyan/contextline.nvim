# 点击面包屑时保持顶栏外观

本文记录 Neovim 顶部 Contextline 面包屑的点击行为、这次颜色问题的原因和修复方式，供以后调整顶栏或弹出菜单时参考。

## 预期行为

平时顶栏使用当前主题的 `WinBar` 前景色和背景色。点击一个面包屑后：

- 顶栏仍保持原来的颜色和文字位置。
- BufferLine 标签仍保持原来的选中标签。
- 面包屑保持原色，只有弹出菜单中的选中行使用选中背景。
- 菜单仍可以用鼠标或键盘选择；关闭后，源缓冲区原有的按键映射恢复。

这些颜色来自 Neovim 的语义高亮组，不在 Contextline 里写死十六进制色值。

## 问题是怎么发生的

点击事件从 Heirline 的 Contextline 段进入全局回调 `_G.contextline_click`，再调用 `contextline.menu.open()`。旧实现用：

```lua
vim.api.nvim_open_win(buf, true, { ... })
```

第二个参数 `true` 会立即把焦点交给菜单浮窗。菜单使用未列入 BufferLine 的临时缓冲区，因此一次点击同时改变了两个状态：

1. 源编辑窗口失去焦点，Neovim 将它的基础高亮从 `WinBar` 切到 `WinBarNC`。这会让浅蓝顶栏变暗。
2. 当前缓冲区变成菜单缓冲区。BufferLine 找不到对应标签后，会把另一个可见缓冲区显示成选中项。

此外，Contextline 的普通文本曾从 `TabLineSel` 取前景色和背景色。`TabLineSel` 表示“当前选中的标签”，并不保证适合 `WinBar`。蓝色主题里它是深蓝底配黄色字；将它套到浅蓝顶栏上，就造成黄字、深色块和顶栏背景混在一起。

点击段原先还额外添加了左右空格。即使高亮组使用相同颜色，打开菜单时文字也会移动一格，容易看起来像整条顶栏发生了变化。

## 当前实现

### 1. 面包屑使用 WinBar 的主题颜色

`lua/contextline/init.lua` 的 `ensure_highlights()` 将 `ContextlineText` 和 `ContextlineActiveMenu` 链接到 `WinBar`，不复制 RGB 数值。警告提示单独读取 `DiagnosticWarn`，缺少时回退到 `WarningMsg`；不设置背景，让它继承顶栏表面。

复制颜色会产生首次进入时的竞态：Heirline 已缓存旧文字颜色，UI adapter 随后更新了 `WinBar` 背景，最终显示成浅蓝空格夹着深蓝底黄色文字。高亮链接能立即跟随新的 `WinBar`，公开配置的 `config.ui_highlights.apply()` 还会在 `WinBar`/`WinBarNC` 更新后清除 Heirline 的颜色和组件缓存，并主动重绘。

`fixed_palette = true` 时，普通图标、文字、分隔符等统一映射到 `ContextlineText`，警告和错误提示映射到 `ContextlineAlert`。Heirline 的 Contextline 段启用了这个选项，所以 COBOL/Treesitter 原有的语义颜色不会把面包屑变成多色。

点击中的段使用 `ContextlineActiveMenu` 作为菜单定位标记，但它的前景色和背景色与 `ContextlineText` 相同，因此打开菜单不会让顶栏芯片闪成另一种蓝色。真正的菜单当前行在浮窗中使用 `PmenuSel`。

### 2. 菜单打开时不切换源窗口焦点

`lua/contextline/menu.lua` 以 `enter = false` 创建浮窗。这样菜单打开后，源窗口仍是当前窗口，源缓冲区仍是当前缓冲区，因此基础组继续使用 `WinBar`，BufferLine 的当前标签也不会变化。

为了保留键盘操作，插件会在菜单打开期间临时把 `<Up>`/`k`、`<Down>`/`j`、`<CR>`/`<Space>`、`q`/`<Esc>` 映射到菜单操作。关闭菜单时会先移除这些临时映射，再恢复源缓冲区原来的映射。

鼠标事件也必须从源缓冲区处理：`<LeftMouse>` 点击浮窗时直接选择条目；点击外部时关闭菜单、恢复原映射，再重放点击，让编辑器或标签正常响应。否则鼠标默认行为会先把焦点切到菜单，源顶栏变成 `WinBarNC`，标签也失去选中状态。

滚轮事件同样由源缓冲区临时接管，并按鼠标位置转给浮窗。菜单条目数不超过浮窗高度时，滚轮在菜单上不执行滚动，避免把底层源码滚走或让菜单内容偏移并留下空白；条目超出可视高度时，滚轮才移动菜单视口，并让选中行留在可视范围内。滚轮落在菜单外时关闭菜单并重放事件，保留编辑区原有滚动行为。

关闭事件绑定在源缓冲区的 `BufLeave`、`WinLeave`、`InsertEnter`、`CursorMoved` 上，并监测浮窗 `WinClosed`；关闭时清理事件组。旧版把 `BufLeave`/`WinLeave` 绑在未被进入的浮窗上，外部点击无法触发，所以菜单一直停留。浮窗还显式清空 `winbar`，关闭 `cursorcolumn` 和换行，设置零滚动边距，避免继承编辑器选项导致额外空行或菜单自动滚动。

### 3. Heirline 显式使用 WinBar 基础组

公开 Neovim 配置 `~/dotfiles/config/nvim/lua/plugins/heirline.lua` 的 `ContextlineWinbar` 设置了 `hl = "WinBar"`。这让组件空白处和默认文字也使用主题提供的顶栏颜色。

## 以后调整时要区分的颜色

| 高亮组 | 用途 | 面包屑中的作用 |
|---|---|---|
| `WinBar` | 活动窗口顶栏 | 普通面包屑的文字和背景来源 |
| `WinBarNC` | 非活动窗口顶栏 | 源窗口不应因打开菜单而意外切到这个组 |
| `TabLineSel` | 当前标签 | 只用于标签，不应用作面包屑颜色来源 |
| `Pmenu` | 弹出菜单普通行 | 层级菜单和补全菜单的普通表面 |
| `PmenuSel` | 弹出菜单选中行 | 菜单中当前选中的条目 |
| `DiagnosticWarn` / `WarningMsg` | 警告文字 | `ContextlineAlert` 的文字来源 |

调色时优先修改主题的语义组，再检查 Contextline 读取的是哪个组。不要把 `TabLineSel`、某个主题的私有组或固定十六进制值直接当成所有顶栏的通用配色。

## 验证方法

在插件目录运行：

```sh
bash tests/test.sh
```

`tests/menu_spec.lua` 检查打开菜单时当前窗口和缓冲区不变、`j` 可以移动弹出菜单的光标、Esc 可以关闭菜单，并且原有的缓冲区按键映射会恢复。`tests/menu_align_spec.lua` 检查活动段文字不位移、点击前后使用相同颜色、浮窗仍对齐到被点击的段。

`tests/winbar_theme_sync_spec.lua` 在文字已生成后修改 `WinBar`，检查已有高亮立即跟随新主题，不能依赖第二次点击刷新。`tests/mouse_ui_spec.py` 使用 pynvim 为 Neovim 附加真实 UI，再发送 `nvim_input_mouse` 事件，验证外部点击、同一光标位置点击、条目跳转和窗口切换。没有 python3/pynvim 时该项显示 SKIP。

公开配置的 `config/nvim/tests/winbar_refresh_spec.lua` 使用实际 Heirline 组件，先缓存旧顶栏，再执行 UI adapter，检查生成的高亮同步更新。

如果需要从运行中的 Neovim 检查颜色，可执行：

```vim
:lua print(vim.inspect(vim.api.nvim_get_hl(0, { name = "WinBar", link = false })))
:lua print(vim.inspect(vim.api.nvim_get_hl(0, { name = "ContextlineText", link = false })))
:lua print(vim.inspect(vim.api.nvim_get_hl(0, { name = "ContextlineActiveMenu", link = false })))
:lua print(vim.inspect(vim.api.nvim_get_hl(0, { name = "Pmenu", link = false })))
```

打开菜单前后还要确认：`nvim_get_current_win()` 和 `nvim_get_current_buf()` 没变；活动段仍在 `WinBar` 上评估；BufferLine 的渲染字符串和高亮区间保持一致。`ContextlineActiveMenu` 只用于定位；检查它的 `fg`/`bg` 应与 `ContextlineText` 一致。菜单当前行则检查 `PmenuSel`。

`chezmoi` 管理的插件代码修改后，只对相应目标文件运行 `chezmoi apply`，不要为了应用一个 Neovim 文件触发其他配置的全量覆盖。
