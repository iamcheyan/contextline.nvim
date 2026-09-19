# Language context design

`contextline.nvim` is a display layer, not a compiler and not a replacement
for an LSP client. Its job is to answer one small question while editing:

> Where am I in this file, and which enclosing code blocks lead to this line?

The statusline should therefore show a path from the broadest useful scope to
the current symbol. For example:

```text
PYTHON | class NightReport | method calculate_summary
JAVA | class NightBatchRunner | method process
JAVASCRIPT | class CsvRecord | method toCsv
HTML | element main | element section | element button
```

Each Tree-sitter segment also contains `kind`, `label`, and `lnum` metadata so
another UI can turn the same data into clickable navigation, a breadcrumb, or
a richer winbar. The default text stays compact enough for a statusline.

## What users need from each language

### Python

Python users normally need the module-level class and the current function or
method. The useful path is:

```text
module/file | class | method
```

The generic provider recognizes classes, functions, and methods from the
Python grammar. A function inside a class is labelled `method`; a top-level
function is labelled `function`. Decorators and local control-flow blocks are
not displayed because they make the path noisy without helping navigation.

### JavaScript and TypeScript

For application and batch tooling, the useful path is usually:

```text
class | method
class | static method
function
interface | method/type member
```

The provider recognizes declarations, definitions, interfaces, enums, type
declarations, and implementation nodes where the installed grammar exposes
them. TypeScript interfaces and enums are kept as separate labelled scopes so
the statusline does not make a type definition look like an executable
function.

### Java

Java code is commonly navigated by package, class, record, and method:

```text
package | class | method
package | record | method
interface | method
```

The generic provider recognizes class, interface, enum, record-like type, and
method nodes. A Java LSP can provide more semantic information, such as the
overload or fully qualified symbol; when `nvim-navic` has a location,
`contextline.nvim` gives that provider priority.

### Go

Go users care about the package, type, method receiver, and function:

```text
package | type ReportUploader | method Upload
package | function main
```

Struct and interface declarations are displayed as type scopes. Methods and
functions remain separate so a receiver method is not confused with a package
function.

### Ruby

Ruby nesting is important because classes and modules can contain methods with
the same name:

```text
module Billing | class Report | method write
class Report | singleton method build
```

The provider recognizes classes, modules, methods, and singleton methods. It
does not show every block passed to `each`, `map`, or `File.foreach`; those are
implementation details rather than stable navigation scopes.

### HTML

HTML is hierarchical rather than function-oriented. The useful context is the
element path under the cursor:

```text
element html | element body | element main | element section
```

This is useful when a page contains repeated forms, tables, or report panels.
Attributes are deliberately not copied into the statusline; the element name
is stable and readable, while the full tag remains visible in the buffer.

### SQL

SQL context is based on query blocks rather than methods:

```text
query | cte settlement_rows
query | table settlement_report
```

Support depends strongly on the SQL grammar installed by the user's
Tree-sitter setup. SQL dialects differ considerably, so dialect-specific
providers may add better names for CTEs, procedures, and tables later.

### Bash and shell scripts

Shell users generally need the current function and, in larger operations
scripts, the surrounding function-based job boundary:

```text
function archive_report
function upload_report
```

The generic provider intentionally does not treat every `if`, `case`, or loop
as a breadcrumb. The shell fixture in `night-batch-lab` is also useful for
testing return-code and job-step navigation.

### COBOL

COBOL is handled by `cobol.nvim`, not by the generic provider. Its context is
domain-specific and should remain richer than a normal Tree-sitter path:

```text
COBOL | FIXED | AREA B | PROCEDURE > 4000-WRITE | 4000-FORMAT-AND-WRITE | PIC 9(5) | 5 B
```

Divisions, sections, paragraphs, data items, PIC clauses, record sizes, and
Copybook context are more useful to a COBOL programmer than generic node
names.

### Windows Batch

`batch.nvim` also has a language-specific provider because labels and control
transfers are the important navigation units:

```text
BATCH | LABEL > upload_job | LINE 180 | CALL :ftp_upload
```

The provider can show the current label, line, `CALL`, `GOTO`, and target label.
This is especially useful for the intentionally long, explicitly written
night-batch fixture.

## Provider priority

The lookup order is:

1. a language plugin registered with `contextline.register()`;
2. `nvim-navic`, when an attached LSP exposes a location;
3. the generic Tree-sitter provider.

This lets a language start with useful syntax-tree context and later gain a
more accurate provider without changing the statusline configuration.

## Parser and navigation requirements

Tree-sitter context requires the parser for the current language. Syntax
highlighting alone is not proof that the parser is installed. If a parser is
missing, the provider returns no context rather than guessing from arbitrary
text. Install parsers through the user's normal `nvim-treesitter` setup.

For semantic navigation and overload-aware names, install an LSP and optionally
`nvim-navic`. The context plugin does not install language servers, parsers, or
keymaps by itself.

## Extension contract

A language plugin can register a provider like this:

```lua
require("contextline").register("my-language", {
  filetypes = { "mylang" },
  get_info = function(opts)
    return {
      language = "MYLANG",
      segments = {
        { text = "Report", label = "class", hl = "Type", lnum = 12 },
        { text = "write", label = "method", hl = "Function", lnum = 48 },
      },
      source = "my-language",
    }
  end,
})
```

The display layer remains reusable by Heirline, lualine, winbars, or another
status component. A provider should return `nil` when it cannot identify a
reliable context.
