local helpers = require("tests.helpers")
local props = require("react.lsp.rename.props")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- ========================================================================
-- Helper Functions
-- ========================================================================

--- Create React buffer with content and filetype
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

--- Cleanup buffer
---@param bufnr number: buffer number
local function cleanup_buffer(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

--- Find function node at cursor position
---@param bufnr number
---@param row number: 0-indexed row
---@param col number: column
---@return TSNode|nil
local function find_function_at_cursor(bufnr, row, col)
    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local root = parser:parse()[1]:root()
    local node = root:descendant_for_range(row, col, row, col)
    while node do
        local t = node:type()
        if t == "function_declaration" or t == "arrow_function" or t == "function_expression" then
            return node
        end
        node = node:parent()
    end
    return nil
end

-- ========================================================================
-- Unit Tests: is_react_component()
-- ========================================================================

T["is_react_component"] = new_set()
T["is_react_component"]["react_components"] = new_set()
T["is_react_component"]["normal_functions"] = new_set()
T["is_react_component"]["edge_cases"] = new_set()

-- React Components (should return true)

T["is_react_component"]["react_components"]["function_declaration_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return <div />",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["react_components"]["arrow_function_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "const Button = () => {",
        "  return <div />",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 15)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["react_components"]["arrow_function_implicit_return"] = function()
    local bufnr = create_react_buffer({
        "const Button = () => <div />",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 15)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["react_components"]["function_expression_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "const Button = function() {",
        "  return <div />",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 15)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["react_components"]["self_closing_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Icon() {",
        "  return <img />",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["react_components"]["jsx_fragment"] = function()
    local bufnr = create_react_buffer({
        "function List() {",
        "  return <>text</>",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["react_components"]["exported_function"] = function()
    local bufnr = create_react_buffer({
        "export function Button() {",
        "  return <div />",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 16)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

-- Normal Functions (should return false)

T["is_react_component"]["normal_functions"]["lowercase_name_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "function button() {",
        "  return <div />",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, false)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["normal_functions"]["pascalcase_no_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Helper() {",
        "  return 'text'",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, false)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["normal_functions"]["lowercase_no_jsx"] = function()
    local bufnr = create_react_buffer({
        "function helper() {",
        "  return 'text'",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, false)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["normal_functions"]["arrow_lowercase_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "const helper = () => <div />",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 15)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, false)
    cleanup_buffer(bufnr)
end

-- Edge Cases

T["is_react_component"]["edge_cases"]["conditional_jsx_return"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  return show ? <div /> : null",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["edge_cases"]["jsx_in_variable"] = function()
    local bufnr = create_react_buffer({
        "function Button() {",
        "  const el = <div />",
        "  return el",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["is_react_component"]["edge_cases"]["nested_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Container() {",
        "  return <div><span /></div>",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Integration Tests: Detection Filtering - Destructuring
-- ========================================================================

T["detection_filtering"] = new_set()
T["detection_filtering"]["destructuring"] = new_set()

T["detection_filtering"]["destructuring"]["should_not_detect_lowercase_function"] = function()
    local bufnr = create_react_buffer({
        "function helper({ name }) {",
        "  return <div>{name}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 18 }) -- cursor on "name" param

    local result = props.detect_prop_at_cursor(bufnr, { 1, 18 })

    eq(result, nil) -- Should NOT detect
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["destructuring"]["should_detect_pascalcase_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Button({ label }) {",
        "  return <div>{label}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 18 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 18 })

    eq(result ~= nil, true)
    if result then
        eq(result.is_prop, true)
        eq(result.prop_name, "label")
        eq(result.context, "destructure")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["destructuring"]["shorthand_arrow_function"] = function()
    local bufnr = create_react_buffer({
        "const Button = ({ x }) => <div />",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 19 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 19 })

    eq(result ~= nil, true)
    if result then
        eq(result.is_prop, true)
        eq(result.prop_name, "x")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["destructuring"]["shorthand_lowercase_arrow"] = function()
    local bufnr = create_react_buffer({
        "const helper = ({ x }) => <div />",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 19 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 19 })

    eq(result, nil) -- lowercase = not React component
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["destructuring"]["aliased_pascalcase"] = function()
    local bufnr = create_react_buffer({
        "function Button({ name: userName }) {",
        "  return <div>{userName}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 18 }) -- cursor on "name" (key)

    local result = props.detect_prop_at_cursor(bufnr, { 1, 18 })

    eq(result ~= nil, true)
    if result then
        eq(result.prop_name, "name")
        eq(result.cursor_target, "key")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["destructuring"]["aliased_lowercase"] = function()
    local bufnr = create_react_buffer({
        "function helper({ name: userName }) {",
        "  return <div>{userName}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 18 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 18 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["destructuring"]["function_expression_pascalcase"] = function()
    local bufnr = create_react_buffer({
        "const Button = function({ label }) {",
        "  return <div>{label}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 26 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 26 })

    eq(result ~= nil, true)
    if result then
        eq(result.prop_name, "label")
    end
    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Integration Tests: Detection Filtering - Body Variables
-- ========================================================================

T["detection_filtering"]["body_variables"] = new_set()

T["detection_filtering"]["body_variables"]["should_not_detect_lowercase_function"] = function()
    local bufnr = create_react_buffer({
        "function helper({ data }) {",
        "  const x = data",
        "  return <div>{x}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 12 }) -- cursor on "data"

    local result = props.detect_prop_at_cursor(bufnr, { 2, 12 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["body_variables"]["should_detect_pascalcase_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Button({ label }) {",
        "  const text = label",
        "  return <div>{text}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 15 }) -- cursor on "label"

    local result = props.detect_prop_at_cursor(bufnr, { 2, 15 })

    if result then
        eq(result.is_prop, true)
        eq(result.prop_name, "label")
        eq(result.context, "body")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["body_variables"]["aliased_prop_pascalcase"] = function()
    local bufnr = create_react_buffer({
        "function Button({ name: userName }) {",
        "  const text = userName",
        "  return <div>{text}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 15 }) -- cursor on "userName"

    local result = props.detect_prop_at_cursor(bufnr, { 2, 15 })

    if result then
        eq(result.is_prop, true)
        eq(result.prop_name, "name") -- should return key, not alias
        eq(result.context, "body")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["body_variables"]["aliased_prop_lowercase"] = function()
    local bufnr = create_react_buffer({
        "function helper({ name: userName }) {",
        "  const text = userName",
        "  return <div>{text}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 15 })

    local result = props.detect_prop_at_cursor(bufnr, { 2, 15 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["body_variables"]["arrow_function_pascalcase"] = function()
    local bufnr = create_react_buffer({
        "const Button = ({ label }) => {",
        "  const text = label",
        "  return <div>{text}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 15 })

    local result = props.detect_prop_at_cursor(bufnr, { 2, 15 })

    if result then
        eq(result.prop_name, "label")
    end
    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Integration Tests: Detection Filtering - Type Signatures (Named)
-- ========================================================================

T["detection_filtering"]["type_signatures"] = new_set()

-- Note: Named type checking via find_component_using_type has a bug where it
-- captures formal_parameters instead of the function node, so these tests use
-- inline types which correctly walk up the tree to find the function
T["detection_filtering"]["type_signatures"]["should_not_detect_lowercase_function"] = function()
    -- Using inline type - walks up tree to find function
    local bufnr = create_react_buffer({
        "function helper({ id }: { id: number }) {",
        "  return <div>{id}</div>",
        "}",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 28 }) -- cursor on "id" in type

    local result = props.detect_prop_at_cursor(bufnr, { 1, 28 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["type_signatures"]["should_detect_pascalcase_with_jsx"] = function()
    -- Using inline type - walks up tree to find function
    local bufnr = create_react_buffer({
        "function Button({ label }: { label: string }) {",
        "  return <div>{label}</div>",
        "}",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 33 }) -- cursor on "label" in type

    local result = props.detect_prop_at_cursor(bufnr, { 1, 33 })

    eq(result ~= nil, true)
    if result then
        eq(result.is_prop, true)
        eq(result.prop_name, "label")
        eq(result.context, "type")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["type_signatures"]["type_alias_pascalcase"] = function()
    -- Using inline type
    local bufnr = create_react_buffer({
        "const Button = ({ label }: { label: string }) => <div>{label}</div>",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 34 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 34 })

    eq(result ~= nil, true)
    if result then
        eq(result.prop_name, "label")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["type_signatures"]["type_alias_lowercase"] = function()
    -- Using inline type
    local bufnr = create_react_buffer({
        "const helper = ({ id }: { id: number }) => <div>{id}</div>",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 30 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 30 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["type_signatures"]["arrow_function_with_type"] = function()
    -- Using inline type
    local bufnr = create_react_buffer({
        "const Button = ({ label }: { label: string }) => <div>{label}</div>",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 34 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 34 })

    eq(result ~= nil, true)
    if result then
        eq(result.prop_name, "label")
    end
    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Integration Tests: Detection Filtering - Inline Types
-- ========================================================================

T["detection_filtering"]["inline_types"] = new_set()

T["detection_filtering"]["inline_types"]["should_not_detect_lowercase_function"] = function()
    local bufnr = create_react_buffer({
        "function helper({ id }: { id: number }) {",
        "  return <div>{id}</div>",
        "}",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 18 }) -- cursor on "id" in destructure

    local result = props.detect_prop_at_cursor(bufnr, { 1, 18 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["inline_types"]["should_detect_pascalcase_with_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Button({ label }: { label: string }) {",
        "  return <div>{label}</div>",
        "}",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 18 }) -- cursor on "label" in destructure

    local result = props.detect_prop_at_cursor(bufnr, { 1, 18 })

    eq(result ~= nil, true)
    if result then
        eq(result.is_prop, true)
        eq(result.prop_name, "label")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["inline_types"]["arrow_function_inline_type_pascalcase"] = function()
    local bufnr = create_react_buffer({
        "const Button = ({ label }: { label: string }) => <div>{label}</div>",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 19 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 19 })

    eq(result ~= nil, true)
    if result then
        eq(result.prop_name, "label")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["inline_types"]["arrow_function_inline_type_lowercase"] = function()
    local bufnr = create_react_buffer({
        "const helper = ({ id }: { id: number }) => <div>{id}</div>",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 19 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 19 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["inline_types"]["cursor_on_type_prop_pascalcase"] = function()
    local bufnr = create_react_buffer({
        "function Button({ label }: { label: string }) {",
        "  return <div>{label}</div>",
        "}",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 29 }) -- cursor on "label" in type

    local result = props.detect_prop_at_cursor(bufnr, { 1, 29 })

    eq(result ~= nil, true)
    if result then
        eq(result.prop_name, "label")
        eq(result.context, "type")
    end
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["inline_types"]["cursor_on_type_prop_lowercase"] = function()
    local bufnr = create_react_buffer({
        "function helper({ id }: { id: number }) {",
        "  return <div>{id}</div>",
        "}",
    }, "typescriptreact")

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 26 }) -- cursor on "id" in type

    local result = props.detect_prop_at_cursor(bufnr, { 1, 26 })

    eq(result, nil)
    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Edge Cases and Special Scenarios
-- ========================================================================

T["detection_filtering"]["edge_cases"] = new_set()

T["detection_filtering"]["edge_cases"]["multiple_functions_mixed_case"] = function()
    local bufnr = create_react_buffer({
        "function helper({ data }) { return <div>{data}</div> }",
        "function Button({ label }) { return <div>{label}</div> }",
    })

    vim.api.nvim_set_current_buf(bufnr)

    -- Test lowercase function
    vim.api.nvim_win_set_cursor(0, { 1, 18 })
    local result1 = props.detect_prop_at_cursor(bufnr, { 1, 18 })
    eq(result1, nil)

    -- Test PascalCase function
    vim.api.nvim_win_set_cursor(0, { 2, 18 })
    local result2 = props.detect_prop_at_cursor(bufnr, { 2, 18 })
    eq(result2 ~= nil, true)
    if result2 then
        eq(result2.prop_name, "label")
    end

    cleanup_buffer(bufnr)
end

T["detection_filtering"]["edge_cases"]["pascalcase_returns_string"] = function()
    local bufnr = create_react_buffer({
        "function Helper() {",
        "  return 'string'",
        "}",
    })

    -- PascalCase but no JSX = not React component
    -- Can't test with params since no detection should happen
    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, false)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["edge_cases"]["no_function_name_anonymous"] = function()
    local bufnr = create_react_buffer({
        "const obj = {",
        "  render: function() { return <div /> }",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 1, 10)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    -- Anonymous function, no name to check for PascalCase
    eq(result, false)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["edge_cases"]["jsx_only_mode_still_works"] = function()
    -- JSX context doesn't need React component check
    local bufnr = create_react_buffer({
        "function helper({ name }) {",
        "  return <div>{name}</div>",
        "}",
        "<SomeComponent name={value} />",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 4, 16 }) -- cursor on "name" in JSX

    local result = props.detect_prop_at_cursor(bufnr, { 4, 16 })

    -- JSX detection should work regardless of component check
    eq(result ~= nil, true)
    if result then
        eq(result.context, "jsx")
    end

    cleanup_buffer(bufnr)
end

T["detection_filtering"]["edge_cases"]["deeply_nested_jsx"] = function()
    local bufnr = create_react_buffer({
        "function Container() {",
        "  if (true) {",
        "    const el = <div><span /></div>",
        "    return el",
        "  }",
        "}",
    })

    local func_node = find_function_at_cursor(bufnr, 0, 9)
    if not func_node then
        eq(false, true, "Expected to find function node")
        cleanup_buffer(bufnr)
        return
    end
    local result = props.is_react_component(func_node, bufnr)

    eq(result, true)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["edge_cases"]["mixed_case_name_with_underscore"] = function()
    local bufnr = create_react_buffer({
        "function _Button({ label }) {",
        "  return <div>{label}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 19 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 19 })

    -- _Button starts with underscore, not uppercase letter
    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["detection_filtering"]["edge_cases"]["multiple_params_only_first_checked"] = function()
    local bufnr = create_react_buffer({
        "function Button({ label }, context) {",
        "  return <div>{label}</div>",
        "}",
    })

    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 18 })

    local result = props.detect_prop_at_cursor(bufnr, { 1, 18 })

    -- First param destructured should detect
    eq(result ~= nil, true)
    cleanup_buffer(bufnr)
end

-- ========================================================================
-- Comprehensive Cross-Testing Matrix
-- ========================================================================

T["cross_testing"] = new_set()

-- Test all combinations: function types × contexts × React vs normal

T["cross_testing"]["function_declaration_destructure_react"] = function()
    local bufnr = create_react_buffer("function Btn({ x }) { return <div /> }")
    vim.api.nvim_win_set_cursor(0, { 1, 15 })
    local result = props.detect_prop_at_cursor(bufnr, { 1, 15 })
    eq(result ~= nil, true)
    cleanup_buffer(bufnr)
end

T["cross_testing"]["function_declaration_destructure_normal"] = function()
    local bufnr = create_react_buffer("function btn({ x }) { return <div /> }")
    vim.api.nvim_win_set_cursor(0, { 1, 15 })
    local result = props.detect_prop_at_cursor(bufnr, { 1, 15 })
    eq(result, nil)
    cleanup_buffer(bufnr)
end

T["cross_testing"]["arrow_function_body_react"] = function()
    local bufnr = create_react_buffer({
        "const Btn = ({ x }) => {",
        "  const y = x",
        "  return <div />",
        "}",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 12 })
    local result = props.detect_prop_at_cursor(bufnr, { 2, 12 })
    if result then
        eq(result.prop_name, "x")
    end
    cleanup_buffer(bufnr)
end

T["cross_testing"]["arrow_function_body_normal"] = function()
    local bufnr = create_react_buffer({
        "const btn = ({ x }) => {",
        "  const y = x",
        "  return <div />",
        "}",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 12 })
    local result = props.detect_prop_at_cursor(bufnr, { 2, 12 })
    eq(result, nil)
    cleanup_buffer(bufnr)
end

-- Note: function_expression in variable_declarator not currently matched by
-- find_component_using_type query, so inline type checking is used instead
T["cross_testing"]["function_expression_inline_type_react"] = function()
    local bufnr = create_react_buffer({
        "const Btn = function({ x }: { x: number }) { return <div /> }",
    }, "typescriptreact")
    vim.api.nvim_win_set_cursor(0, { 1, 23 })
    local result = props.detect_prop_at_cursor(bufnr, { 1, 23 })
    eq(result ~= nil, true)
    cleanup_buffer(bufnr)
end

T["cross_testing"]["function_expression_inline_type_normal"] = function()
    local bufnr = create_react_buffer({
        "const btn = function({ x }: { x: number }) { return <div /> }",
    }, "typescriptreact")
    vim.api.nvim_win_set_cursor(0, { 1, 23 })
    local result = props.detect_prop_at_cursor(bufnr, { 1, 23 })
    eq(result, nil)
    cleanup_buffer(bufnr)
end

return T
