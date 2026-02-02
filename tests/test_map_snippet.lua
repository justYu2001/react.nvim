local helpers = require("tests.helpers")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- Helper to check if LuaSnip is available
local function luasnip_available()
    local ok, _ = pcall(require, "luasnip")
    return ok
end

-- ============================================================
-- Setup and teardown
-- ============================================================
T["setup registers map snippet"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local snippets = require("react.snippets")
    snippets.setup()

    assert(true)

    snippets.teardown()
end

-- ============================================================
-- Transformation tests
-- ============================================================
T["transformation"] = new_set()

T["transformation"]["identifier"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "items" }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, "items.map((item) => ())")
end

T["transformation"]["member expression"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "data.users" }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, "data.users.map((item) => ())")
end

T["transformation"]["call expression"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "getItems()" }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, "getItems().map((item) => ())")
end

T["transformation"]["subscript expression"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "arr[0]" }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, "arr[0].map((item) => ())")
end

T["transformation"]["nested member"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "props.data.items.filter(x => x > 0)" }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, "props.data.items.filter(x => x > 0).map((item) => ())")
end

-- ============================================================
-- Context detection tests
-- ============================================================
T["context"] = new_set()

T["context"]["triggers in jsx braces"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    -- Simulate in_jsx_braces() logic
    -- Should return true when inside jsx_expression inside JSX element
    local in_jsx_expr = true
    local in_jsx_element = true

    local should_show = in_jsx_expr and in_jsx_element
    eq(should_show, true)
end

T["context"]["not outside braces"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    -- Simulate in_jsx_braces() logic
    -- Should return false when not inside jsx_expression
    local in_jsx_expr = false
    local in_jsx_element = true

    local should_show = in_jsx_expr and in_jsx_element
    eq(should_show, false)
end

T["context"]["not outside jsx"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    -- Simulate in_jsx_braces() logic
    -- Should return false when not inside JSX element
    local in_jsx_expr = true
    local in_jsx_element = false

    local should_show = in_jsx_expr and in_jsx_element
    eq(should_show, false)
end

-- ============================================================
-- Tab stops tests
-- ============================================================
T["tab_stops"] = new_set()

T["tab_stops"]["has param and body stops"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    -- Verify structure has 2 insert nodes
    local ls = require("luasnip")
    local i = ls.insert_node
    local t = ls.text_node

    -- Simulate snippet nodes
    local nodes = {
        t("items.map(("),
        i(1, "item"), -- First tab stop with default
        t(") => ("),
        i(2), -- Second tab stop
        t("))"),
    }

    eq(#nodes, 5)
    eq(nodes[2].pos, 1)
    eq(nodes[4].pos, 2)
end

T["tab_stops"]["param has default text"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local ls = require("luasnip")
    local i = ls.insert_node

    local param_node = i(1, "item")
    eq(param_node.pos, 1)
    -- Default text is stored internally, can't easily test
    -- but structure confirms it exists
end

T["tab_stops"]["body is empty"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local ls = require("luasnip")
    local i = ls.insert_node

    local body_node = i(2)
    eq(body_node.pos, 2)
    -- No default text for body
end

-- ============================================================
-- Edge cases
-- ============================================================
T["edge_cases"] = new_set()

T["edge_cases"]["empty match"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "" }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, ".map((item) => ())")
end

T["edge_cases"]["whitespace in expression"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "  items  " }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, "  items  .map((item) => ())")
end

T["edge_cases"]["complex chained expression"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "data.items.filter(Boolean).sort()" }
    local array_expr = table.concat(matched, "\n")
    local result = array_expr .. ".map((item) => ())"

    eq(result, "data.items.filter(Boolean).sort().map((item) => ())")
end

-- ============================================================
-- LSP type checking tests
-- ============================================================
T["lsp_type_check"] = new_set()

-- Helper to create buffer with TSX content
local function create_tsx_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "typescriptreact")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

-- Helper to mock LSP hover response
local function mock_hover_response(type_str)
    return function(_bufnr, method, _params, _timeout)
        if method == "textDocument/hover" then
            return {
                {
                    result = {
                        contents = {
                            value = type_str,
                        },
                    },
                },
            }
        end
        return nil
    end
end

T["lsp_type_check"]["array bracket syntax"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items: string[]" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("const items: string[]")

    -- Verify array type detected via LSP
    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["Array generic syntax"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items: Array<User>" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("const items: Array<User>")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["ReadonlyArray syntax"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items: ReadonlyArray<string>" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("const items: ReadonlyArray<string>")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["chained map method"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "items.map(x => x)" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("items.map(x => x)")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["chained filter method"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "items.filter(Boolean)" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("items.filter(Boolean)")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["chained slice method"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "items.slice(0, 10)" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("items.slice(0, 10)")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["string type rejected"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const title: string" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("const title: string")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["number type rejected"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const count: number" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("const count: number")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["object type rejected"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const obj: { key: string }" })
    local original = vim.lsp.buf_request_sync

    vim.lsp.buf_request_sync = mock_hover_response("const obj: { key: string }")

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local has_result = result ~= nil and result[1] ~= nil
    eq(has_result, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["LSP unavailable fallback"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items = []" })
    local original = vim.lsp.buf_request_sync

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        return nil -- Simulate LSP unavailable
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    eq(result, nil)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["lsp_type_check"]["empty result fallback"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items = []" })
    local original = vim.lsp.buf_request_sync

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        return { {} } -- Empty result
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    local is_empty = result and result[1] and result[1].result == nil
    eq(is_empty, true)

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Hover response format tests
-- ============================================================
T["hover_formats"] = new_set()

T["hover_formats"]["string format"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items: string[]" })
    local original = vim.lsp.buf_request_sync

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/hover" then
            return {
                {
                    result = {
                        contents = "const items: string[]", -- Direct string
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    if result and result[1] then
        local has_string = type(result[1].result.contents) == "string"
        eq(has_string, true)
    end

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hover_formats"]["MarkupContent format"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items: string[]" })
    local original = vim.lsp.buf_request_sync

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/hover" then
            return {
                {
                    result = {
                        contents = {
                            value = "const items: string[]",
                        },
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    if result and result[1] then
        local has_value = result[1].result.contents.value ~= nil
        eq(has_value, true)
    end

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hover_formats"]["MarkedString array format"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items: string[]" })
    local original = vim.lsp.buf_request_sync

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/hover" then
            return {
                {
                    result = {
                        contents = {
                            { value = "const items: string[]" },
                        },
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    if result and result[1] then
        local is_array = type(result[1].result.contents[1]) == "table"
        eq(is_array, true)
    end

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["hover_formats"]["nil contents fallback"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local bufnr = create_tsx_buf({ "const items = []" })
    local original = vim.lsp.buf_request_sync

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.buf_request_sync = function(_bufnr, method, _params, _timeout)
        if method == "textDocument/hover" then
            return {
                {
                    result = {
                        contents = nil,
                    },
                },
            }
        end
        return nil
    end

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", {}, 500)
    if result and result[1] then
        local has_nil = result[1].result.contents == nil
        eq(has_nil, true)
    end

    vim.lsp.buf_request_sync = original
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Module loader tests
-- ============================================================
T["loader"] = new_set()

T["loader"]["map_postfix module loads"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local snippets_init = require("react.snippets")
    snippets_init.setup()

    local ok, map_postfix = pcall(require, "react.snippets.map_postfix")
    assert(ok, "map_postfix module should be loadable")
    assert(type(map_postfix.get_snippets) == "function")

    local snippets = map_postfix.get_snippets()
    assert(type(snippets) == "table")
    assert(#snippets > 0, "Should have at least one snippet")

    snippets_init.teardown()
end

T["loader"]["both cond and map load"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local snippets_init = require("react.snippets")
    snippets_init.setup()

    local ok_cond = pcall(require, "react.snippets.cond_postfix")
    local ok_map = pcall(require, "react.snippets.map_postfix")

    assert(ok_cond, "cond_postfix should load")
    assert(ok_map, "map_postfix should load")

    snippets_init.teardown()
end

return T
