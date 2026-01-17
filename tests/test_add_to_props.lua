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

return T
