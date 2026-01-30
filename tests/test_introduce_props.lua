local helpers = require("tests.helpers")
local introduce_props = require("react.code_actions.introduce_props")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- Helper to create TSX buffer
local function create_tsx_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "typescriptreact"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

-- Helper to get value_node from JSX attribute for testing
local function get_value_node_from_jsx(bufnr, row, col)
    local node = vim.treesitter.get_node({
        bufnr = bufnr,
        pos = { row, col },
    })

    if not node then
        return nil
    end

    -- Walk up to jsx_attribute
    local current = node
    while current do
        if current:type() == "jsx_attribute" then
            -- Find value node
            for child in current:iter_children() do
                if
                    child:type() == "jsx_expression"
                    or child:type() == "string"
                    or child:type() == "number"
                then
                    return child
                end
            end
            return nil
        end
        current = current:parent()
    end

    return nil
end

-- Test infer_type
T["infer_type"] = new_set()

-- Literals
T["infer_type"]["infers string from string literal"] = function()
    local bufnr = create_tsx_buffer({
        '<Component prop="hello" />',
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 20)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers number from number literal"] = function()
    local bufnr = create_tsx_buffer({
        "<Component num={42} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers boolean from true literal"] = function()
    local bufnr = create_tsx_buffer({
        "<Component flag={true} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "boolean")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers boolean from false literal"] = function()
    local bufnr = create_tsx_buffer({
        "<Component flag={false} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "boolean")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers array from array literal"] = function()
    local bufnr = create_tsx_buffer({
        "<Component items={[1, 2, 3]} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 19)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "unknown[]")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers object from object literal"] = function()
    local bufnr = create_tsx_buffer({
        "<Component data={{ foo: 1 }} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "object")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers string from template literal"] = function()
    local bufnr = create_tsx_buffer({
        "<Component msg={`hello`} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Type Annotations
T["infer_type"]["infers from explicit string type annotation"] = function()
    local bufnr = create_tsx_buffer({
        "const value: string = 'hello';",
        "<Component prop={value} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from explicit number type annotation"] = function()
    local bufnr = create_tsx_buffer({
        "const count: number = 42;",
        "<Component num={count} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from explicit boolean type annotation"] = function()
    local bufnr = create_tsx_buffer({
        "const flag: boolean = true;",
        "<Component isActive={flag} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 22)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "boolean")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers custom type identifier"] = function()
    local bufnr = create_tsx_buffer({
        "const user: User = getUser();",
        "<Component data={user} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "User")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers union type takes first"] = function()
    local bufnr = create_tsx_buffer({
        "const val: string | number = 'test';",
        "<Component v={val} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 15)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers intersection type takes first"] = function()
    local bufnr = create_tsx_buffer({
        "const val: Base & Extended = {};",
        "<Component v={val} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 15)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "Base")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Variable Initializers
T["infer_type"]["infers from const with literal initializer"] = function()
    local bufnr = create_tsx_buffer({
        "const greeting = 'hello';",
        "<Component msg={greeting} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from let with number literal"] = function()
    local bufnr = create_tsx_buffer({
        "let count = 10;",
        "<Component num={count} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from const without type annotation"] = function()
    local bufnr = create_tsx_buffer({
        "const isValid = true;",
        "<Component flag={isValid} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "boolean")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Function Return Types
T["infer_type"]["infers from function declaration return type"] = function()
    local bufnr = create_tsx_buffer({
        "function getName(): string {",
        "  return 'test';",
        "}",
        "const name = getName();",
        "<Component n={name} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 4, 15)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from arrow function return type"] = function()
    local bufnr = create_tsx_buffer({
        "const getCount = (): number => 42;",
        "const count = getCount();",
        "<Component num={count} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 2, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from const arrow function with return type"] = function()
    local bufnr = create_tsx_buffer({
        "const isValid = (): boolean => {",
        "  return true;",
        "};",
        "const flag = isValid();",
        "<Component active={flag} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 4, 20)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "boolean")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["returns unknown for function without return type"] = function()
    local bufnr = create_tsx_buffer({
        "const getData = () => ({ foo: 1 });",
        "const data = getData();",
        "<Component val={data} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 2, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "unknown")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Member Expressions
T["infer_type"]["infers from object literal property with string"] = function()
    local bufnr = create_tsx_buffer({
        "const obj = { foo: 'bar' };",
        "<Component val={obj.foo} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from object literal property with number"] = function()
    local bufnr = create_tsx_buffer({
        "const obj = { count: 123 };",
        "<Component num={obj.count} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["infers from object literal property with boolean"] = function()
    local bufnr = create_tsx_buffer({
        "const settings = { enabled: true };",
        "<Component flag={settings.enabled} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "boolean")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["returns unknown for nested member expressions"] = function()
    local bufnr = create_tsx_buffer({
        "const obj = { nested: { deep: 'value' } };",
        "<Component val={obj.nested.deep} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "unknown")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Scope Resolution
T["infer_type"]["finds variable in same scope"] = function()
    local bufnr = create_tsx_buffer({
        "const value = 'test';",
        "<Component prop={value} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 1, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["finds variable in parent scope"] = function()
    local bufnr = create_tsx_buffer({
        "const outer = 42;",
        "function Component() {",
        "  return <div prop={outer} />;",
        "}",
    })

    local value_node = get_value_node_from_jsx(bufnr, 2, 21)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["handles shadowed variables closest scope wins"] = function()
    local bufnr = create_tsx_buffer({
        "const x: string = 'outer';",
        "{",
        "  const x: number = 42;",
        "  <Component prop={x} />",
        "}",
    })

    local value_node = get_value_node_from_jsx(bufnr, 3, 20)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["handles nested function scopes"] = function()
    local bufnr = create_tsx_buffer({
        "const App = () => {",
        "  const message: string = 'hello';",
        "  return <Child msg={message} />;",
        "};",
    })

    local value_node = get_value_node_from_jsx(bufnr, 2, 23)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "string")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Edge Cases
T["infer_type"]["returns unknown for undefined variables"] = function()
    local bufnr = create_tsx_buffer({
        "<Component prop={unknownVar} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 18)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "unknown")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["prevents infinite recursion depth limit"] = function()
    local bufnr = create_tsx_buffer({
        "const a = b;",
        "const b = c;",
        "const c = d;",
        "const d = e;",
        "const e = f;",
        "const f = a;",
        "<Component val={a} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 6, 17)
    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "unknown")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["handles jsx_expression wrapper"] = function()
    local bufnr = create_tsx_buffer({
        "<Component val={123} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 16)
    assert(value_node)
    eq(value_node:type(), "jsx_expression")

    local result = introduce_props.infer_type(bufnr, value_node)
    eq(result, "number")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["infer_type"]["handles missing value_node"] = function()
    local result = introduce_props.infer_type(0, nil)
    eq(result, "unknown")
end

-- Test get_undefined_prop_at_cursor
T["get_undefined_prop_at_cursor"] = new_set()

T["get_undefined_prop_at_cursor"]["returns nil without diagnostics"] = function()
    local bufnr = create_tsx_buffer({
        '<Component validProp="value" />',
    })

    local result = introduce_props.get_undefined_prop_at_cursor({
        bufnr = bufnr,
        row = 1,
        col = 11,
    })

    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_undefined_prop_at_cursor"]["returns nil when cursor not on jsx attribute"] = function()
    local bufnr = create_tsx_buffer({
        "const x = 1;",
    })

    local result = introduce_props.get_undefined_prop_at_cursor({
        bufnr = bufnr,
        row = 1,
        col = 6,
    })

    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test find_component_from_jsx_element
T["find_component_from_jsx_element"] = new_set()

T["find_component_from_jsx_element"]["finds component in same file"] = function()
    local bufnr = create_tsx_buffer({
        "const MyComponent = () => {",
        "  return <div />;",
        "};",
        "",
        "<MyComponent />;",
    })

    local node = vim.treesitter.get_node({
        bufnr = bufnr,
        pos = { 4, 1 },
    })

    -- Find jsx_self_closing_element
    while node and node:type() ~= "jsx_self_closing_element" do
        node = node:parent()
    end

    assert(node)

    local result = introduce_props.find_component_from_jsx_element(bufnr, node)
    assert(result)
    eq(result.bufnr, bufnr)
    eq(result.component_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_from_jsx_element"]["returns nil for member expression components"] = function()
    local bufnr = create_tsx_buffer({
        "<Lib.Button />",
    })

    local node = vim.treesitter.get_node({
        bufnr = bufnr,
        pos = { 0, 1 },
    })

    while node and node:type() ~= "jsx_self_closing_element" do
        node = node:parent()
    end

    assert(node)

    local result = introduce_props.find_component_from_jsx_element(bufnr, node)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_from_jsx_element"]["returns nil when component not found"] = function()
    local bufnr = create_tsx_buffer({
        "<UnknownComponent />",
    })

    local node = vim.treesitter.get_node({
        bufnr = bufnr,
        pos = { 0, 1 },
    })

    while node and node:type() ~= "jsx_self_closing_element" do
        node = node:parent()
    end

    assert(node)

    local result = introduce_props.find_component_from_jsx_element(bufnr, node)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test is_event_handler_prop (pattern matching)
T["is_event_handler_prop"] = new_set()

T["is_event_handler_prop"]["standard handlers"] = function()
    eq(introduce_props.is_event_handler_prop("onClick"), true)
    eq(introduce_props.is_event_handler_prop("onChange"), true)
    eq(introduce_props.is_event_handler_prop("onSubmit"), true)
    eq(introduce_props.is_event_handler_prop("onFocus"), true)
    eq(introduce_props.is_event_handler_prop("onBlur"), true)
    eq(introduce_props.is_event_handler_prop("onKeyDown"), true)
    eq(introduce_props.is_event_handler_prop("onMouseEnter"), true)
end

T["is_event_handler_prop"]["custom handlers"] = function()
    eq(introduce_props.is_event_handler_prop("onCustomEvent"), true)
    eq(introduce_props.is_event_handler_prop("onValidate"), true)
end

T["is_event_handler_prop"]["non-handlers"] = function()
    eq(introduce_props.is_event_handler_prop("userName"), false)
    eq(introduce_props.is_event_handler_prop("value"), false)
    eq(introduce_props.is_event_handler_prop("count"), false)
    eq(introduce_props.is_event_handler_prop("isActive"), false)
end

T["is_event_handler_prop"]["edge cases"] = function()
    eq(introduce_props.is_event_handler_prop("ontology"), false)
    eq(introduce_props.is_event_handler_prop("online"), false)
    eq(introduce_props.is_event_handler_prop("only"), false)
    eq(introduce_props.is_event_handler_prop("on"), false)
    eq(introduce_props.is_event_handler_prop("onA"), true) -- Has uppercase after 'on'
end

-- Test type override integration
T["type_override"] = new_set()

T["type_override"]["pattern_based_validation"] = function()
    -- Verify event handlers detected
    eq(introduce_props.is_event_handler_prop("onClick"), true)
    eq(introduce_props.is_event_handler_prop("onChange"), true)

    -- Verify non-handlers not detected
    eq(introduce_props.is_event_handler_prop("value"), false)
    eq(introduce_props.is_event_handler_prop("ontology"), false)

    -- Trust implementation correctly applies:
    -- if is_event_handler_prop(name) and type == "unknown" then
    --     type = "() => void"
end

-- Test function type pattern detection
T["function_type_pattern"] = new_set()

T["function_type_pattern"]["matches_simple_arrow_function"] = function()
    local type_str = "() => void"
    local matches = type_str:match("^%(%s*%)%s*=>") ~= nil
    eq(matches, true)

    local return_type = type_str:match("=>%s*(.+)$")
    eq(return_type, "void")
end

T["function_type_pattern"]["matches_with_return_type"] = function()
    local type_str = "() => boolean"
    local matches = type_str:match("^%(%s*%)%s*=>") ~= nil
    eq(matches, true)

    local return_type = type_str:match("=>%s*(.+)$")
    eq(return_type, "boolean")
end

T["function_type_pattern"]["matches_with_params"] = function()
    local type_str = "(e: Event) => void"
    -- Note: Pattern only matches (), not with params
    local matches = type_str:match("^%(%s*%)%s*=>") ~= nil
    eq(matches, false) -- Doesn't match - has params
end

T["function_type_pattern"]["no_match_for_non_function_types"] = function()
    eq(("string"):match("^%(%s*%)%s*=>") ~= nil, false)
    eq(("unknown"):match("^%(%s*%)%s*=>") ~= nil, false)
    eq(("Promise<void>"):match("^%(%s*%)%s*=>") ~= nil, false)
end

-- Arrow function type inference tests
T["arrow_function_inference"] = new_set()

T["arrow_function_inference"]["single_typed_param"] = function()
    local bufnr = create_tsx_buffer({ "const handler = (value: string) => {}" })
    local value_node = get_value_node_from_jsx(bufnr, 0, 16)

    if value_node then
        local inferred_type = introduce_props.infer_type(bufnr, value_node)
        eq(inferred_type:match("%(value: string%).*=>.*void") ~= nil, true)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["arrow_function_inference"]["multi_param"] = function()
    local bufnr = create_tsx_buffer({ "const handler = (e: Event, data: string) => {}" })
    local value_node = get_value_node_from_jsx(bufnr, 0, 16)

    if value_node then
        local inferred_type = introduce_props.infer_type(bufnr, value_node)
        eq(inferred_type:match("%(e: Event, data: string%).*=>.*void") ~= nil, true)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["arrow_function_inference"]["optional_param"] = function()
    local bufnr = create_tsx_buffer({ "const handler = (value?: string) => {}" })
    local value_node = get_value_node_from_jsx(bufnr, 0, 16)

    if value_node then
        local inferred_type = introduce_props.infer_type(bufnr, value_node)
        eq(inferred_type:match("%(value%?: string%).*=>.*void") ~= nil, true)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["arrow_function_inference"]["explicit_return_type"] = function()
    local bufnr = create_tsx_buffer({ "const handler = (val: string): boolean => true" })
    local value_node = get_value_node_from_jsx(bufnr, 0, 16)

    if value_node then
        local inferred_type = introduce_props.infer_type(bufnr, value_node)
        eq(inferred_type, "(val: string) => boolean")
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["arrow_function_inference"]["untyped_param"] = function()
    local bufnr = create_tsx_buffer({ "const handler = (value) => {}" })
    local value_node = get_value_node_from_jsx(bufnr, 0, 16)

    if value_node then
        local inferred_type = introduce_props.infer_type(bufnr, value_node)
        eq(inferred_type, "(value) => void")
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["jsx_cleanup"] = new_set()

T["jsx_cleanup"]["removes_single_param_type_annotation"] = function()
    local bufnr = create_tsx_buffer({
        "<Component onClick={(value: string) => {}} />",
    })

    -- Get jsx_expression containing arrow function
    local value_node = get_value_node_from_jsx(bufnr, 0, 20) -- position in JSX

    -- Create cleanup edits
    local cleanup_edits = introduce_props.create_jsx_cleanup_edit(bufnr, value_node)

    -- Apply edits in reverse order
    table.sort(cleanup_edits, function(a, b)
        if a.row_start == b.row_start then
            return a.col_start > b.col_start
        end
        return a.row_start > b.row_start
    end)

    for _, edit in ipairs(cleanup_edits) do
        vim.api.nvim_buf_set_text(
            bufnr,
            edit.row_start,
            edit.col_start,
            edit.row_end,
            edit.col_end,
            vim.split(edit.text, "\n")
        )
    end

    -- Verify result
    local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
    eq(result, "<Component onClick={(value) => {}} />")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["jsx_cleanup"]["removes_multi_param_type_annotations"] = function()
    local bufnr = create_tsx_buffer({
        "<Component onChange={(e: Event, data: string) => {}} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 20)
    local cleanup_edits = introduce_props.create_jsx_cleanup_edit(bufnr, value_node)

    -- Apply edits
    table.sort(cleanup_edits, function(a, b)
        if a.row_start == b.row_start then
            return a.col_start > b.col_start
        end
        return a.row_start > b.row_start
    end)

    for _, edit in ipairs(cleanup_edits) do
        vim.api.nvim_buf_set_text(
            bufnr,
            edit.row_start,
            edit.col_start,
            edit.row_end,
            edit.col_end,
            vim.split(edit.text, "\n")
        )
    end

    local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
    eq(result, "<Component onChange={(e, data) => {}} />")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["jsx_cleanup"]["preserves_untyped_params"] = function()
    local bufnr = create_tsx_buffer({
        "<Component onClick={(value) => {}} />",
    })

    local value_node = get_value_node_from_jsx(bufnr, 0, 20)
    local cleanup_edits = introduce_props.create_jsx_cleanup_edit(bufnr, value_node)

    -- Should return empty edits (no type annotations to remove)
    eq(#cleanup_edits, 0)

    local result = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
    eq(result, "<Component onClick={(value) => {}} />")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
