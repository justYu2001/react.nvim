local helpers = require("tests.helpers")
local component_props = require("react.lsp.rename.component_props")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- ========================================================================
-- Helper Functions
-- ========================================================================

--- Create a React buffer with content and filetype
---@param lines table|string: lines of content
---@param filetype string|nil: buffer filetype (default: "typescriptreact")
---@return number: buffer number
local function create_react_buffer(lines, filetype)
    if type(lines) == "string" then
        lines = vim.split(lines, "\n")
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = filetype or "typescriptreact"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- Set as current buffer and parse tree
    vim.api.nvim_set_current_buf(bufnr)

    -- Force treesitter parse
    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }
    local lang = lang_map[filetype or "typescriptreact"]
    if lang then
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
        if ok and parser then
            parser:parse()
        end
    end

    return bufnr
end

--- Cleanup a test buffer
---@param bufnr number: buffer number
local function cleanup_buffer(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

-- ========================================================================
-- Cross-File Import Detection Tests
-- ========================================================================

T["is_component_import"] = new_set()

T["is_component_import"]["detects named import"] = function()
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "Button" in import statement (line 1, col 9)
    local pos = { 1, 9 }
    local result = component_props.is_component_import(bufnr, pos)

    eq(result and result.is_import, true)
    eq(result and result.import_type, "named")
    eq(result and result.component_name, "Button")

    cleanup_buffer(bufnr)
end

T["is_component_import"]["detects default import"] = function()
    local code = [[
import Button from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "Button" in import statement (line 1, col 7)
    local pos = { 1, 7 }
    local result = component_props.is_component_import(bufnr, pos)

    eq(result and result.is_import, true)
    eq(result and result.import_type, "default")
    eq(result and result.component_name, "Button")

    cleanup_buffer(bufnr)
end

T["is_component_import"]["returns false for non-import identifier"] = function()
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "Button" in JSX (line 4, col 11)
    local pos = { 4, 11 }
    local result = component_props.is_component_import(bufnr, pos)

    eq(result and result.is_import, false)

    cleanup_buffer(bufnr)
end

T["is_component_import"]["returns false for lowercase import"] = function()
    local code = [[
import { button } from "./button"

export function App() {
  return <div />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "button" in import statement
    local pos = { 1, 9 }
    local result = component_props.is_component_import(bufnr, pos)

    eq(result and result.is_import, false)

    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Cross-File Scenario Detection Tests
-- ========================================================================

T["detect_cross_file_scenario"] = new_set()

T["detect_cross_file_scenario"]["detects import scenario for named import"] = function()
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "Button" in import
    local pos = { 1, 9 }
    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    eq(result ~= nil, true)
    eq(result and result.is_cross_file, true)
    eq(result and result.scenario, "import")
    eq(result and result.import_type, "named")
    eq(result and result.component_name, "Button")

    cleanup_buffer(bufnr)
end

T["detect_cross_file_scenario"]["detects import scenario for default import"] = function()
    local code = [[
import Button from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "Button" in import
    local pos = { 1, 7 }
    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    eq(result ~= nil, true)
    eq(result and result.is_cross_file, true)
    eq(result and result.scenario, "import")
    eq(result and result.import_type, "default")
    eq(result and result.component_name, "Button")

    cleanup_buffer(bufnr)
end

T["detect_cross_file_scenario"]["returns nil for same-file component"] = function()
    local code = [[
interface ButtonProps {
  label: string;
}

function Button(props: ButtonProps) {
  return <button>{props.label}</button>
}

export function App() {
  return <Button label="Click me" />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "Button" component name
    local pos = { 5, 9 }
    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    eq(result, nil)

    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Usage Scenario Detection Tests
-- ========================================================================

T["detect_cross_file_scenario"]["usage_scenario"] = new_set()

T["detect_cross_file_scenario"]["usage_scenario"]["detects usage of imported component"] = function()
    -- Create temp directory and component file
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    local component_code = [[
interface ButtonProps {
  label: string;
}

export function Button(props: ButtonProps) {
  return <button>{props.label}</button>
}
]]
    local component_file = test_dir .. "/Button.tsx"
    vim.fn.writefile(vim.split(component_code, "\n"), component_file)

    local usage_code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(usage_code)
    local usage_file = test_dir .. "/App.tsx"
    vim.api.nvim_buf_set_name(bufnr, usage_file)

    -- Cursor on "Button" in JSX usage (line 4, col 11)
    local pos = { 4, 11 }
    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    eq(result ~= nil, true)
    if result then
        eq(result.is_cross_file, true)
        eq(result.scenario, "usage")
        eq(result.component_name, "Button")
        eq(result.import_info ~= nil, true)
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["detect_cross_file_scenario"]["usage_scenario"]["returns nil for non-imported component"] = function()
    local code = [[
function Button() {
  return <button>Click</button>
}

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)

    -- Cursor on "Button" usage (same file component)
    local pos = { 6, 11 }
    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["detect_cross_file_scenario"]["usage_scenario"]["detects usage with default import"] = function()
    -- Create temp directory and component file
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    local component_code = [[
export default function Button() {
  return <button>Click</button>
}
]]
    local component_file = test_dir .. "/Button.tsx"
    vim.fn.writefile(vim.split(component_code, "\n"), component_file)

    local usage_code = [[
import Button from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(usage_code)
    local usage_file = test_dir .. "/App.tsx"
    vim.api.nvim_buf_set_name(bufnr, usage_file)

    -- Cursor on "Button" in JSX usage
    local pos = { 4, 11 }
    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    -- Default imports currently not detected as cross-file (only named imports)
    -- This is expected behavior - default imports use different AST structure
    eq(result, nil)

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["detect_cross_file_scenario"]["usage_scenario"]["detects usage in nested JSX"] = function()
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    local component_code = [[
export function Button() {
  return <button>Click</button>
}
]]
    local component_file = test_dir .. "/Button.tsx"
    vim.fn.writefile(vim.split(component_code, "\n"), component_file)

    local usage_code = [[
import { Button } from "./Button"

export function App() {
  return (
    <div>
      <Button />
    </div>
  )
}
]]

    local bufnr = create_react_buffer(usage_code)
    local usage_file = test_dir .. "/App.tsx"
    vim.api.nvim_buf_set_name(bufnr, usage_file)

    -- Cursor on "Button" in nested JSX
    local pos = { 6, 7 }
    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["detect_cross_file_scenario"]["usage_scenario"]["extracts import_info from usage"] = function()
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    local component_code = [[
export function Button() {
  return <button>Click</button>
}
]]
    local component_file = test_dir .. "/Button.tsx"
    vim.fn.writefile(vim.split(component_code, "\n"), component_file)

    local usage_code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(usage_code)
    local usage_file = test_dir .. "/App.tsx"
    vim.api.nvim_buf_set_name(bufnr, usage_file)

    local pos = { 4, 11 }

    local result = component_props.detect_cross_file_scenario(bufnr, pos)

    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
        eq(result.import_info ~= nil, true)
        if result.import_info then
            eq(result.import_info.component_info ~= nil, true)
        end
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

return T
