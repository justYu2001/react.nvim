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

return T
