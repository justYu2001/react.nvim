local helpers = require("tests.helpers")
local generate_handler = require("react.code_actions.generate_handler")

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

-- Test detect_component_at_cursor
T["detect_component_at_cursor"] = new_set()

T["detect_component_at_cursor"]["detects component on self-closing element"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <MyButton />;",
        "}",
    })

    local context = generate_handler.detect_component_at_cursor({
        bufnr = bufnr,
        row = 2,
        col = 11, -- on "MyButton"
    })

    assert(context)
    eq(context.component_name, "MyButton")
    eq(context.jsx_element_node ~= nil, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_component_at_cursor"]["detects component on opening element"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <MyButton onClick={}>Click</MyButton>;",
        "}",
    })

    local context = generate_handler.detect_component_at_cursor({
        bufnr = bufnr,
        row = 2,
        col = 11, -- on "MyButton"
    })

    assert(context)
    eq(context.component_name, "MyButton")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_component_at_cursor"]["detects HTML element name"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button>Click</button>;",
        "}",
    })

    local context = generate_handler.detect_component_at_cursor({
        bufnr = bufnr,
        row = 2,
        col = 11, -- on "button"
    })

    assert(context)
    eq(context.component_name, "button")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_component_at_cursor"]["returns nil when cursor not on component name"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button onClick={}>Click</button>;",
        "}",
    })

    -- Cursor on onClick, not on button
    local context = generate_handler.detect_component_at_cursor({
        bufnr = bufnr,
        row = 2,
        col = 20,
    })

    eq(context, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_component_at_cursor"]["returns nil when not in JSX"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const x = 1;",
        "  return <div />;",
        "}",
    })

    local context = generate_handler.detect_component_at_cursor({
        bufnr = bufnr,
        row = 2,
        col = 10,
    })

    eq(context, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_component_at_cursor"]["returns nil when cursor is on attribute value"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        '  return <div className="foo" />;',
        "}",
    })

    local context = generate_handler.detect_component_at_cursor({
        bufnr = bufnr,
        row = 2,
        col = 25, -- inside "foo"
    })

    eq(context, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test get_assigned_props
T["get_assigned_props"] = new_set()

T["get_assigned_props"]["finds explicitly assigned props"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button onClick={fn} onFocus={fn2} />;",
        "}",
    })

    -- Get the jsx_self_closing_element node
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local assigned = generate_handler.get_assigned_props(jsx_node, bufnr)

    eq(assigned["onClick"], true)
    eq(assigned["onFocus"], true)
    eq(assigned["onChange"], nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_assigned_props"]["ignores spread attributes"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button {...props} onClick={fn} />;",
        "}",
    })

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local assigned = generate_handler.get_assigned_props(jsx_node, bufnr)

    -- Only onClick is explicitly assigned; spread is ignored
    eq(assigned["onClick"], true)
    eq(assigned["props"], nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_assigned_props"]["returns empty table when no props"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button />;",
        "}",
    })

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local assigned = generate_handler.get_assigned_props(jsx_node, bufnr)

    eq(next(assigned), nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test get_available_event_props (mocked LSP)
T["get_available_event_props"] = new_set()

T["get_available_event_props"]["filters event props from completion results"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button />;",
        "}",
    })

    -- Mock LSP completion
    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            {
                                label = "onClick",
                                detail = "(property) onClick?: (event: MouseEvent<HTMLButtonElement>) => void",
                            },
                            {
                                label = "onChange",
                                detail = "(property) onChange?: (event: ChangeEvent<HTMLButtonElement>) => void",
                            },
                            { label = "className" },
                            {
                                label = "onFocus?",
                                detail = "(property) onFocus?: (event: FocusEvent<HTMLButtonElement>) => void",
                            },
                            { label = "id" },
                        },
                    },
                },
            }
        end
        return nil
    end

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local props = generate_handler.get_available_event_props(bufnr, jsx_node, "button")

    assert(props)
    -- Should contain only on* props, sorted, with ? stripped, as objects
    eq(props[1].name, "onChange")
    eq(props[1].handler_type, "(event: ChangeEvent<HTMLButtonElement>) => void")
    eq(props[2].name, "onClick")
    eq(props[2].handler_type, "(event: MouseEvent<HTMLButtonElement>) => void")
    eq(props[3].name, "onFocus")
    eq(props[3].handler_type, "(event: FocusEvent<HTMLButtonElement>) => void")
    eq(#props, 3)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_available_event_props"]["returns nil when no event props"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button />;",
        "}",
    })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            { label = "className" },
                            { label = "id" },
                        },
                    },
                },
            }
        end
        return nil
    end

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local props = generate_handler.get_available_event_props(bufnr, jsx_node, "button")

    eq(props, nil)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_available_event_props"]["returns nil when LSP returns no result"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button />;",
        "}",
    })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, _method, _params, _timeout)
        return nil
    end

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local props = generate_handler.get_available_event_props(bufnr, jsx_node, "button")

    eq(props, nil)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_available_event_props"]["handles completion list format (not items)"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button />;",
        "}",
    })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        {
                            label = "onBlur",
                            detail = "(property) onBlur?: (event: FocusEvent<HTMLButtonElement>) => void",
                        },
                        {
                            label = "onKeyDown",
                            detail = "(property) onKeyDown?: (event: KeyboardEvent<HTMLButtonElement>) => void",
                        },
                        { label = "style" },
                    },
                },
            }
        end
        return nil
    end

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local props = generate_handler.get_available_event_props(bufnr, jsx_node, "button")

    assert(props)
    eq(props[1].name, "onBlur")
    eq(props[1].handler_type, "(event: FocusEvent<HTMLButtonElement>) => void")
    eq(props[2].name, "onKeyDown")
    eq(props[2].handler_type, "(event: KeyboardEvent<HTMLButtonElement>) => void")
    eq(#props, 2)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test extract_handler_type
T["extract_handler_type"] = new_set()

T["extract_handler_type"]["extracts type from standard detail format"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onClick?: (event: MouseEvent<HTMLButtonElement>) => void",
        "button"
    )
    eq(result, "(event: MouseEvent<HTMLButtonElement>) => void")
end

T["extract_handler_type"]["strips undefined from union type"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onClick?: (event: MouseEvent<HTMLButtonElement>) => void | undefined",
        "button"
    )
    eq(result, "(event: MouseEvent<HTMLButtonElement>) => void")
end

T["extract_handler_type"]["expands React.MouseEventHandler shorthand"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onClick?: React.MouseEventHandler<HTMLButtonElement>",
        "button"
    )
    eq(result, "(event: MouseEvent<HTMLButtonElement>) => void")
end

T["extract_handler_type"]["expands React.ChangeEventHandler shorthand"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onChange?: React.ChangeEventHandler<HTMLInputElement>",
        "input"
    )
    eq(result, "(event: ChangeEvent<HTMLInputElement>) => void")
end

T["extract_handler_type"]["normalizes param name to event for HTML elements"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onClick?: (e: MouseEvent<HTMLButtonElement>) => void",
        "button"
    )
    eq(result, "(event: MouseEvent<HTMLButtonElement>) => void")
end

T["extract_handler_type"]["preserves original param name for PascalCase components"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onClick?: (e: MouseEvent<HTMLButtonElement>) => void",
        "MyButton"
    )
    eq(result, "(e: MouseEvent<HTMLButtonElement>) => void")
end

T["extract_handler_type"]["returns nil for nil detail"] = function()
    local result = generate_handler.extract_handler_type(nil, "button")
    eq(result, nil)
end

T["extract_handler_type"]["returns nil when no type found"] = function()
    local result = generate_handler.extract_handler_type("some random text", "button")
    eq(result, nil)
end

T["extract_handler_type"]["extracts bare function type from custom component detail"] = function()
    local result = generate_handler.extract_handler_type("(value: string) => void", "Button")
    eq(result, "(value: string) => void")
end

T["extract_handler_type"]["extracts bare function type with generic param"] = function()
    local result = generate_handler.extract_handler_type("(value: Array<string>) => void", "MyComp")
    eq(result, "(value: Array<string>) => void")
end

T["extract_handler_type"]["strips React. prefix from direct MouseEvent signature"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void",
        "button"
    )
    eq(result, "(event: MouseEvent<HTMLButtonElement>) => void")
end

T["extract_handler_type"]["strips React. prefix from direct ChangeEvent signature"] = function()
    local result = generate_handler.extract_handler_type(
        "(property) onChange?: (event: React.ChangeEvent<HTMLInputElement>) => void",
        "input"
    )
    eq(result, "(event: ChangeEvent<HTMLInputElement>) => void")
end

T["get_available_event_props"]["resolves detail via completionItem/resolve for lazy completion"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button />;",
        "}",
    })

    local original_req = vim.lsp.buf_request_sync
    local original_get_client = vim.lsp.get_client_by_id

    -- Return items with data but no detail; client_id key is 1
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                [1] = {
                    result = {
                        items = {
                            {
                                label = "onClick",
                                data = { some = "opaque_data" },
                            },
                        },
                    },
                },
            }
        end
        return nil
    end

    -- Fake client that resolves the detail
    vim.lsp.get_client_by_id = function(id)
        if id == 1 then
            return {
                request_sync = function(_self, _method, _item, _timeout)
                    return {
                        result = {
                            detail = "(property) onClick?: (event: MouseEvent<HTMLButtonElement>) => void",
                        },
                    }
                end,
            }
        end
        return nil
    end

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local props = generate_handler.get_available_event_props(bufnr, jsx_node, "button")

    assert(props)
    eq(#props, 1)
    eq(props[1].name, "onClick")
    eq(props[1].handler_type, "(event: MouseEvent<HTMLButtonElement>) => void")

    vim.lsp.buf_request_sync = original_req
    vim.lsp.get_client_by_id = original_get_client
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_available_event_props"]["inserts and removes temp space for no-space self-closing element"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <button/>;",
        "}",
    })

    local original_line = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1]

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            {
                                label = "onClick",
                                detail = "(property) onClick?: (event: MouseEvent<HTMLButtonElement>) => void",
                            },
                        },
                    },
                },
            }
        end
        return nil
    end

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { 1, 11 } })
    local jsx_node = node

    while jsx_node do
        if jsx_node:type() == "jsx_self_closing_element" then
            break
        end
        jsx_node = jsx_node:parent()
    end

    assert(jsx_node)

    local props = generate_handler.get_available_event_props(bufnr, jsx_node, "button")

    assert(props)
    eq(#props, 1)
    eq(props[1].name, "onClick")

    -- Temp space must have been cleaned up
    local after_line = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1]
    eq(after_line, original_line)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
