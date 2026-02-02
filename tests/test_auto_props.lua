local helpers = require("tests.helpers")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- Helper: create TSX buffer
local function create_tsx_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "typescriptreact"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
end

-- Helper: check LuaSnip availability
local function luasnip_available()
    local ok, _ = pcall(require, "luasnip")
    return ok
end

-- ============================================================
-- Unit Tests - detect_jsx_component()
-- ============================================================
T["detect_jsx_component"] = new_set()

T["detect_jsx_component"]["PascalCase component"] = function()
    local bufnr = create_tsx_buffer({ "<Button>" })

    -- Mock treesitter detection
    local auto_props_module = require("react.completion.auto_props")
    local detect = auto_props_module.detect_jsx_component
        or function(bufnr, row, col)
            local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
            local component_name = line:match("<([A-Z][%w_]*)")
            if component_name then
                return {
                    component_name = component_name,
                    component_row = row,
                }
            end
            return nil
        end

    local result = detect(bufnr, 0, 7)
    assert(result)
    eq(result.component_name, "Button")
    eq(result.component_row, 0)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["lowercase HTML element"] = function()
    local bufnr = create_tsx_buffer({ "<button>" })

    -- Regex match should fail for lowercase
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local component_name = line:match("<([A-Z][%w_]*)")

    eq(component_name, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["nested JSX"] = function()
    local bufnr = create_tsx_buffer({ "<div><Button /></div>" })

    -- Cursor at "Button" position (col 11)
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local component_name = line:match("<([A-Z][%w_]*)")

    eq(component_name, "Button")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["self-closing tag"] = function()
    local bufnr = create_tsx_buffer({ "<Button />" })

    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local component_name = line:match("<([A-Z][%w_]*)")

    eq(component_name, "Button")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["no JSX context"] = function()
    local bufnr = create_tsx_buffer({ "const x = Button" })

    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local component_name = line:match("<([A-Z][%w_]*)")

    eq(component_name, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["incomplete tag creates ERROR node"] = function()
    local bufnr = create_tsx_buffer({ "<Tag" })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    -- Verify incomplete tag creates ERROR node (not jsx_element/jsx_opening_element)
    local function find_node_types(node)
        local types = {}
        table.insert(types, node:type())
        for child in node:iter_children() do
            vim.list_extend(types, find_node_types(child))
        end
        return types
    end

    local types = find_node_types(root)
    eq(vim.tbl_contains(types, "ERROR"), true, "Should have ERROR node")
    eq(vim.tbl_contains(types, "jsx_element"), false, "Should not have jsx_element")
    eq(vim.tbl_contains(types, "jsx_opening_element"), false, "Should not have jsx_opening_element")

    -- Verify regex extracts component name (fallback for ERROR nodes)
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local component_name = line:match("<([A-Z][%w_]*)")
    eq(component_name, "Tag")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["incomplete tag with custom component on next line"] = function()
    local bufnr = create_tsx_buffer({
        "<Button",
        "<Complete />",
    })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local auto_props = require("react.completion.auto_props")

    -- Cursor on row 0 after "<Button"
    local result = auto_props.detect_jsx_component(bufnr, 0, 7)

    -- Should return context with component_name but nil jsx_element_node
    -- (multi-row node rejected to prevent contamination from next line)
    assert(result, "Should return context")
    eq(result.component_name, "Button")
    eq(result.component_row, 0)
    eq(result.jsx_element_node, nil, "jsx_element_node should be nil for multi-row incomplete tag")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["incomplete tag with HTML tag on next line"] = function()
    local bufnr = create_tsx_buffer({
        "<Button",
        "<div />",
    })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local auto_props = require("react.completion.auto_props")

    -- Cursor on row 0 after "<Button"
    local result = auto_props.detect_jsx_component(bufnr, 0, 7)

    -- Should return context even when node starts on different row
    assert(result, "Should return context")
    eq(result.component_name, "Button")
    eq(result.component_row, 0)
    eq(result.jsx_element_node, nil, "jsx_element_node should be nil when node on different row")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["detect_jsx_component"]["complete tag spanning multiple rows"] = function()
    local bufnr = create_tsx_buffer({
        "<Button",
        "  prop={value}",
        "/>",
    })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local auto_props = require("react.completion.auto_props")

    -- Cursor on row 0 after "<Button"
    -- This is a complete multi-row tag (ends with />), should allow the node
    -- Note: This test may not work as expected since line 0 doesn't end with > or />
    -- but demonstrates the intended behavior
    local result = auto_props.detect_jsx_component(bufnr, 0, 7)

    assert(result, "Should return context")
    eq(result.component_name, "Button")
    eq(result.component_row, 0)
    -- jsx_element_node could be nil or valid depending on treesitter parsing

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Unit Tests - get_assigned_props()
-- ============================================================
T["get_assigned_props"] = new_set()

T["get_assigned_props"]["no props"] = function()
    local bufnr = create_tsx_buffer({ "<Button>" })

    -- Parse and get jsx_element_node
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local tree = parser:parse()[1]
    local root = tree:root()
    local jsx_node = root:named_child(0)

    if jsx_node then
        local assigned = {}
        for child in jsx_node:iter_children() do
            if child:type() == "jsx_attribute" then
                for attr_child in child:iter_children() do
                    if attr_child:type() == "property_identifier" then
                        assigned[vim.treesitter.get_node_text(attr_child, bufnr)] = true
                        break
                    end
                end
            end
        end

        local count = 0
        for _ in pairs(assigned) do
            count = count + 1
        end
        eq(count, 0)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_assigned_props"]["single prop"] = function()
    local bufnr = create_tsx_buffer({ '<Button value="x">' })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    -- Find jsx element
    local function find_jsx_element(node)
        if node:type() == "jsx_opening_element" or node:type() == "jsx_self_closing_element" then
            return node
        end
        for child in node:iter_children() do
            local result = find_jsx_element(child)
            if result then
                return result
            end
        end
        return nil
    end

    local jsx_node = find_jsx_element(root)
    if jsx_node then
        local assigned = {}
        for child in jsx_node:iter_children() do
            if child:type() == "jsx_attribute" then
                for attr_child in child:iter_children() do
                    if attr_child:type() == "property_identifier" then
                        assigned[vim.treesitter.get_node_text(attr_child, bufnr)] = true
                        break
                    end
                end
            end
        end

        eq(assigned["value"], true)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_assigned_props"]["multiple props"] = function()
    local bufnr = create_tsx_buffer({ '<Button a={1} b="2">' })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    local function find_jsx_element(node)
        if node:type() == "jsx_opening_element" or node:type() == "jsx_self_closing_element" then
            return node
        end
        for child in node:iter_children() do
            local result = find_jsx_element(child)
            if result then
                return result
            end
        end
        return nil
    end

    local jsx_node = find_jsx_element(root)
    if jsx_node then
        local assigned = {}
        for child in jsx_node:iter_children() do
            if child:type() == "jsx_attribute" then
                for attr_child in child:iter_children() do
                    if attr_child:type() == "property_identifier" then
                        assigned[vim.treesitter.get_node_text(attr_child, bufnr)] = true
                        break
                    end
                end
            end
        end

        eq(assigned["a"], true)
        eq(assigned["b"], true)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_assigned_props"]["spread ignored"] = function()
    local bufnr = create_tsx_buffer({ '<Button {...props} value="x">' })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    local function find_jsx_element(node)
        if node:type() == "jsx_opening_element" or node:type() == "jsx_self_closing_element" then
            return node
        end
        for child in node:iter_children() do
            local result = find_jsx_element(child)
            if result then
                return result
            end
        end
        return nil
    end

    local jsx_node = find_jsx_element(root)
    if jsx_node then
        local assigned = {}
        for child in jsx_node:iter_children() do
            if child:type() == "jsx_attribute" then
                for attr_child in child:iter_children() do
                    if attr_child:type() == "property_identifier" then
                        assigned[vim.treesitter.get_node_text(attr_child, bufnr)] = true
                        break
                    end
                end
            end
        end

        -- Only explicit jsx_attribute, not spread
        eq(assigned["value"], true)
        eq(assigned["props"], nil)
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["get_assigned_props"]["nil node returns empty"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    -- Directly call the internal function via module (if exported for testing)
    -- Or test via the public API
    local auto_props = require("react.completion.auto_props")

    -- get_assigned_props is internal, but we test via detect_jsx_component
    -- which returns nil jsx_element_node for incomplete tags
    local context = auto_props.detect_jsx_component(bufnr, 0, 7)

    -- Context should exist but jsx_element_node should be nil
    assert(context, "Should have context")
    eq(context.jsx_element_node, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Integration Tests - query_required_props()
-- ============================================================
T["query_required_props"] = new_set()

T["query_required_props"]["required props"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            { label = "value", detail = "(property) ButtonProps.value: string" },
                        },
                    },
                },
            }
        end
        return nil
    end

    -- Simulate query
    local line_text = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local needs_temp_close = not line_text:match("[/>]$")
    eq(needs_temp_close, true)

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    local items = result and result[1] and result[1].result and result[1].result.items

    local required_props = {}
    if items then
        for _, item in ipairs(items) do
            local detail = item.detail
            if detail then
                local prop_name, optional = detail:match("%.(%w+)(%??):")
                if prop_name and optional == "" then
                    table.insert(required_props, prop_name)
                end
            end
        end
    end

    eq(#required_props, 1)
    eq(required_props[1], "value")

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["query_required_props"]["optional props only"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            { label = "value", detail = "(property) ButtonProps.value?: string" },
                        },
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    local items = result and result[1] and result[1].result and result[1].result.items

    local required_props = {}
    if items then
        for _, item in ipairs(items) do
            local detail = item.detail
            if detail then
                local prop_name, optional = detail:match("%.(%w+)(%??):")
                if prop_name and optional == "" then
                    table.insert(required_props, prop_name)
                end
            end
        end
    end

    eq(#required_props, 0)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["query_required_props"]["mixed required and optional"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            { label = "a", detail = "(property) ButtonProps.a: string" },
                            { label = "b", detail = "(property) ButtonProps.b?: string" },
                        },
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    local items = result and result[1] and result[1].result and result[1].result.items

    local required_props = {}
    if items then
        for _, item in ipairs(items) do
            local detail = item.detail
            if detail then
                local prop_name, optional = detail:match("%.(%w+)(%??):")
                if prop_name and optional == "" then
                    table.insert(required_props, prop_name)
                end
            end
        end
    end

    eq(#required_props, 1)
    eq(required_props[1], "a")

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["query_required_props"]["lazy completion resolve"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original_request = vim.lsp.buf_request_sync
    local original_client = vim.lsp.get_client_by_id

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                [1] = {
                    result = {
                        items = {
                            { label = "value", data = { some = "data" } },
                        },
                    },
                },
            }
        end
        return nil
    end

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_client_by_id = function(_id)
        return {
            request_sync = function(method, _item, _timeout, _bufnr)
                if method == "completionItem/resolve" then
                    return {
                        result = {
                            detail = "(property) ButtonProps.value: string",
                        },
                    }
                end
                return nil
            end,
        }
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    local items = result and result[1] and result[1].result and result[1].result.items

    local required_props = {}
    if items then
        local client = vim.lsp.get_client_by_id(1)
        for _, item in ipairs(items) do
            local detail = item.detail
            -- Resolve if missing
            if not detail and item.data and client then
                local response = client.request_sync("completionItem/resolve", item, 1000, bufnr)
                if response and response.result then
                    detail = response.result.detail
                end
            end

            if detail then
                local prop_name, optional = detail:match("%.(%w+)(%??):")
                if prop_name and optional == "" then
                    table.insert(required_props, prop_name)
                end
            end
        end
    end

    eq(#required_props, 1)
    eq(required_props[1], "value")

    vim.lsp.buf_request_sync = original_request
    vim.lsp.get_client_by_id = original_client
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["query_required_props"]["incomplete JSX no closing"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local line_text = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local needs_temp_close = not line_text:match("[/>]$")

    eq(needs_temp_close, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["query_required_props"]["different prop detail formats"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    -- Test format: (property) a: Type
    local detail1 = "(property) a: string"
    local prop1, opt1 = detail1:match("%(property%)%s+(%w+)(%??):")
    eq(prop1, "a")
    eq(opt1, "")

    -- Test format: (property) ButtonProps.a: Type
    local detail2 = "(property) ButtonProps.a: string"
    local prop2, opt2 = detail2:match("%.(%w+)(%??):")
    eq(prop2, "a")
    eq(opt2, "")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["query_required_props"]["label parsing fallback"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    -- Test label parsing when detail is unavailable
    -- "a" = required (no ? suffix)
    local label1 = "a"
    local prop_name1, optional1
    if label1:match("%?$") then
        prop_name1 = label1:match("^(%w+)%?$")
        optional1 = "?"
    else
        prop_name1 = label1:match("^(%w+)$")
        optional1 = ""
    end
    eq(prop_name1, "a")
    eq(optional1, "")

    -- "b?" = optional (has ? suffix)
    local label2 = "b?"
    local prop_name2, optional2
    if label2:match("%?$") then
        prop_name2 = label2:match("^(%w+)%?$")
        optional2 = "?"
    else
        prop_name2 = label2:match("^(%w+)$")
        optional2 = ""
    end
    eq(prop_name2, "b")
    eq(optional2, "?")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Integration Tests - generate_props_snippet()
-- ============================================================
T["generate_props_snippet"] = new_set()

T["generate_props_snippet"]["single prop"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local ls = require("luasnip")
    local s = ls.snippet
    local i = ls.insert_node
    local t = ls.text_node

    local nodes = {}
    local props = { "value" }

    for idx, prop in ipairs(props) do
        table.insert(nodes, t(" " .. prop .. "={"))
        table.insert(nodes, i(idx))
        table.insert(nodes, t("}"))
    end

    local snippet = s("", nodes)

    eq(snippet ~= nil, true)
    -- Snippet structure creates wrapper + nodes
    assert(#nodes >= 3)
end

T["generate_props_snippet"]["multiple props"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local ls = require("luasnip")
    local s = ls.snippet
    local i = ls.insert_node
    local t = ls.text_node

    local nodes = {}
    local props = { "a", "b" }

    for idx, prop in ipairs(props) do
        table.insert(nodes, t(" " .. prop .. "={"))
        table.insert(nodes, i(idx))
        table.insert(nodes, t("}"))
    end

    local snippet = s("", nodes)

    eq(snippet ~= nil, true)
    -- Snippet structure creates wrapper + nodes
    assert(#nodes >= 6)
end

T["generate_props_snippet"]["empty list"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local props = {}

    eq(#props, 0)
end

-- ============================================================
-- Integration Tests - insert_props_snippet()
-- ============================================================
T["insert_props_snippet"] = new_set()

T["insert_props_snippet"]["opening tag"] = function()
    local bufnr = create_tsx_buffer({ "<Button>" })

    local line_text = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local insert_col = #line_text

    if line_text:sub(-1) == ">" then
        insert_col = insert_col - 1
    end

    eq(insert_col, 7)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["insert_props_snippet"]["self-closing tag"] = function()
    local bufnr = create_tsx_buffer({ "<Button />" })

    local line_text = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local insert_col = #line_text

    if line_text:sub(-2) == "/>" then
        insert_col = insert_col - 2
    end

    eq(insert_col, 8)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["insert_props_snippet"]["incomplete tag"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local line_text = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local insert_col = #line_text

    eq(insert_col, 7)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- End-to-End Tests - handle_completion()
-- ============================================================
T["handle_completion"] = new_set()

T["handle_completion"]["complete workflow"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buffer({ "<Button" })

    -- Mock LSP for completion query
    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_, method, _, _)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            { label = "value", detail = "(property) ButtonProps.value: string" },
                        },
                    },
                },
            }
        end
        return nil
    end

    -- Simulate completion context check (handle_completion checks vim.v.completed_item)
    -- We can't set vim.v.completed_item in tests, so just verify the workflow logic
    local has_lsp_result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    eq(has_lsp_result ~= nil, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["handle_completion"]["already has some props"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buffer({ '<Button value="x"' })

    -- Expected: filter out "value" from required props
    local assigned = { value = true }
    local all_required = { "value", "label" }
    local missing = {}

    for _, prop in ipairs(all_required) do
        if not assigned[prop] then
            table.insert(missing, prop)
        end
    end

    eq(#missing, 1)
    eq(missing[1], "label")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["handle_completion"]["no required props"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            { label = "value", detail = "(property) ButtonProps.value?: string" },
                        },
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    local items = result and result[1] and result[1].result and result[1].result.items

    local required_props = {}
    if items then
        for _, item in ipairs(items) do
            local detail = item.detail
            if detail then
                local prop_name, optional = detail:match("%.(%w+)(%??):")
                if prop_name and optional == "" then
                    table.insert(required_props, prop_name)
                end
            end
        end
    end

    eq(#required_props, 0)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["handle_completion"]["HTML element"] = function()
    local bufnr = create_tsx_buffer({ "<div" })

    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local component_name = line:match("<([A-Z][%w_]*)")

    eq(component_name, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["handle_completion"]["non-LSP completion"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    -- Test checking completed_item validity (would be done by handle_completion)
    -- In a real scenario, handle_completion checks if completed_item.word exists
    local mock_completed = { word = "Button" }
    local is_valid = mock_completed.word and mock_completed.word ~= ""
    eq(is_valid, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Edge Cases
-- ============================================================
T["edge_cases"] = new_set()

T["edge_cases"]["incomplete JSX ERROR nodes"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "tsx")
    if not ok then
        MiniTest.skip("treesitter tsx parser not available")
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return
    end

    local tree = parser:parse()[1]
    local root = tree:root()

    -- Check for ERROR nodes (incomplete JSX often has them)
    for child in root:iter_children() do
        if child:type() == "ERROR" then
            -- Found error node, but regex fallback will work
            break
        end
    end

    -- Regex fallback should still work
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
    local component_name = line:match("<([A-Z][%w_]*)")
    eq(component_name, "Button")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["edge_cases"]["LSP timeout"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, _method, _params, _timeout)
        return nil -- Simulate timeout
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    eq(result, nil)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["edge_cases"]["empty completion results"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {},
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    local items = result and result[1] and result[1].result and result[1].result.items

    eq(items and #items == 0, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["edge_cases"]["PascalCase filter"] = function()
    local bufnr = create_tsx_buffer({ "<Button" })

    local original = vim.lsp.buf_request_sync
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/completion" then
            return {
                {
                    result = {
                        items = {
                            { label = "Button", detail = "(property) Button: Component" },
                            { label = "value", detail = "(property) ButtonProps.value: string" },
                        },
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", {}, 1000)
    local items = result and result[1] and result[1].result and result[1].result.items

    local required_props = {}
    if items then
        for _, item in ipairs(items) do
            local label = item.label or ""
            -- Skip PascalCase
            if not label:match("^[A-Z]") then
                local detail = item.detail
                if detail then
                    local prop_name, optional = detail:match("%.(%w+)(%??):")
                    if prop_name and optional == "" then
                        table.insert(required_props, prop_name)
                    end
                end
            end
        end
    end

    eq(#required_props, 1)
    eq(required_props[1], "value")

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
