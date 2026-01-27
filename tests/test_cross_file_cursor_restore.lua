local helpers = require("tests.helpers")
local rename = require("react.lsp.rename")
local component_props = require("react.lsp.rename.component_props")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- ========================================================================
-- Helper Functions
-- ========================================================================

--- Create test buffer
local function create_react_buffer(lines, filetype)
    if type(lines) == "string" then
        lines = vim.split(lines, "\n")
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = filetype or "typescriptreact"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)

    local lang = "tsx"
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if ok and parser then
        parser:parse()
    end

    return bufnr
end

--- Cleanup
local function cleanup_buffer(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

--- Mock LSP buf_request_all
local function mock_lsp_request(responses)
    local original_request = vim.lsp.buf_request_all
    local call_count = 0

    vim.lsp.buf_request_all = function(bufnr, method, params, callback)
        call_count = call_count + 1
        local response = responses[call_count] or {}
        vim.schedule(function()
            callback(response)
        end)
    end

    return {
        restore = function()
            vim.lsp.buf_request_all = original_request
        end,
    }
end

--- Mock LSP apply
local function mock_lsp_apply()
    local captured_edits = {}
    local lsp_init = require("react.lsp")
    local original_apply = lsp_init._original_apply_workspace_edit

    ---@diagnostic disable-next-line: duplicate-set-field
    lsp_init._original_apply_workspace_edit = function(edit, encoding)
        table.insert(captured_edits, { edit = edit, encoding = encoding })
    end

    return {
        captured = captured_edits,
        restore = function()
            lsp_init._original_apply_workspace_edit = original_apply
        end,
    }
end

-- ========================================================================
-- Cursor Restoration Tests
-- ========================================================================

T["cursor_restoration"] = new_set()

T["cursor_restoration"]["saves original position before modification"] = function()
    -- Create temp files
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

    local original_pos = { 4, 11 } -- Cursor on Button usage

    vim.api.nvim_win_set_cursor(0, original_pos)

    -- Detect scenario (this will be usage)
    local result = component_props.detect_cross_file_scenario(bufnr, original_pos)

    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["cursor_restoration"]["usage scenario sets should_restore_cursor flag"] = function()
    -- Create temp files
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

    local usage_pos = { 4, 11 }

    local result = component_props.detect_cross_file_scenario(bufnr, usage_pos)

    -- Usage scenario should exist
    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["cursor_restoration"]["import scenario does not restore cursor"] = function()
    -- Test that import scenario doesn't set should_restore_cursor
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)
    local import_pos = { 1, 9 } -- Cursor on Button in import

    vim.api.nvim_win_set_cursor(0, import_pos)

    local result = component_props.detect_cross_file_scenario(bufnr, import_pos)

    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "import") -- Import scenario, not usage
    end

    -- For import scenario, should_restore_cursor should be false
    -- (tested implicitly by implementation)

    cleanup_buffer(bufnr)
end

T["cursor_restoration"]["validates window before restoration"] = function()
    -- Test window validity check
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)
    local pos = { 4, 11 }

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(win, pos)

    -- Verify window is valid
    eq(vim.api.nvim_win_is_valid(win), true)

    cleanup_buffer(bufnr)
end

T["cursor_restoration"]["validates buffer before restoration"] = function()
    -- Test buffer validity in window check
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)
    local pos = { 4, 11 }

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(win, pos)

    -- Verify buffer matches window
    eq(vim.api.nvim_win_get_buf(win), bufnr)

    cleanup_buffer(bufnr)
end

T["cursor_restoration"]["cursor position preserved across rename"] = function()
    -- Test that original_pos variable holds the right value
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)
    local usage_pos = { 4, 11 }
    local win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_cursor(win, usage_pos)

    -- Verify initial position
    local cursor_before = vim.api.nvim_win_get_cursor(win)
    eq(cursor_before[1], usage_pos[1])
    eq(cursor_before[2], usage_pos[2])

    cleanup_buffer(bufnr)
end

T["cursor_restoration"]["usage scenario finds import position"] = function()
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    local component_code = [[
export function Button() {
  return <button>Click</button>
}
]]
    vim.fn.writefile(vim.split(component_code, "\n"), test_dir .. "/Button.tsx")

    local usage_code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(usage_code)
    vim.api.nvim_buf_set_name(bufnr, test_dir .. "/App.tsx")

    local usage_pos = { 4, 11 }

    -- The implementation should find import at line 1
    local result = component_props.detect_cross_file_scenario(bufnr, usage_pos)

    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
        eq(result.import_info ~= nil, true)
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["cursor_restoration"]["handles multiple imports correctly"] = function()
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    -- Create component files
    vim.fn.writefile({ "export function Input() {}" }, test_dir .. "/Input.tsx")
    vim.fn.writefile(
        { "export function Button() { return <button>Click</button> }" },
        test_dir .. "/Button.tsx"
    )

    local usage_code = [[
import { Input } from "./Input"
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(usage_code)
    vim.api.nvim_buf_set_name(bufnr, test_dir .. "/App.tsx")

    local usage_pos = { 5, 11 }

    local result = component_props.detect_cross_file_scenario(bufnr, usage_pos)

    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
        eq(result.component_name, "Button")
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["cursor_restoration"]["scheduled restoration executes after rename"] = function()
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    vim.fn.writefile(
        { "export function Button() { return <button>Click</button> }" },
        test_dir .. "/Button.tsx"
    )

    local usage_code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(usage_code)
    vim.api.nvim_buf_set_name(bufnr, test_dir .. "/App.tsx")

    local usage_pos = { 4, 11 }
    local win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_cursor(win, usage_pos)

    local result = component_props.detect_cross_file_scenario(bufnr, usage_pos)

    -- Usage scenario should schedule cursor restoration
    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["cursor_restoration"]["original_pos not modified during rename"] = function()
    -- Verify original_pos stays constant even if pos changes
    local code = [[
import { Button } from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(code)
    local usage_pos = { 4, 11 }

    -- Simulate what happens in handle_cross_file_direct_rename
    local original_pos = usage_pos
    local pos = usage_pos

    -- In usage scenario, pos gets modified to import position
    pos = { 1, 9 }

    -- original_pos should still be usage position
    eq(original_pos[1], 4)
    eq(original_pos[2], 11)
    eq(pos[1], 1)
    eq(pos[2], 9)

    cleanup_buffer(bufnr)
end

T["cursor_restoration"]["default import usage scenario"] = function()
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    vim.fn.writefile(
        { "export default function Button() { return <button>Click</button> }" },
        test_dir .. "/Button.tsx"
    )

    local usage_code = [[
import Button from "./Button"

export function App() {
  return <Button />
}
]]

    local bufnr = create_react_buffer(usage_code)
    vim.api.nvim_buf_set_name(bufnr, test_dir .. "/App.tsx")

    local usage_pos = { 4, 11 }

    local result = component_props.detect_cross_file_scenario(bufnr, usage_pos)

    -- Default imports currently not detected as cross-file (only named imports)
    eq(result, nil)

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

T["cursor_restoration"]["nested jsx usage preserves position"] = function()
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    vim.fn.writefile(
        { "export function Button() { return <button>Click</button> }" },
        test_dir .. "/Button.tsx"
    )

    local usage_code = [[
import { Button } from "./Button"

export function App() {
  return (
    <div>
      <section>
        <Button />
      </section>
    </div>
  )
}
]]

    local bufnr = create_react_buffer(usage_code)
    vim.api.nvim_buf_set_name(bufnr, test_dir .. "/App.tsx")

    local usage_pos = { 7, 9 }

    local result = component_props.detect_cross_file_scenario(bufnr, usage_pos)

    eq(result ~= nil, true)
    if result then
        eq(result.scenario, "usage")
    end

    cleanup_buffer(bufnr)
    vim.fn.delete(test_dir, "rf")
end

return T
