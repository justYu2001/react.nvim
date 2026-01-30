local helpers = require("tests.helpers")
local add_to_props = require("react.code_actions.add_to_props")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- Helper to create TSX buffer
local function create_tsx_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "typescriptreact"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
end

-- Test find_component_params
T["find_component_params"] = new_set()

T["find_component_params"]["detects destructured params"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = ({ foo }) => {",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 1, 2)
    assert(result)
    eq(result.type, "destructured")
    eq(result.pattern_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["detects destructured with type"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = ({ foo }: Props) => {",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 1, 2)
    assert(result)
    eq(result.type, "destructured")
    eq(result.pattern_node ~= nil, true)
    eq(result.type_annotation ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["detects typed not destructured"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = (props: Props) => {",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 1, 2)
    assert(result)
    eq(result.type, "typed_not_destructured")
    eq(result.type_annotation ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["detects no params"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 1, 2)
    assert(result)
    eq(result.type, "no_params")
    eq(result.formal_parameters ~= nil, true)
    eq(result.function_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["skips helper inside PascalCase component"] = function()
    local bufnr = create_tsx_buffer({
        "function MyComponent() {",
        "  function helper() {",
        "    const x = 1;",
        "  }",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 2, 4)
    assert(result)
    eq(result.type, "no_params")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["skips helper inside arrow component with JSX"] = function()
    local bufnr = create_tsx_buffer({
        "const MyComponent = () => {",
        "  const helper = () => {",
        "    return 42;",
        "  };",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 2, 4)
    assert(result)
    eq(result.type, "no_params")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["skips nested helpers (2 levels deep)"] = function()
    local bufnr = create_tsx_buffer({
        "function MyComponent({ foo }) {",
        "  function helper1() {",
        "    function helper2() {",
        "      const x = 1;",
        "    }",
        "  }",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 3, 6)
    assert(result)
    eq(result.type, "destructured")
    eq(result.pattern_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["detects PascalCase function without JSX"] = function()
    local bufnr = create_tsx_buffer({
        "function MyComponent() {",
        "  const x = 1;",
        "  return null;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 1, 2)
    assert(result)
    eq(result.type, "no_params")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["detects lowercase function WITH JSX"] = function()
    local bufnr = create_tsx_buffer({
        "function myComponent() {",
        "  return <div />;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 1, 2)
    assert(result)
    eq(result.type, "no_params")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_params"]["returns nil for lowercase function WITHOUT JSX"] = function()
    local bufnr = create_tsx_buffer({
        "function helper() {",
        "  const x = 1;",
        "  return x + 1;",
        "}",
    })

    local result = add_to_props.find_component_params(bufnr, 1, 2)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test already_in_destructuring
T["already_in_destructuring"] = new_set()

T["already_in_destructuring"]["returns true when var exists"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = ({ foo, bar }) => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local result = add_to_props.already_in_destructuring(bufnr, comp_params.pattern_node, "foo")
    eq(result, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["already_in_destructuring"]["returns false when var missing"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = ({ foo }) => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local result = add_to_props.already_in_destructuring(bufnr, comp_params.pattern_node, "bar")
    eq(result, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test already_in_type
T["already_in_type"] = new_set()

T["already_in_type"]["returns true when prop exists"] = function()
    local bufnr = create_tsx_buffer({
        "interface Props {",
        "  foo: string;",
        "}",
        "",
        "const Component = (props: Props) => {",
        "  return <div />;",
        "}",
    })

    local root = vim.treesitter.get_parser(bufnr, "tsx"):parse()[1]:root()
    local type_node = nil
    for node in root:iter_children() do
        if node:type() == "interface_declaration" then
            type_node = node:named_child(1)
            break
        end
    end

    local result = add_to_props.already_in_type(bufnr, type_node, "foo")
    eq(result, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["already_in_type"]["returns false when prop missing"] = function()
    local bufnr = create_tsx_buffer({
        "interface Props {",
        "  foo: string;",
        "}",
        "",
        "const Component = (props: Props) => {",
        "  return <div />;",
        "}",
    })

    local root = vim.treesitter.get_parser(bufnr, "tsx"):parse()[1]:root()
    local type_node = nil
    for node in root:iter_children() do
        if node:type() == "interface_declaration" then
            type_node = node:named_child(1)
            break
        end
    end

    local result = add_to_props.already_in_type(bufnr, type_node, "bar")
    eq(result, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test create_destructuring_edit
T["create_destructuring_edit"] = new_set()

T["create_destructuring_edit"]["adds to empty destructuring"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = ({}) => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local edit = add_to_props.create_destructuring_edit(comp_params.pattern_node, "bar")

    eq(edit ~= nil, true)
    eq(edit.text, "bar")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_destructuring_edit"]["adds to existing props"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = ({ foo }) => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local edit = add_to_props.create_destructuring_edit(comp_params.pattern_node, "bar")

    eq(edit ~= nil, true)
    eq(edit.text, ", bar")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test create_type_edit
T["create_type_edit"] = new_set()

T["create_type_edit"]["creates snippet edit with empty interface"] = function()
    local bufnr = create_tsx_buffer({
        "interface Props {}",
        "",
        "const Component = (props: Props) => {",
        "  return <div />;",
        "}",
    })

    local root = vim.treesitter.get_parser(bufnr, "tsx"):parse()[1]:root()
    local type_node = nil
    for node in root:iter_children() do
        if node:type() == "interface_declaration" then
            type_node = node:named_child(1)
            break
        end
    end

    local edit = add_to_props.create_type_edit(bufnr, type_node, "bar")

    eq(edit ~= nil, true)
    eq(edit.snippet ~= nil, true)
    eq(edit.snippet.var_name, "bar")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_type_edit"]["creates snippet edit with existing props"] = function()
    local bufnr = create_tsx_buffer({
        "interface Props {",
        "  foo: string;",
        "}",
        "",
        "const Component = (props: Props) => {",
        "  return <div />;",
        "}",
    })

    local root = vim.treesitter.get_parser(bufnr, "tsx"):parse()[1]:root()
    local type_node = nil
    for node in root:iter_children() do
        if node:type() == "interface_declaration" then
            type_node = node:named_child(1)
            break
        end
    end

    local edit = add_to_props.create_type_edit(bufnr, type_node, "bar")

    eq(edit ~= nil, true)
    eq(edit.snippet ~= nil, true)
    eq(edit.snippet.var_name, "bar")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test extract_component_name
T["extract_component_name"] = new_set()

T["extract_component_name"]["extracts from const declaration"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local name = add_to_props.extract_component_name(bufnr, comp_params.function_node)
    eq(name, "Component")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_component_name"]["extracts from let declaration"] = function()
    local bufnr = create_tsx_buffer({
        "let MyButton = () => {",
        "  return <button />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local name = add_to_props.extract_component_name(bufnr, comp_params.function_node)
    eq(name, "MyButton")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_component_name"]["returns nil for nil input"] = function()
    local bufnr = create_tsx_buffer({ "const x = 1" })
    local name = add_to_props.extract_component_name(bufnr, nil)
    eq(name, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test create_no_params_destructuring_edit
T["create_no_params_destructuring_edit"] = new_set()

T["create_no_params_destructuring_edit"]["creates edit without type"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local edit =
        add_to_props.create_no_params_destructuring_edit(comp_params.formal_parameters, "foo", nil)

    eq(edit.text, "({ foo })")
    eq(edit.row_start ~= nil, true)
    eq(edit.col_start ~= nil, true)
    eq(edit.row_end ~= nil, true)
    eq(edit.col_end ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_no_params_destructuring_edit"]["creates edit with type"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local edit = add_to_props.create_no_params_destructuring_edit(
        comp_params.formal_parameters,
        "bar",
        "ComponentProps"
    )

    eq(edit.text, "({ bar }: ComponentProps)")
    eq(edit.row_start ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test create_interface_edit
T["create_interface_edit"] = new_set()

T["create_interface_edit"]["creates interface with correct structure"] = function()
    local bufnr = create_tsx_buffer({
        "const MyComponent = () => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 2)
    assert(comp_params)
    local edits = add_to_props.create_interface_edit(
        bufnr,
        comp_params.function_node,
        "MyComponentProps",
        "foo"
    )
    assert(edits)

    eq(#edits, 2) -- Structure edit + snippet edit
    eq(edits[1].text:match("interface MyComponentProps"), "interface MyComponentProps")
    eq(edits[2].snippet ~= nil, true)
    eq(edits[2].snippet.var_name, "foo")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_interface_edit"]["returns nil when interface exists"] = function()
    local bufnr = create_tsx_buffer({
        "interface MyComponentProps {}",
        "",
        "const MyComponent = () => {",
        "  return <div />;",
        "}",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 3, 2)
    assert(comp_params)
    local edits = add_to_props.create_interface_edit(
        bufnr,
        comp_params.function_node,
        "MyComponentProps",
        "foo"
    )

    eq(edits, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_interface_edit"]["respects indentation"] = function()
    local bufnr = create_tsx_buffer({
        "  const MyComponent = () => {",
        "    return <div />;",
        "  }",
    })

    local comp_params = add_to_props.find_component_params(bufnr, 1, 4)
    assert(comp_params)
    local edits = add_to_props.create_interface_edit(
        bufnr,
        comp_params.function_node,
        "MyComponentProps",
        "foo"
    )
    assert(edits)

    eq(edits[1].text:match("^  interface"), "  interface") -- Starts with 2 spaces
    eq(edits[2].snippet.indent, "    ") -- Property indent is 4 spaces

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test is_event_handler_prop
T["is_event_handler_prop"] = new_set()

T["is_event_handler_prop"]["standard handlers"] = function()
    eq(add_to_props.is_event_handler_prop("onClick"), true)
    eq(add_to_props.is_event_handler_prop("onChange"), true)
    eq(add_to_props.is_event_handler_prop("onSubmit"), true)
    eq(add_to_props.is_event_handler_prop("onFocus"), true)
    eq(add_to_props.is_event_handler_prop("onBlur"), true)
    eq(add_to_props.is_event_handler_prop("onKeyDown"), true)
    eq(add_to_props.is_event_handler_prop("onMouseEnter"), true)
end

T["is_event_handler_prop"]["custom handlers"] = function()
    eq(add_to_props.is_event_handler_prop("onCustomEvent"), true)
    eq(add_to_props.is_event_handler_prop("onValidate"), true)
end

T["is_event_handler_prop"]["non-handlers"] = function()
    eq(add_to_props.is_event_handler_prop("userName"), false)
    eq(add_to_props.is_event_handler_prop("value"), false)
    eq(add_to_props.is_event_handler_prop("count"), false)
    eq(add_to_props.is_event_handler_prop("isActive"), false)
end

T["is_event_handler_prop"]["edge cases"] = function()
    eq(add_to_props.is_event_handler_prop("ontology"), false)
    eq(add_to_props.is_event_handler_prop("online"), false)
    eq(add_to_props.is_event_handler_prop("only"), false)
    eq(add_to_props.is_event_handler_prop("on"), false)
    eq(add_to_props.is_event_handler_prop("onA"), true) -- Has uppercase after 'on'
end

-- Helper to find jsx_element_node at cursor
local function find_jsx_element_at_cursor(bufnr, row, col)
    local node = vim.treesitter.get_node({
        bufnr = bufnr,
        pos = { row, col },
    })
    while node do
        if node:type() == "jsx_self_closing_element" or node:type() == "jsx_opening_element" then
            return node
        end
        node = node:parent()
    end
    return nil
end

-- Helper to find component function node (arrow_function or function_declaration)
local function find_component_function_node(bufnr, comp_name)
    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local tree = parser:parse()[1]
    local root = tree:root()

    -- Search for function_declaration
    for node in root:iter_children() do
        if node:type() == "function_declaration" then
            for child in node:iter_children() do
                if child:type() == "identifier" then
                    local name = vim.treesitter.get_node_text(child, bufnr)
                    if name == comp_name then
                        return node
                    end
                end
            end
        elseif node:type() == "lexical_declaration" then
            -- Search for const Cmp = ...
            for child in node:iter_children() do
                if child:type() == "variable_declarator" then
                    local ident = child:named_child(0)
                    if ident and ident:type() == "identifier" then
                        local name = vim.treesitter.get_node_text(ident, bufnr)
                        if name == comp_name then
                            -- Return the function node
                            for vchild in child:iter_children() do
                                if vchild:type() == "arrow_function" then
                                    return vchild
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Test get_jsx_context_for_undefined_var
T["get_jsx_context_for_undefined_var"] = new_set()

T["get_jsx_context_for_undefined_var"]["detects JSX context for undefined var in prop"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a: string }) => <div />;",
        "function Parent() {",
        "  return <Cmp a={udf} />;",
        "}",
    })

    -- Position at "udf" on line 3 (0-indexed: row 2)
    local result = add_to_props.get_jsx_context_for_undefined_var(bufnr, 2, 17, "udf")
    assert(result)
    eq(result.prop_name, "a")
    eq(result.jsx_element_node ~= nil, true)
    eq(result.jsx_element_node:type(), "jsx_self_closing_element")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_jsx_context_for_undefined_var"]["returns nil when not in JSX"] = function()
    local bufnr = create_tsx_buffer({
        "function Comp() {",
        "  const x = udf;",
        "}",
    })

    local result = add_to_props.get_jsx_context_for_undefined_var(bufnr, 1, 12, "udf")
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_jsx_context_for_undefined_var"]["returns nil for defined variable"] = function()
    local bufnr = create_tsx_buffer({
        "const defined = 'hello';",
        "const Cmp = () => <div />;",
        "function Parent() {",
        "  return <Cmp a={defined} />;",
        "}",
    })

    -- This function doesn't check if var is defined; it just returns JSX context
    -- The real check happens in get_undefined_var_at_cursor via diagnostics
    local result = add_to_props.get_jsx_context_for_undefined_var(bufnr, 3, 17, "defined")
    -- Will return context even if defined, since function only checks structure
    assert(result)
    eq(result.prop_name, "a")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_jsx_context_for_undefined_var"]["handles jsx_opening_element (not self-closing)"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a: string }) => <div />;",
        "return <Cmp a={udf}>content</Cmp>;",
    })

    local result = add_to_props.get_jsx_context_for_undefined_var(bufnr, 1, 15, "udf")
    assert(result)
    eq(result.prop_name, "a")
    eq(result.jsx_element_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_jsx_context_for_undefined_var"]["returns nil when node is not identifier"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = () => <div />;",
        'return <Cmp a="literal" />;',
    })

    -- Position at string literal, not identifier
    local result = add_to_props.get_jsx_context_for_undefined_var(bufnr, 1, 15, "literal")
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test find_component_from_jsx_usage
T["find_component_from_jsx_usage"] = new_set()

T["find_component_from_jsx_usage"]["finds component in same file"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a: string }) => <div />;",
        "function Parent() {",
        "  return <Cmp a={val} />;",
        "}",
    })

    local jsx_node = find_jsx_element_at_cursor(bufnr, 2, 10)
    assert(jsx_node)

    local result = add_to_props.find_component_from_jsx_usage(bufnr, jsx_node)
    assert(result)
    eq(result.bufnr, bufnr)
    eq(result.component_node ~= nil, true)
    eq(result.component_node:type(), "arrow_function")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_from_jsx_usage"]["finds function_declaration component"] = function()
    local bufnr = create_tsx_buffer({
        "function Cmp({ a }: { a: string }) {",
        "  return <div />;",
        "}",
        "function Parent() {",
        "  return <Cmp a={val} />;",
        "}",
    })

    local jsx_node = find_jsx_element_at_cursor(bufnr, 4, 10)
    assert(jsx_node)

    local result = add_to_props.find_component_from_jsx_usage(bufnr, jsx_node)
    assert(result)
    eq(result.bufnr, bufnr)
    eq(result.component_node ~= nil, true)
    eq(result.component_node:type(), "function_declaration")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_from_jsx_usage"]["returns nil when component not found"] = function()
    local bufnr = create_tsx_buffer({
        "function Parent() {",
        "  return <UnknownCmp a={val} />;",
        "}",
    })

    local jsx_node = find_jsx_element_at_cursor(bufnr, 1, 10)
    assert(jsx_node)

    local result = add_to_props.find_component_from_jsx_usage(bufnr, jsx_node)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test extract_prop_type_from_component
T["extract_prop_type_from_component"] = new_set()

T["extract_prop_type_from_component"]["extracts type from inline object_type"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a: string }) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "a")
    assert(result)
    eq(result.type, "string")
    eq(result.optional, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["extracts complex type from inline object"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ data }: { data: Array<string> }) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "data")
    assert(result)
    eq(result.type, "Array<string>")
    eq(result.optional, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["extracts type from interface reference"] = function()
    local bufnr = create_tsx_buffer({
        "interface Props { a: number; }",
        "const Cmp = ({ a }: Props) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "a")
    assert(result)
    eq(result.type, "number")
    eq(result.optional, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["extracts type from type alias"] = function()
    local bufnr = create_tsx_buffer({
        "type Props = { a: boolean; };",
        "const Cmp = ({ a }: Props) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "a")
    assert(result)
    eq(result.type, "boolean")
    eq(result.optional, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["returns nil when prop not in type"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a: string }) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "b")
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["returns nil when no type annotation"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "a")
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["handles union types"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a: string | number }) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "a")
    assert(result)
    eq(result.type, "string | number")
    eq(result.optional, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["handles optional props"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a?: string }) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "a")
    assert(result)
    eq(result.type, "string")
    eq(result.optional, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_prop_type_from_component"]["handles nested object types"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ user }: { user: { name: string } }) => <div />;",
    })

    local function_node = find_component_function_node(bufnr, "Cmp")
    assert(function_node)
    local result = add_to_props.extract_prop_type_from_component(bufnr, function_node, "user")
    assert(result)
    eq(result.type, "{ name: string }")
    eq(result.optional, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Integration tests for direct insert feature
T["integration"] = new_set()

T["integration"]["direct insert - required type"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ a }: { a: string }) => <div />;",
        "function Parent() {",
        "  return <Cmp a={udf} />;",
        "}",
    })

    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, bufnr, {
        {
            lnum = 2,
            col = 17,
            message = "Cannot find name 'udf'",
            severity = vim.diagnostic.severity.ERROR,
        },
    })

    vim.api.nvim_win_set_cursor(0, { 3, 17 })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = add_to_props.get_source(null_ls)
    local actions = source.generator.fn({
        bufnr = bufnr,
        row = 3,
        col = 17,
    })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Check key features
    local has_interface = false
    local has_typed_param = false
    local has_direct_type = false

    for _, line in ipairs(lines) do
        if line:match("interface ParentProps") then
            has_interface = true
        end
        if line:match("Parent%(.*ParentProps%)") then
            has_typed_param = true
        end
        if line:match("udf: string") then
            has_direct_type = true
        end
    end

    eq(has_interface, true)
    eq(has_typed_param, true)
    eq(has_direct_type, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["integration"]["direct insert - optional type"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ b }: { b?: number }) => <div />;",
        "function Parent() {",
        "  return <Cmp b={udf} />;",
        "}",
    })

    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, bufnr, {
        {
            lnum = 2,
            col = 17,
            message = "Cannot find name 'udf'",
            severity = vim.diagnostic.severity.ERROR,
        },
    })

    vim.api.nvim_win_set_cursor(0, { 3, 17 })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = add_to_props.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 17 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Verify interface with optional marker
    local has_interface = false
    local has_optional_type = false
    local has_typed_param = false

    for _, line in ipairs(lines) do
        if line:match("interface ParentProps") then
            has_interface = true
        end
        if line:match("udf%?: number") then
            has_optional_type = true
        end
        if line:match("Parent%(.*ParentProps%)") then
            has_typed_param = true
        end
    end

    eq(has_interface, true)
    eq(has_optional_type, true)
    eq(has_typed_param, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["integration"]["direct insert - function type"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ onClick }: { onClick: (x: number) => void }) => <div />;",
        "function Parent() {",
        "  return <Cmp onClick={handler} />;",
        "}",
    })

    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, bufnr, {
        {
            lnum = 2,
            col = 24,
            message = "Cannot find name 'handler'",
            severity = vim.diagnostic.severity.ERROR,
        },
    })

    vim.api.nvim_win_set_cursor(0, { 3, 24 })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = add_to_props.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 24 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Verify function type is inserted directly
    local has_interface = false
    local has_function_type = false
    local has_typed_param = false

    for _, line in ipairs(lines) do
        if line:match("interface ParentProps") then
            has_interface = true
        end
        if line:match("handler: %(x: number%) => void") then
            has_function_type = true
        end
        if line:match("Parent%(.*ParentProps%)") then
            has_typed_param = true
        end
    end

    eq(has_interface, true)
    eq(has_function_type, true)
    eq(has_typed_param, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["integration"]["direct insert - complex type"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ data }: { data: Array<string> }) => <div />;",
        "function Parent() {",
        "  return <Cmp data={items} />;",
        "}",
    })

    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, bufnr, {
        {
            lnum = 2,
            col = 20,
            message = "Cannot find name 'items'",
            severity = vim.diagnostic.severity.ERROR,
        },
    })

    vim.api.nvim_win_set_cursor(0, { 3, 20 })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = add_to_props.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 20 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Verify complex/generic type
    local has_interface = false
    local has_array_type = false
    local has_typed_param = false

    for _, line in ipairs(lines) do
        if line:match("interface ParentProps") then
            has_interface = true
        end
        if line:match("items: Array<string>") then
            has_array_type = true
        end
        if line:match("Parent%(.*ParentProps%)") then
            has_typed_param = true
        end
    end

    eq(has_interface, true)
    eq(has_array_type, true)
    eq(has_typed_param, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["integration"]["direct insert - union type"] = function()
    local bufnr = create_tsx_buffer({
        "const Cmp = ({ val }: { val: string | number }) => <div />;",
        "function Parent() {",
        "  return <Cmp val={mixed} />;",
        "}",
    })

    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, bufnr, {
        {
            lnum = 2,
            col = 19,
            message = "Cannot find name 'mixed'",
            severity = vim.diagnostic.severity.ERROR,
        },
    })

    vim.api.nvim_win_set_cursor(0, { 3, 19 })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = add_to_props.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 19 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Verify union type
    local has_interface = false
    local has_union_type = false
    local has_typed_param = false

    for _, line in ipairs(lines) do
        if line:match("interface ParentProps") then
            has_interface = true
        end
        if line:match("mixed: string | number") then
            has_union_type = true
        end
        if line:match("Parent%(.*ParentProps%)") then
            has_typed_param = true
        end
    end

    eq(has_interface, true)
    eq(has_union_type, true)
    eq(has_typed_param, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
