# contextline.nvim

A small context provider for Neovim statuslines and Winbars.

`contextline.nvim` does not replace Heirline, lualine, or dropbar. It provides
the current code hierarchy as reusable data and a simple text component. A
language plugin can register its own parser, while common languages can use the
generic Tree-sitter provider.

## What it displays

Examples:

```text
PYTHON | Demo | run
COBOL | FIXED | PROCEDURE > 2000-PROCESS | WS-COUNT | PIC 9(5) | 5 B
BATCH | LABEL > process_job | LINE 180 | CALL :upload_job
```

## Built-in providers

- Custom providers registered by language plugins have priority.
- `nvim-navic` is used when available and has a location for the buffer.
- Tree-sitter is used as a dependency-free fallback for common languages.

The generic Tree-sitter provider currently recognizes common class, function,
method, module, interface, struct, enum, trait, and implementation nodes in
languages such as Python, Lua, JavaScript/TypeScript, Bash, C/C++, Go, Rust,
Ruby, and Java, subject to the installed parser grammar.

The language-specific design and the information users typically need from
each language are documented in [Language context design](docs/language-context.md).

## Installation

With lazy.nvim:

```lua
{
  "iamcheyan/contextline.nvim",
  event = { "BufReadPost", "BufNewFile" },
  opts = {},
}
```

The usual display integration is a component in an existing statusline:

```lua
local contextline = require("contextline")

-- lualine
{ contextline.component() }
```

For Heirline, use `contextline.get()` from a provider component. The plugin
does not install a statusline or keymaps by default.

## Registering a language provider

Language plugins can provide more accurate context than a generic syntax tree:

```lua
require("contextline").register("my-language", {
  filetypes = { "mylang" },
  get_info = function(opts)
    return {
      language = "MYLANG",
      segments = {
        { text = "SECTION > Main", hl = "Identifier" },
        { text = "FUNCTION > run", hl = "Function" },
      },
      source = "my-language",
    }
  end,
})
```

Providers return `nil` when no context is available. Each segment may contain
`text`, `hl`, `kind`, and `lnum` fields.

## Supported language strategy

The plugin intentionally separates display from parsing:

- use Tree-sitter for mainstream programming languages;
- use LSP/navic when a language server has better semantic information;
- use custom providers for COBOL, Batch, SQL dialects, JCL, or other legacy
  languages whose structure is not represented by a reliable LSP.

## Development

```bash
tests/test.sh
```

The multilingual fixtures used for manual testing live in the companion
[`night-batch-lab`](https://github.com/iamcheyan/night-batch-lab) project.

The repository is developed with `cobol.nvim`, `batch.nvim`, and the
`night-batch-lab` practice project.
