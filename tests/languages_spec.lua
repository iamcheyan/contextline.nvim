local contextline = require("contextline")

local function run_test(name, ft, lines, cursor, expected_segments)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, cursor)

  local ok = pcall(vim.treesitter.start, buf, ft)
  if not ok then
    print(string.format("languages_spec [%s]: SKIP (parser not available)", name))
    return
  end

  local info = contextline.get_info({ bufnr = buf, winid = win })
  assert(info, string.format("[%s] Expected info to be non-nil", name))
  assert(info.segments, string.format("[%s] Expected segments to be non-nil", name))
  assert(#info.segments == #expected_segments,
    string.format("[%s] Expected %d segments, got %d: %s",
      name, #expected_segments, #info.segments, vim.inspect(info.segments)))

  for i, exp in ipairs(expected_segments) do
    local actual = info.segments[i]
    if exp.text then
      assert(actual.text == exp.text,
        string.format("[%s] Segment %d text: expected %s, got %s", name, i, exp.text, actual.text))
    end
    if exp.icon then
      assert(actual.icon == exp.icon,
        string.format("[%s] Segment %d icon: expected %s, got %s", name, i, exp.icon, actual.icon))
    end
  end
end

-- 1. Java
run_test("Java", "java", {
  "public class OrderService {",
  "  public void cancelOrder(String id) {",
  "    System.out.println(id);",
  "  }",
  "}",
}, { 3, 6 }, {
  { text = "OrderService", icon = "󰌗" },
  { text = "cancelOrder", icon = "󰆧" },
})

-- 2. Go
run_test("Go", "go", {
  "package report",
  "type Uploader struct {",
  "  APIKey string",
  "}",
  "func (u *Uploader) Upload(ctx context.Context) error {",
  "  return nil",
  "}",
}, { 6, 4 }, {
  { text = "(Uploader).Upload", icon = "󰆧" },
})

-- 3. Rust
run_test("Rust", "rust", {
  "mod network {",
  "  impl Client {",
  "    pub fn connect(&self) {}",
  "  }",
  "}",
}, { 3, 12 }, {
  { text = "network", icon = "󰌗" },
  { text = "impl Client", icon = "󰠱" },
  { text = "connect", icon = "󰆧" },
})

-- 4. C
run_test("C", "c", {
  "int compute_hash(const char* s) {",
  "  return 42;",
  "}",
}, { 2, 4 }, {
  { text = "compute_hash", icon = "󰊕" },
})

-- 5. JSON
run_test("JSON", "json", {
  "{",
  '  "scripts": {',
  '    "build": "tsc"',
  "  }",
  "}",
}, { 3, 6 }, {
  { text = "scripts", icon = "󰌋" },
  { text = "build", icon = "󰌋" },
})

-- 6. YAML
run_test("YAML", "yaml", {
  "services:",
  "  web:",
  "    image: nginx",
}, { 3, 6 }, {
  { text = "services", icon = "󰌋" },
  { text = "web", icon = "󰌋" },
  { text = "image", icon = "󰌋" },
})

-- 7. Markdown
run_test("Markdown", "markdown", {
  "# Architecture",
  "",
  "Overview",
  "",
  "## Database",
  "",
  "Details",
}, { 7, 2 }, {
  { text = "Architecture", icon = "󰉫" },
  { text = "Database", icon = "󰉫" },
})

-- 8. HTML
run_test("HTML", "html", {
  '<div id="app">',
  '  <main class="container">',
  "    <p>Hello</p>",
  "  </main>",
  "</div>",
}, { 3, 6 }, {
  { text = "div#app", icon = "󰅴" },
  { text = "main.container", icon = "󰅴" },
  { text = "p", icon = "󰅴" },
})

-- 9. SQL
run_test("SQL", "sql", {
  "WITH daily_summary AS (",
  "  SELECT count(*) FROM orders",
  ")",
  "SELECT * FROM daily_summary;",
}, { 2, 4 }, {
  { text = "daily_summary", icon = "󰆼" },
})

-- 10. Diagnostics and Scope Line formatting test
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "def my_func():",
  "    x = 1",
  "    y = 2",
  "    return x + y",
})
vim.bo[buf].filetype = "python"
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(win, buf)
vim.api.nvim_win_set_cursor(win, { 2, 4 })
pcall(vim.treesitter.start, buf, "python")

vim.diagnostic.set(vim.api.nvim_create_namespace("test_diag"), buf, {
  {
    lnum = 1,
    col = 4,
    severity = vim.diagnostic.severity.WARN,
    message = "Unused variable",
  },
})

local formatted = contextline.get({ bufnr = buf, show_scope_lines = true, show_diagnostics = true })
assert(formatted:find("my_func"), "Formatted string should contain function name")
assert(formatted:find("%(4L%)"), "Formatted string should contain scope lines (4L)")
assert(formatted:find(" 1"), "Formatted string should contain warning badge")

print("languages_spec: OK")
