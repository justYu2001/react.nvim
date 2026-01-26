local helpers = require("tests.helpers")
local wrap_use_callback = require("react.code_actions.wrap_use_callback")

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

-- Test find_function_context
T["find_function_context"] = new_set()

T["find_function_context"]["detects inner function in component"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const handleClick = () => {",
        "    console.log('clicked');",
        "  };",
        "  return <div />;",
        "}",
    })

    local result = wrap_use_callback.find_function_context(bufnr, 2, 4)
    assert(result)
    eq(result.function_node ~= nil, true)
    eq(result.component_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_function_context"]["detects inner arrow function"] = function()
    local bufnr = create_tsx_buffer({
        "const MyComponent = () => {",
        "  const helper = () => 42;",
        "  return <div />;",
        "}",
    })

    local result = wrap_use_callback.find_function_context(bufnr, 1, 18)
    assert(result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_function_context"]["returns nil for lowercase function without JSX"] = function()
    local bufnr = create_tsx_buffer({
        "function helper() {",
        "  const inner = () => 1;",
        "}",
    })

    local result = wrap_use_callback.find_function_context(bufnr, 1, 2)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_function_context"]["returns nil when already wrapped"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const handleClick = useCallback(() => {",
        "    console.log('clicked');",
        "  }, []);",
        "  return <div />;",
        "}",
    })

    local result = wrap_use_callback.find_function_context(bufnr, 2, 4)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_function_context"]["works with PascalCase component"] = function()
    local bufnr = create_tsx_buffer({
        "function MyComponent() {",
        "  const handleClick = () => {};",
        "  return <div />;",
        "}",
    })

    local result = wrap_use_callback.find_function_context(bufnr, 1, 23)
    assert(result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_function_context"]["works in custom hook"] = function()
    local bufnr = create_tsx_buffer({
        "function useCustomHook() {",
        "  const helper = () => {};",
        "  return helper;",
        "}",
    })

    local result = wrap_use_callback.find_function_context(bufnr, 1, 18)
    assert(result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test find_function_from_jsx_handler
T["find_function_from_jsx_handler"] = new_set()

T["find_function_from_jsx_handler"]["detects handler in JSX"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const handleClick = () => {};",
        "  return <button onClick={handleClick} />;",
        "}",
    })

    local result = wrap_use_callback.find_function_from_jsx_handler(bufnr, 2, 26)
    assert(result)
    eq(result.function_node ~= nil, true)
    eq(result.component_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_function_from_jsx_handler"]["returns nil for non-handler prop"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const value = 'test';",
        "  return <input value={value} />;",
        "}",
    })

    local result = wrap_use_callback.find_function_from_jsx_handler(bufnr, 2, 24)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_function_from_jsx_handler"]["returns nil when already wrapped"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const handleClick = useCallback(() => {}, []);",
        "  return <button onClick={handleClick} />;",
        "}",
    })

    local result = wrap_use_callback.find_function_from_jsx_handler(bufnr, 2, 26)
    eq(result, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test extract_dependencies
T["extract_dependencies"] = new_set()

T["extract_dependencies"]["empty deps for no closure"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const handleClick = () => {",
        "    console.log('clicked');",
        "  };",
        "  return <div />;",
        "}",
    })

    -- Get function nodes manually
    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    -- Find component and inner function
    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end

        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)
    eq(#deps, 0)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_dependencies"]["includes state vars"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const [count, setCount] = useState(0);",
        "  const handleClick = () => {",
        "    setCount(count + 1);",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end

        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    -- Should include 'count' but NOT 'setCount'
    local has_count = false
    local has_setCount = false

    for _, dep in ipairs(deps) do
        if dep == "count" then
            has_count = true
        end
        if dep == "setCount" then
            has_setCount = true
        end
    end

    eq(has_count, true)
    eq(has_setCount, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_dependencies"]["excludes params and locals"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const external = 42;",
        "  const handleClick = (event) => {",
        "    const local = 1;",
        "    console.log(event, local, external);",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end

        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    -- Should only include 'external'
    local has_external = false
    local has_event = false
    local has_local = false

    for _, dep in ipairs(deps) do
        if dep == "external" then
            has_external = true
        end
        if dep == "event" then
            has_event = true
        end
        if dep == "local" then
            has_local = true
        end
    end

    eq(has_external, true)
    eq(has_event, false)
    eq(has_local, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_dependencies"]["includes only root for member expressions"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const obj = { method: () => {} };",
        "  const handleClick = () => {",
        "    obj.method();",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil
    local arrow_count = 0

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            arrow_count = arrow_count + 1
            if arrow_count == 1 then
                component_node = node
            elseif arrow_count == 3 then
                -- Skip the 2nd one (in object literal), get the 3rd
                function_node = node
            end
        end

        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    -- Should include 'obj' but not 'method'
    local has_obj = false
    local has_method = false

    for _, dep in ipairs(deps) do
        if dep == "obj" then
            has_obj = true
        end
        if dep == "method" then
            has_method = true
        end
    end

    eq(has_obj, true)
    eq(has_method, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["extract_dependencies"]["sorts alphabetically"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const zebra = 1;",
        "  const apple = 2;",
        "  const banana = 3;",
        "  const handleClick = () => {",
        "    console.log(zebra, apple, banana);",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end

        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    eq(deps[1], "apple")
    eq(deps[2], "banana")
    eq(deps[3], "zebra")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test collect_use_state_setters
T["collect_use_state_setters"] = new_set()

T["collect_use_state_setters"]["finds useState setters"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const [count, setCount] = useState(0);",
        "  const [items, setItems] = useState([]);",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    -- Find component node
    local component_node = nil

    local function find_component(node)
        if node:type() == "arrow_function" then
            component_node = node
            return
        end

        for child in node:iter_children() do
            find_component(child)
        end
    end

    find_component(root)

    local setters = wrap_use_callback.collect_use_state_setters(bufnr, component_node)

    eq(setters["setCount"], true)
    eq(setters["setItems"], true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["collect_use_state_setters"]["returns empty for no useState"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const value = 42;",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil

    local function find_component(node)
        if node:type() == "arrow_function" then
            component_node = node
            return
        end

        for child in node:iter_children() do
            find_component(child)
        end
    end

    find_component(root)

    local setters = wrap_use_callback.collect_use_state_setters(bufnr, component_node)

    local count = 0
    for _, _ in pairs(setters) do
        count = count + 1
    end

    eq(count, 0)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test has_use_callback_import
T["has_use_callback_import"] = new_set()

T["has_use_callback_import"]["detects existing import"] = function()
    local bufnr = create_tsx_buffer({
        "import { useCallback, useState } from 'react';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local result = wrap_use_callback.has_use_callback_import(bufnr)
    eq(result, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["has_use_callback_import"]["returns false when not imported"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState } from 'react';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local result = wrap_use_callback.has_use_callback_import(bufnr)
    eq(result, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["has_use_callback_import"]["returns false for no imports"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local result = wrap_use_callback.has_use_callback_import(bufnr)
    eq(result, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test create_import_edit
T["create_import_edit"] = new_set()

T["create_import_edit"]["returns nil when already imported"] = function()
    local bufnr = create_tsx_buffer({
        "import { useCallback } from 'react';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    eq(edit, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_import_edit"]["adds to existing named imports"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState } from 'react';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    eq(edit.text:match("useCallback"), "useCallback")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_import_edit"]["creates new import when none exists"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    eq(edit.row, 0)
    eq(
        edit.text:match("import { useCallback } from 'react'"),
        "import { useCallback } from 'react'"
    )

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_import_edit"]["respects use client directive"] = function()
    local bufnr = create_tsx_buffer({
        "'use client';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    eq(edit.row, 1) -- After 'use client'

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test create_wrapper_edit
T["create_wrapper_edit"] = new_set()

T["create_wrapper_edit"]["wraps function with deps"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const value = 42;",
        "  const handleClick = () => {",
        "    console.log(value);",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end

        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local context = {
        function_node = function_node,
        component_node = component_node,
    }

    local deps = { "value" }

    local edit = wrap_use_callback.create_wrapper_edit(bufnr, context, deps)
    assert(edit)
    eq(edit.text:match("useCallback"), "useCallback")
    eq(edit.text:match("%[value%]"), "[value]")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_wrapper_edit"]["wraps with empty deps"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const handleClick = () => {",
        "    console.log('clicked');",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end

        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local context = {
        function_node = function_node,
        component_node = component_node,
    }

    local deps = {}

    local edit = wrap_use_callback.create_wrapper_edit(bufnr, context, deps)
    assert(edit)
    eq(edit.text:match("%[%]"), "[]")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test generate_handler_name
T["generate_handler_name"] = new_set()

T["generate_handler_name"]["onClick on Button -> handleButtonClick"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <Button onClick={() => {}} />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    -- Find jsx_attribute
    local jsx_attr = nil
    local function find_attr(node)
        if node:type() == "jsx_attribute" then
            jsx_attr = node
            return
        end
        for child in node:iter_children() do
            find_attr(child)
        end
    end
    find_attr(root)

    local handler_name = wrap_use_callback.generate_handler_name(bufnr, jsx_attr)
    eq(handler_name, "handleButtonClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["onChange on input -> handleInputChange"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <input onChange={() => {}} />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local jsx_attr = nil
    local function find_attr(node)
        if node:type() == "jsx_attribute" then
            jsx_attr = node
            return
        end
        for child in node:iter_children() do
            find_attr(child)
        end
    end
    find_attr(root)

    local handler_name = wrap_use_callback.generate_handler_name(bufnr, jsx_attr)
    eq(handler_name, "handleInputChange")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["onSubmit on form -> handleFormSubmit"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <form onSubmit={() => {}} />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local jsx_attr = nil
    local function find_attr(node)
        if node:type() == "jsx_attribute" then
            jsx_attr = node
            return
        end
        for child in node:iter_children() do
            find_attr(child)
        end
    end
    find_attr(root)

    local handler_name = wrap_use_callback.generate_handler_name(bufnr, jsx_attr)
    eq(handler_name, "handleFormSubmit")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["onClick on div -> handleDivClick"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <div onClick={() => {}} />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local jsx_attr = nil
    local function find_attr(node)
        if node:type() == "jsx_attribute" then
            jsx_attr = node
            return
        end
        for child in node:iter_children() do
            find_attr(child)
        end
    end
    find_attr(root)

    local handler_name = wrap_use_callback.generate_handler_name(bufnr, jsx_attr)
    eq(handler_name, "handleDivClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["handles missing element name"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <><button onClick={() => {}} /></>;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local jsx_attr = nil
    local function find_attr(node)
        if node:type() == "jsx_attribute" then
            jsx_attr = node
            return
        end
        for child in node:iter_children() do
            find_attr(child)
        end
    end
    find_attr(root)

    local handler_name = wrap_use_callback.generate_handler_name(bufnr, jsx_attr)
    eq(handler_name, "handleButtonClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test find_return_statement edge cases
T["find_return_statement"] = new_set()

T["find_return_statement"]["finds last return in multiple returns"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  if (true) return <div>early</div>;",
        "  if (false) return <div>another</div>;",
        "  return <div>last</div>;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    -- Find component node
    local component_node = nil
    local function find_component(node)
        if node:type() == "arrow_function" then
            component_node = node
            return
        end
        for child in node:iter_children() do
            find_component(child)
        end
    end
    find_component(root)

    local return_node = wrap_use_callback.find_return_statement(component_node)
    assert(return_node)

    -- Verify it's the last return
    local return_text = vim.treesitter.get_node_text(return_node, bufnr)
    eq(return_text:match("last") ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_return_statement"]["handles early returns in conditionals"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  if (condition) {",
        "    return <div>early</div>;",
        "  }",
        "  return <div>final</div>;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function find_component(node)
        if node:type() == "arrow_function" then
            component_node = node
            return
        end
        for child in node:iter_children() do
            find_component(child)
        end
    end
    find_component(root)

    local return_node = wrap_use_callback.find_return_statement(component_node)
    assert(return_node)

    -- Should find the final return
    local return_text = vim.treesitter.get_node_text(return_node, bufnr)
    eq(return_text:match("final") ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_return_statement"]["returns nil for implicit return"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => <div />;",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function find_component(node)
        if node:type() == "arrow_function" then
            component_node = node
            return
        end
        for child in node:iter_children() do
            find_component(child)
        end
    end
    find_component(root)

    local return_node = wrap_use_callback.find_return_statement(component_node)
    eq(return_node, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_return_statement"]["returns nil for no return statement"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const x = 1;",
        "};",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function find_component(node)
        if node:type() == "arrow_function" then
            component_node = node
            return
        end
        for child in node:iter_children() do
            find_component(child)
        end
    end
    find_component(root)

    local return_node = wrap_use_callback.find_return_statement(component_node)
    eq(return_node, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test apply_edits
T["apply_edits"] = new_set()

T["apply_edits"]["applies single edit"] = function()
    local bufnr = create_tsx_buffer({
        "const x = 1;",
    })

    local edits = {
        {
            row_start = 0,
            col_start = 10,
            row_end = 0,
            col_end = 11,
            text = "42",
        },
    }

    wrap_use_callback.apply_edits(bufnr, edits)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "const x = 42;")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["apply_edits"]["applies multiple edits in order"] = function()
    local bufnr = create_tsx_buffer({
        "const x = 1;",
        "const y = 2;",
    })

    local edits = {
        {
            row = 0,
            col = 0,
            text = "import { x } from 'y';\n",
        },
        {
            row_start = 1,
            col_start = 10,
            row_end = 1,
            col_end = 11,
            text = "99",
        },
    }

    wrap_use_callback.apply_edits(bufnr, edits)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "import { x } from 'y';")
    eq(lines[2], "const x = 1;")
    eq(lines[3], "const y = 99;")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["apply_edits"]["applies edits bottom-to-top"] = function()
    local bufnr = create_tsx_buffer({
        "line 1",
        "line 2",
        "line 3",
    })

    -- Insert at line 2, then line 1 - should apply in reverse order
    local edits = {
        {
            row = 1,
            col = 0,
            text = "inserted 2\n",
        },
        {
            row = 0,
            col = 0,
            text = "inserted 1\n",
        },
    }

    wrap_use_callback.apply_edits(bufnr, edits)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "inserted 1")
    eq(lines[2], "line 1")
    eq(lines[3], "inserted 2")
    eq(lines[4], "line 2")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["apply_edits"]["applies edits right-to-left on same line"] = function()
    local bufnr = create_tsx_buffer({
        "const x = 1, y = 2;",
    })

    local edits = {
        {
            row_start = 0,
            col_start = 17,
            row_end = 0,
            col_end = 18,
            text = "99",
        },
        {
            row_start = 0,
            col_start = 10,
            row_end = 0,
            col_end = 11,
            text = "42",
        },
    }

    wrap_use_callback.apply_edits(bufnr, edits)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "const x = 42, y = 99;")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test inline JSX extraction
T["inline_jsx_extraction"] = new_set()

T["inline_jsx_extraction"]["extracts simple inline arrow function"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <button onClick={() => alert('hi')} />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 2, col = 26 })

    assert(actions and #actions > 0)
    eq(actions[1].title, "Extract to useCallback handler")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["inline_jsx_extraction"]["extracts inline function with dependencies"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const count = 1;",
        "  return <button onClick={() => console.log(count)} />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 26 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_declaration = false
    local has_replacement = false

    for _, line in ipairs(lines) do
        if line:match("handleButtonClick") and line:match("useCallback") then
            has_declaration = true
        end
        if line:match("onClick={handleButtonClick}") then
            has_replacement = true
        end
    end

    eq(has_declaration, true)
    eq(has_replacement, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["inline_jsx_extraction"]["generates proper handler name"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <input onChange={() => {}} />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 2, col = 26 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_handler = false

    for _, line in ipairs(lines) do
        if line:match("handleInputChange") then
            has_handler = true
        end
    end

    eq(has_handler, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["inline_jsx_extraction"]["verifies both edits applied"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  return <button onClick={() => {}} />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 2, col = 26 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Should have declaration + import
    local has_import = false
    local has_declaration = false
    local has_replacement = false

    for _, line in ipairs(lines) do
        if line:match("useCallback") and line:match("from 'react'") then
            has_import = true
        end
        if line:match("const handleButtonClick") and line:match("useCallback") then
            has_declaration = true
        end
        if line:match("onClick={handleButtonClick}") then
            has_replacement = true
        end
    end

    eq(has_import, true)
    eq(has_declaration, true)
    eq(has_replacement, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test function_declaration conversion
T["function_declaration_conversion"] = new_set()

T["function_declaration_conversion"]["converts with no params"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  function handleClick() {",
        "    console.log('clicked');",
        "  }",
        "  return <div />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 2, col = 12 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_const_arrow = false

    for _, line in ipairs(lines) do
        if line:match("const handleClick = useCallback") then
            has_const_arrow = true
        end
    end

    eq(has_const_arrow, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["function_declaration_conversion"]["converts with params"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  function handleClick(event, data) {",
        "    console.log(event, data);",
        "  }",
        "  return <div />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 2, col = 12 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_params = false

    for _, line in ipairs(lines) do
        if line:match("%(event, data%)") then
            has_params = true
        end
    end

    eq(has_params, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["function_declaration_conversion"]["converts with dependencies"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const count = 1;",
        "  function handleClick() {",
        "    console.log(count);",
        "  }",
        "  return <div />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 12 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_deps = false

    for _, line in ipairs(lines) do
        if line:match("%[count%]") then
            has_deps = true
        end
    end

    eq(has_deps, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["function_declaration_conversion"]["verifies const arrow format"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  function helper() {",
        "    return 42;",
        "  }",
        "  return <div />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 2, col = 12 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local converted = false

    for _, line in ipairs(lines) do
        if line:match("const helper = useCallback%(%(%) =>") then
            converted = true
        end
    end

    eq(converted, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test import edge cases
T["import_edge_cases"] = new_set()

T["import_edge_cases"]["adds to default import"] = function()
    local bufnr = create_tsx_buffer({
        "import React from 'react';",
        "",
        "const Component = () => {",
        "  const handleClick = () => {};",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    eq(edit.text, ", { useCallback }")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["import_edge_cases"]["adds at beginning of named imports"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState } from 'react';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    eq(edit.text, "useCallback, ")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["import_edge_cases"]["adds in middle of named imports"] = function()
    local bufnr = create_tsx_buffer({
        "import { memo, useState } from 'react';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    -- useCallback should be inserted after memo (alphabetically between memo and useState)
    eq(edit.text, ", useCallback")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["import_edge_cases"]["adds at end of named imports"] = function()
    local bufnr = create_tsx_buffer({
        "import { memo } from 'react';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    eq(edit.text, ", useCallback")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["import_edge_cases"]["respects use client directive"] = function()
    local bufnr = create_tsx_buffer({
        "'use client';",
        "",
        "const Component = () => {",
        "  return <div />;",
        "}",
    })

    local edit = wrap_use_callback.create_import_edit(bufnr)
    assert(edit)
    eq(edit.row, 1) -- Should be after 'use client'

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test dependency extraction edge cases
T["dependency_extraction_edge_cases"] = new_set()

T["dependency_extraction_edge_cases"]["destructured parameters"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const external = 42;",
        "  const handleClick = ({ value }) => {",
        "    console.log(value, external);",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end
        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    -- NOTE: Current implementation doesn't properly extract destructured params
    -- so 'value' gets included in deps (known limitation)
    local has_external = false
    local has_value = false

    for _, dep in ipairs(deps) do
        if dep == "external" then
            has_external = true
        end
        if dep == "value" then
            has_value = true
        end
    end

    eq(has_external, true)
    eq(has_value, true) -- Currently true due to limitation

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["dependency_extraction_edge_cases"]["nested function scopes"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const outer = 1;",
        "  const handleClick = () => {",
        "    const inner = 2;",
        "    const nested = () => {",
        "      console.log(outer, inner);",
        "    };",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil
    local arrow_count = 0

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            arrow_count = arrow_count + 1
            if arrow_count == 1 then
                component_node = node
            elseif arrow_count == 2 then
                function_node = node
            end
        end
        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    -- handleClick should only include outer, not inner (local)
    local has_outer = false
    local has_inner = false

    for _, dep in ipairs(deps) do
        if dep == "outer" then
            has_outer = true
        end
        if dep == "inner" then
            has_inner = true
        end
    end

    eq(has_outer, true)
    eq(has_inner, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["dependency_extraction_edge_cases"]["array destructuring in params"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const external = 42;",
        "  const handleClick = ([first, second]) => {",
        "    console.log(first, second, external);",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end
        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    -- NOTE: Current implementation doesn't extract array destructured params
    -- so they get included in deps (known limitation)
    local has_external = false
    local has_first = false
    local has_second = false

    for _, dep in ipairs(deps) do
        if dep == "external" then
            has_external = true
        end
        if dep == "first" then
            has_first = true
        end
        if dep == "second" then
            has_second = true
        end
    end

    eq(has_external, true)
    eq(has_first, true) -- Currently true due to limitation
    eq(has_second, true) -- Currently true due to limitation

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["dependency_extraction_edge_cases"]["mixed params locals external"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const alpha = 1;",
        "  const beta = 2;",
        "  const handleClick = (gamma) => {",
        "    const delta = 3;",
        "    console.log(alpha, beta, gamma, delta);",
        "  };",
        "  return <div />;",
        "}",
    })

    local parser = vim.treesitter.get_parser(bufnr, "tsx")
    local trees = parser:parse()
    local root = trees[1]:root()

    local component_node = nil
    local function_node = nil

    local function find_nodes(node)
        if node:type() == "arrow_function" then
            if not component_node then
                component_node = node
            elseif not function_node then
                function_node = node
            end
        end
        for child in node:iter_children() do
            find_nodes(child)
        end
    end

    find_nodes(root)

    local deps = wrap_use_callback.extract_dependencies(bufnr, function_node, component_node)

    -- Should only include alpha and beta (sorted)
    eq(#deps, 2)
    eq(deps[1], "alpha")
    eq(deps[2], "beta")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test end-to-end integration
T["integration"] = new_set()

T["integration"]["invoke on inner function completes transformation"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const value = 42;",
        "  const handleClick = () => {",
        "    console.log(value);",
        "  };",
        "  return <div />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 10 })

    assert(actions and #actions > 0)
    eq(actions[1].title, "Wrap with useCallback")

    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_import = false
    local has_wrapper = false
    local has_deps = false

    for _, line in ipairs(lines) do
        if line:match("useCallback") and line:match("from 'react'") then
            has_import = true
        end
        if line:match("useCallback") then
            has_wrapper = true
        end
        if line:match("%[value%]") then
            has_deps = true
        end
    end

    eq(has_import, true)
    eq(has_wrapper, true)
    eq(has_deps, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["integration"]["invoke on JSX handler applies wrapper"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const handleClick = () => {",
        "    console.log('clicked');",
        "  };",
        "  return <button onClick={handleClick} />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    -- Row 5 is the return statement with onClick={handleClick}
    local actions = source.generator.fn({ bufnr = bufnr, row = 5, col = 26 })

    assert(actions and #actions > 0)
    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_wrapper = false

    for _, line in ipairs(lines) do
        if line:match("useCallback") then
            has_wrapper = true
        end
    end

    eq(has_wrapper, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["integration"]["invoke on inline JSX extracts and wraps"] = function()
    local bufnr = create_tsx_buffer({
        "const Component = () => {",
        "  const count = 1;",
        "  return <button onClick={() => console.log(count)} />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 3, col = 26 })

    assert(actions and #actions > 0)
    eq(actions[1].title, "Extract to useCallback handler")

    actions[1].action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local has_handler = false
    local has_replacement = false

    for _, line in ipairs(lines) do
        if line:match("const handleButtonClick") and line:match("useCallback") then
            has_handler = true
        end
        if line:match("onClick={handleButtonClick}") then
            has_replacement = true
        end
    end

    eq(has_handler, true)
    eq(has_replacement, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["integration"]["no action when already wrapped"] = function()
    local bufnr = create_tsx_buffer({
        "import { useCallback } from 'react';",
        "",
        "const Component = () => {",
        "  const handleClick = useCallback(() => {",
        "    console.log('clicked');",
        "  }, []);",
        "  return <button onClick={handleClick} />;",
        "}",
    })

    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_use_callback.get_source(null_ls)
    local actions = source.generator.fn({ bufnr = bufnr, row = 4, col = 10 })

    eq(actions, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
