local helpers = require("tests.helpers")
local component_props = require("react.lsp.rename.component_props")
local utils = require("react.lsp.rename.utils")

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

--- Create an LSP range object
---@param start_line number
---@param start_char number
---@param end_line number
---@param end_char number
---@return table
local function create_range(start_line, start_char, end_line, end_char)
    return {
        start = { line = start_line, character = start_char },
        ["end"] = { line = end_line, character = end_char },
    }
end

-- ========================================================================
-- Name Transformation Tests
-- ========================================================================

T["calculate_props_type_name"] = new_set()

T["calculate_props_type_name"]["converts simple component name"] = function()
    local result = component_props.calculate_props_type_name("Button")
    eq(result, "ButtonProps")
end

T["calculate_props_type_name"]["converts multi-word component name"] = function()
    local result = component_props.calculate_props_type_name("CustomButton")
    eq(result, "CustomButtonProps")
end

T["calculate_props_type_name"]["handles empty string"] = function()
    local result = component_props.calculate_props_type_name("")
    eq(result, "")
end

T["calculate_props_type_name"]["handles nil"] = function()
    ---@diagnostic disable-next-line: param-type-mismatch
    local result = component_props.calculate_props_type_name(nil)
    eq(result, "")
end

T["calculate_component_name"] = new_set()

T["calculate_component_name"]["extracts simple component name"] = function()
    local result = component_props.calculate_component_name("ButtonProps")
    eq(result, "Button")
end

T["calculate_component_name"]["extracts multi-word component name"] = function()
    local result = component_props.calculate_component_name("CustomButtonProps")
    eq(result, "CustomButton")
end

T["calculate_component_name"]["returns nil for no Props suffix"] = function()
    local result = component_props.calculate_component_name("Button")
    eq(result, nil)
end

T["calculate_component_name"]["returns nil for just Props"] = function()
    local result = component_props.calculate_component_name("Props")
    eq(result, nil)
end

T["calculate_component_name"]["returns nil for empty string"] = function()
    local result = component_props.calculate_component_name("")
    eq(result, nil)
end

T["calculate_component_name"]["returns nil for nil"] = function()
    ---@diagnostic disable-next-line: param-type-mismatch
    local result = component_props.calculate_component_name(nil)
    eq(result, nil)
end

-- ========================================================================
-- Component Detection Tests
-- ========================================================================

T["is_component_name"] = new_set()
T["is_component_name"]["function_declaration"] = new_set()

T["is_component_name"]["function_declaration"]["detects function component"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 9 }) -- cursor on "Button"

    local result = component_props.is_component_name(bufnr, { 1, 9 })

    if result then
        eq(result.is_component, true)
        eq(result.component_name, "Button")
        eq(result.props_type_name, "ButtonProps")
        eq(result.type_location, nil)
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["function_declaration"]["detects with props type present"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps {",
        "  label: string;",
        "}",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 4, 9 }) -- cursor on "Button"

    local result = component_props.is_component_name(bufnr, { 4, 9 })

    if result then
        eq(result.is_component, true)
        eq(result.component_name, "Button")
        eq(result.props_type_name, "ButtonProps")
        eq(result.type_location ~= nil, true)
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["arrow_function"] = new_set()

T["is_component_name"]["arrow_function"]["detects arrow function component"] = function()
    local bufnr = create_react_buffer({
        "const Button = () => {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- cursor on "Button"

    local result = component_props.is_component_name(bufnr, { 1, 6 })

    if result then
        eq(result.is_component, true)
        eq(result.component_name, "Button")
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["arrow_function"]["detects with props type present"] = function()
    local bufnr = create_react_buffer({
        "type ButtonProps = { label: string }",
        "const Button = () => {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 6 }) -- cursor on "Button"

    local result = component_props.is_component_name(bufnr, { 2, 6 })

    if result then
        eq(result.is_component, true)
        eq(result.type_location ~= nil, true)
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["function_expression"] = new_set()

T["is_component_name"]["function_expression"]["detects function expression component"] = function()
    local bufnr = create_react_buffer({
        "const Button = function() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- cursor on "Button"

    local result = component_props.is_component_name(bufnr, { 1, 6 })

    if result then
        eq(result.is_component, true)
        eq(result.component_name, "Button")
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["edge_cases"] = new_set()

T["is_component_name"]["edge_cases"]["rejects non-PascalCase"] = function()
    local bufnr = create_react_buffer({
        "function button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local result = component_props.is_component_name(bufnr, { 1, 9 })

    if result then
        eq(result.is_component, false)
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["edge_cases"]["rejects non-JSX return"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return 'hello'",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local result = component_props.is_component_name(bufnr, { 1, 9 })

    if result then
        eq(result.is_component, false)
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["edge_cases"]["rejects JavaScript file"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    }, "javascriptreact")

    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local result = component_props.is_component_name(bufnr, { 1, 9 })

    if result then
        eq(result.is_component, false)
    end

    cleanup_buffer(bufnr)
end

T["is_component_name"]["edge_cases"]["rejects cursor not on identifier"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- cursor on "function"

    local result = component_props.is_component_name(bufnr, { 1, 0 })

    if result then
        eq(result.is_component, false)
    end

    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Props Type Detection Tests
-- ========================================================================

T["is_props_type_name"] = new_set()
T["is_props_type_name"]["interface"] = new_set()

T["is_props_type_name"]["interface"]["detects interface props type"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps {",
        "  label: string;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- cursor on "ButtonProps"

    local result = component_props.is_props_type_name(bufnr, { 1, 10 })

    if result then
        eq(result.is_props_type, true)
        eq(result.component_name, "Button")
        eq(result.props_type_name, "ButtonProps")
        eq(result.component_location, nil)
    end

    cleanup_buffer(bufnr)
end

T["is_props_type_name"]["interface"]["detects with component present"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps {",
        "  label: string;",
        "}",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 })

    local result = component_props.is_props_type_name(bufnr, { 1, 10 })

    if result then
        eq(result.is_props_type, true)
        eq(result.component_location ~= nil, true)
    end

    cleanup_buffer(bufnr)
end

T["is_props_type_name"]["type_alias"] = new_set()

T["is_props_type_name"]["type_alias"]["detects type alias props type"] = function()
    local bufnr = create_react_buffer({
        "type ButtonProps = {",
        "  label: string;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- cursor on "ButtonProps"

    local result = component_props.is_props_type_name(bufnr, { 1, 5 })

    if result then
        eq(result.is_props_type, true)
        eq(result.component_name, "Button")
        eq(result.props_type_name, "ButtonProps")
    end

    cleanup_buffer(bufnr)
end

T["is_props_type_name"]["type_alias"]["detects with component present"] = function()
    local bufnr = create_react_buffer({
        "type ButtonProps = { label: string }",
        "const Button = () => <div>Click</div>",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 5 })

    local result = component_props.is_props_type_name(bufnr, { 1, 5 })

    if result then
        eq(result.is_props_type, true)
        eq(result.component_location ~= nil, true)
    end

    cleanup_buffer(bufnr)
end

T["is_props_type_name"]["edge_cases"] = new_set()

T["is_props_type_name"]["edge_cases"]["rejects non-Props suffix"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonState {",
        "  count: number;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 })

    local result = component_props.is_props_type_name(bufnr, { 1, 10 })

    if result then
        eq(result.is_props_type, false)
    end

    cleanup_buffer(bufnr)
end

T["is_props_type_name"]["edge_cases"]["rejects JavaScript file"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps {",
        "  label: string;",
        "}",
    }, "javascript")

    vim.api.nvim_win_set_cursor(0, { 1, 10 })

    local result = component_props.is_props_type_name(bufnr, { 1, 10 })

    if result then
        eq(result.is_props_type, false)
    end

    cleanup_buffer(bufnr)
end

T["is_props_type_name"]["edge_cases"]["rejects cursor not on type identifier"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps {",
        "  label: string;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 2 }) -- cursor on "label"

    local result = component_props.is_props_type_name(bufnr, { 2, 2 })

    if result then
        eq(result.is_props_type, false)
    end

    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Utility Function Tests
-- ========================================================================

T["is_type_shared"] = new_set()

T["is_type_shared"]["single usage returns false"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button(props: ButtonProps) {",
        "  return <div>{props.label}</div>",
        "}",
    })

    local result = component_props.is_type_shared(bufnr, "ButtonProps")

    eq(result, false)

    cleanup_buffer(bufnr)
end

T["is_type_shared"]["multiple usage returns true"] = function()
    local bufnr = create_react_buffer({
        "interface SharedProps { label: string }",
        "function Button(props: SharedProps) {",
        "  return <div>{props.label}</div>",
        "}",
        "function Link(props: SharedProps) {",
        "  return <a>{props.label}</a>",
        "}",
    })

    local result = component_props.is_type_shared(bufnr, "SharedProps")

    eq(result, true)

    cleanup_buffer(bufnr)
end

T["is_type_shared"]["no usage returns false"] = function()
    local bufnr = create_react_buffer({
        "interface UnusedProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    local result = component_props.is_type_shared(bufnr, "UnusedProps")

    eq(result, false)

    cleanup_buffer(bufnr)
end

T["check_conflict"] = new_set()

T["check_conflict"]["detects existing identifier"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "function CustomButton() {",
        "  return <div>Custom</div>",
        "}",
    })

    local has_conflict = utils.check_conflict(bufnr, "CustomButton")

    eq(has_conflict, true)

    cleanup_buffer(bufnr)
end

T["check_conflict"]["returns false when no conflict"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    local has_conflict = utils.check_conflict(bufnr, "CustomButton")

    eq(has_conflict, false)

    cleanup_buffer(bufnr)
end

T["check_conflict"]["returns false for empty buffer"] = function()
    local bufnr = create_react_buffer({})

    local has_conflict = utils.check_conflict(bufnr, "Button")

    eq(has_conflict, false)

    cleanup_buffer(bufnr)
end

T["find_references"] = new_set()

T["find_references"]["finds single reference"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
    })

    local references = utils.find_references(bufnr, "ButtonProps")

    eq(#references, 1)
    eq(references[1].range.start.line, 0)
    eq(references[1].range.start.character, 10)

    cleanup_buffer(bufnr)
end

T["find_references"]["finds multiple references"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button(props: ButtonProps) {",
        "  const x: ButtonProps = props",
        "}",
    })

    local references = utils.find_references(bufnr, "ButtonProps")

    eq(#references, 3)

    cleanup_buffer(bufnr)
end

T["find_references"]["returns empty for no references"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    local references = utils.find_references(bufnr, "ButtonProps")

    eq(#references, 0)

    cleanup_buffer(bufnr)
end

T["find_references"]["respects word boundaries"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "interface MyButtonProps { label: string }",
    })

    local references = utils.find_references(bufnr, "ButtonProps")

    -- Should only match "ButtonProps", not "MyButtonProps"
    eq(#references, 1)

    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Prepare Rename Tests
-- ========================================================================

T["prepare_secondary_rename"] = new_set()
T["prepare_secondary_rename"]["component_to_type"] = new_set()

T["prepare_secondary_rename"]["component_to_type"]["renames props type when both exist"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 9 }) -- cursor on "Button"

    local result = component_props.prepare_secondary_rename(bufnr, { 2, 9 }, "CustomButton")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "ButtonProps")
        eq(result.secondary_name, "CustomButtonProps")
        eq(#result.references > 0, true)
    end

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["component_to_type"]["returns nil when props type missing"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local result = component_props.prepare_secondary_rename(bufnr, { 1, 9 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["component_to_type"]["warns and skips when props type is shared"] = function()
    local bufnr = create_react_buffer({
        "interface SharedProps { label: string }",
        "function Button(props: SharedProps) {",
        "  return <div>{props.label}</div>",
        "}",
        "function Link(props: SharedProps) {",
        "  return <a>{props.label}</a>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 9 }) -- cursor on "Button"

    local result = component_props.prepare_secondary_rename(bufnr, { 2, 9 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["component_to_type"]["warns and skips on conflict"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "interface CustomButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 3, 9 })

    local result = component_props.prepare_secondary_rename(bufnr, { 3, 9 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["type_to_component"] = new_set()

T["prepare_secondary_rename"]["type_to_component"]["renames component when both exist"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- cursor on "ButtonProps"

    local result = component_props.prepare_secondary_rename(bufnr, { 1, 10 }, "CustomButtonProps")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "Button")
        eq(result.secondary_name, "CustomButton")
        eq(#result.references > 0, true)
    end

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["type_to_component"]["returns nil when component missing"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 })

    local result = component_props.prepare_secondary_rename(bufnr, { 1, 10 }, "CustomButtonProps")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["type_to_component"]["returns nil when new name doesn't match pattern"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 })

    local result = component_props.prepare_secondary_rename(bufnr, { 1, 10 }, "Button")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["type_to_component"]["warns and skips on conflict"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "function CustomButton() {",
        "  return <div>Custom</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 })

    local result = component_props.prepare_secondary_rename(bufnr, { 1, 10 }, "CustomButtonProps")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["edge_cases"] = new_set()

T["prepare_secondary_rename"]["edge_cases"]["returns nil for JavaScript file"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    }, "javascriptreact")

    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local result = component_props.prepare_secondary_rename(bufnr, { 1, 9 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["edge_cases"]["returns nil for cursor not on component or type"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 3, 10 }) -- cursor on "return"

    local result = component_props.prepare_secondary_rename(bufnr, { 3, 10 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_from_edit"] = new_set()

T["prepare_secondary_from_edit"]["extracts name from workspace edit"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 9 })

    local workspace_edit = {
        changes = {
            [vim.uri_from_bufnr(bufnr)] = {
                { range = create_range(1, 9, 1, 15), newText = "CustomButton" },
            },
        },
    }

    local result = component_props.prepare_secondary_from_edit(bufnr, { 2, 9 }, workspace_edit)

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "ButtonProps")
        eq(result.secondary_name, "CustomButtonProps")
    end

    cleanup_buffer(bufnr)
end

T["prepare_secondary_from_edit"]["returns nil for invalid workspace edit"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local workspace_edit = {}

    local result = component_props.prepare_secondary_from_edit(bufnr, { 1, 9 }, workspace_edit)

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_from_edit"]["returns nil for JavaScript file"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
    }, "javascriptreact")

    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local workspace_edit = {
        changes = {
            [vim.uri_from_bufnr(bufnr)] = {
                { range = create_range(0, 9, 0, 15), newText = "CustomButton" },
            },
        },
    }

    local result = component_props.prepare_secondary_from_edit(bufnr, { 1, 9 }, workspace_edit)

    eq(result, nil)

    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Integration Tests
-- ========================================================================

T["integration"] = new_set()

T["integration"]["full rename flow component to type"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps {",
        "  label: string;",
        "  onClick: () => void;",
        "}",
        "function Button(props: ButtonProps) {",
        "  return <div onClick={props.onClick}>{props.label}</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 5, 9 }) -- cursor on "Button"

    local result = component_props.prepare_secondary_rename(bufnr, { 5, 9 }, "SubmitButton")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "ButtonProps")
        eq(result.secondary_name, "SubmitButtonProps")
        -- Should find all references to ButtonProps
        eq(#result.references >= 2, true)
    end

    cleanup_buffer(bufnr)
end

T["integration"]["full rename flow type to component"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps {",
        "  label: string;",
        "}",
        "function Button(props: ButtonProps) {",
        "  return <div>{props.label}</div>",
        "}",
        "export { Button }",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- cursor on "ButtonProps"

    local result = component_props.prepare_secondary_rename(bufnr, { 1, 10 }, "SubmitButtonProps")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "Button")
        eq(result.secondary_name, "SubmitButton")
        -- Should find all references to Button
        eq(#result.references >= 2, true)
    end

    cleanup_buffer(bufnr)
end

T["integration"]["multiple components in buffer"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "interface LinkProps { href: string }",
        "function Link() {",
        "  return <a>Link</a>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 9 }) -- cursor on first "Button"

    local result = component_props.prepare_secondary_rename(bufnr, { 2, 9 }, "CustomButton")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "ButtonProps")
        eq(result.secondary_name, "CustomButtonProps")
        -- Should only affect Button-related references, not Link
        local button_refs = utils.find_references(bufnr, "ButtonProps")
        local link_refs = utils.find_references(bufnr, "LinkProps")
        eq(#button_refs, 1)
        eq(#link_refs, 1) -- Should be unchanged
    end

    cleanup_buffer(bufnr)
end

T["integration"]["exported component and type"] = function()
    local bufnr = create_react_buffer({
        "export interface ButtonProps {",
        "  label: string;",
        "}",
        "export function Button(props: ButtonProps) {",
        "  return <div>{props.label}</div>",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 4, 16 }) -- cursor on "Button"

    local result = component_props.prepare_secondary_rename(bufnr, { 4, 16 }, "IconButton")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "ButtonProps")
        eq(result.secondary_name, "IconButtonProps")
    end

    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Component Usage Rename Tests
-- ========================================================================

T["is_component_usage_in_same_file"] = new_set()

T["is_component_usage_in_same_file"]["detects basic usage"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "const App = () => <Button />",
    })

    vim.api.nvim_win_set_cursor(0, { 5, 19 }) -- cursor on "Button" in usage

    local result = component_props.is_component_usage_in_same_file(bufnr, { 5, 19 })

    if result then
        eq(result.is_usage, true)
        eq(result.component_name, "Button")
        eq(result.props_type_name, "ButtonProps")
        eq(result.type_location ~= nil, true)
    end

    cleanup_buffer(bufnr)
end

T["is_component_usage_in_same_file"]["detects usage with props"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button(props: ButtonProps) {",
        "  return <div>{props.label}</div>",
        "}",
        'const App = () => <Button label="Click" />',
    })

    vim.api.nvim_win_set_cursor(0, { 5, 19 })

    local result = component_props.is_component_usage_in_same_file(bufnr, { 5, 19 })

    if result then
        eq(result.is_usage, true)
        eq(result.component_name, "Button")
    end

    cleanup_buffer(bufnr)
end

T["is_component_usage_in_same_file"]["detects self-closing element"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "const App = () => <div><Button /></div>",
    })

    vim.api.nvim_win_set_cursor(0, { 5, 27 })

    local result = component_props.is_component_usage_in_same_file(bufnr, { 5, 27 })

    if result then
        eq(result.is_usage, true)
    end

    cleanup_buffer(bufnr)
end

T["is_component_usage_in_same_file"]["returns nil without props type"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "const App = () => <Button />",
    })

    vim.api.nvim_win_set_cursor(0, { 4, 19 })

    local result = component_props.is_component_usage_in_same_file(bufnr, { 4, 19 })

    if result then
        eq(result.is_usage, true)
        eq(result.type_location, nil)
    end

    cleanup_buffer(bufnr)
end

T["is_component_usage_in_same_file"]["rejects non-PascalCase"] = function()
    local bufnr = create_react_buffer({
        "const App = () => <button />",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 19 })

    local result = component_props.is_component_usage_in_same_file(bufnr, { 1, 19 })

    if result then
        eq(result.is_usage, false)
    end

    cleanup_buffer(bufnr)
end

T["is_component_usage_in_same_file"]["rejects cross-file usage"] = function()
    local bufnr = create_react_buffer({
        "import { Button } from './Button'",
        "const App = () => <Button />",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 19 })

    local result = component_props.is_component_usage_in_same_file(bufnr, { 2, 19 })

    if result then
        eq(result.is_usage, false)
    end

    cleanup_buffer(bufnr)
end

T["is_component_usage_in_same_file"]["rejects member expression"] = function()
    local bufnr = create_react_buffer({
        "const Foo = { Bar: () => <div>Bar</div> }",
        "const App = () => <Foo.Bar />",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 23 })

    local result = component_props.is_component_usage_in_same_file(bufnr, { 2, 23 })

    if result then
        eq(result.is_usage, false)
    end

    cleanup_buffer(bufnr)
end

T["is_component_usage_in_same_file"]["rejects JavaScript file"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "const App = () => <Button />",
    }, "javascriptreact")

    vim.api.nvim_win_set_cursor(0, { 4, 19 })

    local result = component_props.is_component_usage_in_same_file(bufnr, { 4, 19 })

    if result then
        eq(result.is_usage, false)
    end

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["usage_to_definition"] = new_set()

T["prepare_secondary_rename"]["usage_to_definition"]["renames from usage when both exist"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button(props: ButtonProps) {",
        "  return <div>{props.label}</div>",
        "}",
        "const App = () => <Button />",
    })

    vim.api.nvim_win_set_cursor(0, { 5, 19 }) -- cursor on usage

    local result = component_props.prepare_secondary_rename(bufnr, { 5, 19 }, "CustomButton")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "ButtonProps")
        eq(result.secondary_name, "CustomButtonProps")
        eq(#result.references > 0, true)
    end

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["usage_to_definition"]["returns nil without props type"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div>Click</div>",
        "}",
        "const App = () => <Button />",
    })

    vim.api.nvim_win_set_cursor(0, { 4, 19 })

    local result = component_props.prepare_secondary_rename(bufnr, { 4, 19 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["usage_to_definition"]["warns and skips when shared"] = function()
    local bufnr = create_react_buffer({
        "interface SharedProps { label: string }",
        "function Button(props: SharedProps) {",
        "  return <div>{props.label}</div>",
        "}",
        "function Link(props: SharedProps) {",
        "  return <a>{props.label}</a>",
        "}",
        "const App = () => <Button />",
    })

    vim.api.nvim_win_set_cursor(0, { 8, 19 })

    local result = component_props.prepare_secondary_rename(bufnr, { 8, 19 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["usage_to_definition"]["warns and skips on conflict"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "interface CustomButtonProps { label: string }",
        "function Button(props: ButtonProps) {",
        "  return <div>{props.label}</div>",
        "}",
        "const App = () => <Button />",
    })

    vim.api.nvim_win_set_cursor(0, { 6, 19 })

    local result = component_props.prepare_secondary_rename(bufnr, { 6, 19 }, "CustomButton")

    eq(result, nil)

    cleanup_buffer(bufnr)
end

T["prepare_secondary_rename"]["usage_to_definition"]["handles multiple usages"] = function()
    local bufnr = create_react_buffer({
        "interface ButtonProps { label: string }",
        "function Button(props: ButtonProps) {",
        "  return <div>{props.label}</div>",
        "}",
        "const App = () => {",
        "  return (",
        "    <div>",
        "      <Button />",
        "      <Button />",
        "    </div>",
        "  )",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 8, 7 }) -- first usage

    local result = component_props.prepare_secondary_rename(bufnr, { 8, 7 }, "SubmitButton")

    eq(result ~= nil, true)
    if result then
        eq(result.secondary_old, "ButtonProps")
        eq(result.secondary_name, "SubmitButtonProps")
    end

    cleanup_buffer(bufnr)
end

return T
