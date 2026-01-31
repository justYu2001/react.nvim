local helpers = require("tests.helpers")
local generate_event_handler = require("react.code_actions.generate_event_handler")

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

-- Helper to set diagnostic
local function set_diagnostic(bufnr, row, col, message)
    local ns = vim.api.nvim_create_namespace("test_diagnostics")
    vim.diagnostic.set(ns, bufnr, {
        {
            lnum = row - 1, -- 0-indexed
            col = col,
            message = message,
            severity = vim.diagnostic.severity.ERROR,
        },
    })
    return ns
end

-- Test detect_event_handler_context
T["detect_event_handler_context"] = new_set()

T["detect_event_handler_context"]["detects empty handler onClick={}"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button onClick={}>Click</button>;",
        "}",
    })

    local context = generate_event_handler.detect_event_handler_context({
        bufnr = bufnr,
        row = 2,
        col = 25, -- Position in onClick
    })

    assert(context)
    eq(context.type, "empty")
    eq(context.attr_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_event_handler_context"]["detects undefined handler with diagnostic"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button onClick={handleClick}>Click</button>;",
        "}",
    })

    set_diagnostic(bufnr, 2, 27, "Cannot find name 'handleClick'")

    local context = generate_event_handler.detect_event_handler_context({
        bufnr = bufnr,
        row = 2,
        col = 27,
    })

    assert(context)
    eq(context.type, "undefined")
    eq(context.handler_name, "handleClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_event_handler_context"]["detects undefined handler with eslint diagnostic"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button onClick={handleClick}>Click</button>;",
        "}",
    })

    set_diagnostic(bufnr, 2, 27, "'handleClick' is not defined")

    local context = generate_event_handler.detect_event_handler_context({
        bufnr = bufnr,
        row = 2,
        col = 27,
    })

    assert(context)
    eq(context.type, "undefined")
    eq(context.handler_name, "handleClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_event_handler_context"]["detects undefined handler with translated error"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button onClick={handleClick}>Click</button>;",
        "}",
    })

    set_diagnostic(bufnr, 2, 27, "I can't find the variable you're trying to access.")

    local context = generate_event_handler.detect_event_handler_context({
        bufnr = bufnr,
        row = 2,
        col = 27,
    })

    assert(context)
    eq(context.type, "undefined")
    eq(context.handler_name, "handleClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_event_handler_context"]["filters non-event handlers"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button className={}>Click</button>;",
        "}",
    })

    local context = generate_event_handler.detect_event_handler_context({
        bufnr = bufnr,
        row = 2,
        col = 25,
    })

    eq(context, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_event_handler_context"]["returns nil when not in JSX context"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const x = 1;",
        "  return <button>Click</button>;",
        "}",
    })

    local context = generate_event_handler.detect_event_handler_context({
        bufnr = bufnr,
        row = 2,
        col = 10,
    })

    eq(context, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_event_handler_context"]["returns nil for defined handlers"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const handleClick = () => {};",
        "  return <button onClick={handleClick}>Click</button>;",
        "}",
    })

    local context = generate_event_handler.detect_event_handler_context({
        bufnr = bufnr,
        row = 3,
        col = 27,
    })

    eq(context, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_event_handler_context"]["detects various event types"] = function()
    local events = { "onClick", "onChange", "onSubmit", "onKeyDown", "onFocus", "onBlur" }

    for _, event in ipairs(events) do
        local bufnr = create_tsx_buffer({
            "function App() {",
            string.format("  return <button %s={}>Click</button>;", event),
            "}",
        })

        local context = generate_event_handler.detect_event_handler_context({
            bufnr = bufnr,
            row = 2,
            col = 25,
        })

        assert(context)
        eq(context.type, "empty")

        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

-- Test find_component_scope
T["find_component_scope"] = new_set()

T["find_component_scope"]["finds component with JSX return"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)

    assert(component)
    eq(component ~= nil, true)
    eq(component:type(), "function_declaration")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_scope"]["finds PascalCase component without JSX"] = function()
    local bufnr = create_tsx_buffer({
        "function MyComponent() {",
        "  return null;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)

    eq(component ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_scope"]["finds nested component"] = function()
    local bufnr = create_tsx_buffer({
        "function Outer() {",
        "  function Inner() {",
        "    return <div />;",
        "  }",
        "  return <Inner />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 2, 5)

    assert(component)
    eq(component ~= nil, true)
    eq(component:type(), "function_declaration")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_scope"]["returns nil for non-component function"] = function()
    local bufnr = create_tsx_buffer({
        "function helper() {",
        "  const x = 1;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)

    eq(component, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_scope"]["finds component with arrow function"] = function()
    local bufnr = create_tsx_buffer({
        "const App = () => {",
        "  return <div />;",
        "};",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)

    assert(component)
    eq(component ~= nil, true)
    eq(component:type(), "arrow_function")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_component_scope"]["finds component with function declaration"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)

    assert(component)
    eq(component ~= nil, true)
    eq(component:type(), "function_declaration")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test generate_handler_name
T["generate_handler_name"] = new_set()

T["generate_handler_name"]["generates handleButtonClick for button onClick"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button>Click</button>;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local name = generate_event_handler.generate_handler_name("button", "Click", bufnr, component)

    eq(name, "handleButtonClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["generates handleInputChange for input onChange"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <input />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local name = generate_event_handler.generate_handler_name("input", "Change", bufnr, component)

    eq(name, "handleInputChange")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["capitalizes HTML element names"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local name = generate_event_handler.generate_handler_name("div", "Click", bufnr, component)

    eq(name, "handleDivClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["handles already capitalized custom components"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <MyButton />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local name = generate_event_handler.generate_handler_name("MyButton", "Click", bufnr, component)

    eq(name, "handleMyButtonClick")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["adds suffix for name conflicts"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const handleButtonClick = () => {};",
        "  return <button>Click</button>;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local name = generate_event_handler.generate_handler_name("button", "Click", bufnr, component)

    eq(name, "handleButtonClick2")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["handles multiple conflicts"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const handleButtonClick = () => {};",
        "  const handleButtonClick2 = () => {};",
        "  const handleButtonClick3 = () => {};",
        "  return <button>Click</button>;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local name = generate_event_handler.generate_handler_name("button", "Click", bufnr, component)

    eq(name, "handleButtonClick4")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_handler_name"]["handles form onSubmit"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <form />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local name = generate_event_handler.generate_handler_name("form", "Submit", bufnr, component)

    eq(name, "handleFormSubmit")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test generate_function_code
T["generate_function_code"] = new_set()

T["generate_function_code"]["generates TypeScript function with event parameter"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event: MouseEvent<HTMLButtonElement>) => void",
        true,
        "  ",
        true
    )

    eq(code, "  const handleClick = (event: MouseEvent<HTMLButtonElement>) => {\n    \n  };")
end

T["generate_function_code"]["generates TypeScript function without parameters"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event: MouseEvent<HTMLButtonElement>) => void",
        false,
        "  ",
        true
    )

    eq(code, "  const handleClick = () => {\n    \n  };")
end

T["generate_function_code"]["generates JavaScript function with event parameter"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event) => void",
        true,
        "  ",
        false
    )

    eq(code, "  const handleClick = (event) => {\n    \n  };")
end

T["generate_function_code"]["generates JavaScript function without parameters"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event) => void",
        false,
        "  ",
        false
    )

    eq(code, "  const handleClick = () => {\n    \n  };")
end

T["generate_function_code"]["preserves indentation"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event: MouseEvent) => void",
        true,
        "    ",
        true
    )

    eq(code, "    const handleClick = (event: MouseEvent) => {\n      \n    };")
end

T["generate_function_code"]["extracts parameter type from handler signature"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event: MouseEvent<HTMLButtonElement>) => void",
        true,
        "  ",
        true
    )

    assert(code:match("event: MouseEvent<HTMLButtonElement>"))
end

T["generate_function_code"]["handles handler type without fat arrow"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event: MouseEvent<HTMLButtonElement>)",
        true,
        "  ",
        true
    )

    assert(code:match("event: MouseEvent<HTMLButtonElement>"))
end

T["generate_function_code"]["uses default event parameter when no type"] = function()
    local code =
        generate_event_handler.generate_function_code("handleClick", nil, true, "  ", false)

    eq(code, "  const handleClick = (event) => {\n    \n  };")
end

T["generate_function_code"]["preserves custom parameter name for custom components (TypeScript)"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(click: CustomClickEvent) => void",
        true,
        "  ",
        true
    )

    eq(code, "  const handleClick = (click: CustomClickEvent) => {\n    \n  };")
end

T["generate_function_code"]["preserves custom parameter name for custom components (JavaScript)"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(click) => void",
        true,
        "  ",
        false
    )

    eq(code, "  const handleClick = (click) => {\n    \n  };")
end

T["generate_function_code"]["normalizes to event for HTML elements"] = function()
    local code = generate_event_handler.generate_function_code(
        "handleClick",
        "(event: MouseEvent<HTMLButtonElement>) => void",
        true,
        "  ",
        true
    )

    assert(code:match("event: MouseEvent<HTMLButtonElement>"))
end

-- Test get_react_import_info
T["get_react_import_info"] = new_set()

T["get_react_import_info"]["finds named imports"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local import_info =
        require("react.code_actions.generate_event_handler").get_react_import_info(bufnr)

    assert(import_info)
    eq(import_info ~= nil, true)
    eq(import_info.type, "named")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_react_import_info"]["finds default import"] = function()
    local bufnr = create_tsx_buffer({
        "import React from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local import_info =
        require("react.code_actions.generate_event_handler").get_react_import_info(bufnr)

    assert(import_info)
    eq(import_info ~= nil, true)
    eq(import_info.type, "default")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_react_import_info"]["returns nil when no React import"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local import_info =
        require("react.code_actions.generate_event_handler").get_react_import_info(bufnr)

    eq(import_info, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_react_import_info"]["handles mixed imports"] = function()
    local bufnr = create_tsx_buffer({
        "import React, { useState } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local import_info =
        require("react.code_actions.generate_event_handler").get_react_import_info(bufnr)

    assert(import_info)
    eq(import_info ~= nil, true)
    -- Should find named imports first
    eq(import_info.type, "named")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test has_type_import
T["has_type_import"] = new_set()

T["has_type_import"]["detects existing type import"] = function()
    local bufnr = create_tsx_buffer({
        "import { type MouseEvent } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local has_import =
        require("react.code_actions.generate_event_handler").has_type_import(bufnr, "MouseEvent")

    eq(has_import, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["has_type_import"]["detects import type syntax"] = function()
    local bufnr = create_tsx_buffer({
        "import { MouseEvent } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local has_import =
        require("react.code_actions.generate_event_handler").has_type_import(bufnr, "MouseEvent")

    eq(has_import, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["has_type_import"]["returns false when type not imported"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local has_import =
        require("react.code_actions.generate_event_handler").has_type_import(bufnr, "MouseEvent")

    eq(has_import, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["has_type_import"]["returns false when no React import"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local has_import =
        require("react.code_actions.generate_event_handler").has_type_import(bufnr, "MouseEvent")

    eq(has_import, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test create_type_import_edit
T["create_type_import_edit"] = new_set()

T["create_type_import_edit"]["creates new import when none exists"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = require("react.code_actions.generate_event_handler").create_type_import_edit(
        bufnr,
        "MouseEvent"
    )

    assert(edit)
    eq(edit ~= nil, true)
    eq(edit.row, 0)
    eq(edit.col, 0)
    eq(edit.text, "import { type MouseEvent } from 'react';\n")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_type_import_edit"]["adds to existing named imports alphabetically"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = require("react.code_actions.generate_event_handler").create_type_import_edit(
        bufnr,
        "MouseEvent"
    )

    assert(edit)
    eq(edit ~= nil, true)
    -- MouseEvent comes before useState alphabetically
    eq(edit.text, "type MouseEvent, ")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_type_import_edit"]["adds to default import"] = function()
    local bufnr = create_tsx_buffer({
        "import React from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = require("react.code_actions.generate_event_handler").create_type_import_edit(
        bufnr,
        "MouseEvent"
    )

    assert(edit)
    eq(edit ~= nil, true)
    eq(edit.text, ", { type MouseEvent }")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_type_import_edit"]["returns nil when type already imported"] = function()
    local bufnr = create_tsx_buffer({
        "import { type MouseEvent } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = require("react.code_actions.generate_event_handler").create_type_import_edit(
        bufnr,
        "MouseEvent"
    )

    eq(edit, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_type_import_edit"]["respects 'use client' directive"] = function()
    local bufnr = create_tsx_buffer({
        "'use client'",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = require("react.code_actions.generate_event_handler").create_type_import_edit(
        bufnr,
        "MouseEvent"
    )

    assert(edit)
    eq(edit ~= nil, true)
    eq(edit.row, 1)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_type_import_edit"]["handles multiple existing type imports"] = function()
    local bufnr = create_tsx_buffer({
        "import { type ChangeEvent, useState } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = require("react.code_actions.generate_event_handler").create_type_import_edit(
        bufnr,
        "MouseEvent"
    )

    assert(edit)
    eq(edit ~= nil, true)
    -- MouseEvent comes after ChangeEvent, before useState
    eq(edit.text, ", type MouseEvent")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test find_return_statement
T["find_return_statement"] = new_set()

T["find_return_statement"]["finds return in function"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local return_node = generate_event_handler.find_return_statement(component)

    assert(return_node)
    eq(return_node ~= nil, true)
    eq(return_node:type(), "return_statement")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_return_statement"]["finds last return with multiple returns"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  if (true) return <div />;",
        "  return <span />;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local return_node = generate_event_handler.find_return_statement(component)

    assert(return_node)
    eq(return_node ~= nil, true)
    local row = return_node:range()
    eq(row, 2) -- 0-indexed, so line 3

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_return_statement"]["returns nil when no return"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const x = 1;",
        "}",
    })

    local component = generate_event_handler.find_component_scope(bufnr, 1, 10)
    local return_node = generate_event_handler.find_return_statement(component)

    eq(return_node, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
