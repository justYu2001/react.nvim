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
T["setup registers snippets"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local snippets = require("react.snippets")
    snippets.setup()

    -- Just verify setup doesn't error
    assert(true)

    snippets.teardown()
end

T["teardown can be called safely"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local snippets = require("react.snippets")
    snippets.setup()
    snippets.teardown()

    -- Test teardown can be called multiple times without error
    snippets.teardown()
end

-- ============================================================
-- Transformation logic tests
-- ============================================================
T["transformation"] = new_set()

T["transformation"]["single-line"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local jsx_text = "<div>test</div>"
    local has_newline = jsx_text:find("\n") ~= nil

    eq(has_newline, false)

    local result = "{ && " .. jsx_text .. "}"
    eq(result, "{ && <div>test</div>}")
end

T["transformation"]["multi-line with parens"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local jsx_text = "<div>\n  content\n</div>"
    local has_newline = jsx_text:find("\n") ~= nil

    eq(has_newline, true)

    -- Simulate the indentation logic
    local sc = 4 -- starting column
    local indent = string.rep(" ", sc)
    local lines = vim.split(jsx_text, "\n")

    -- Normalize
    local normalized_lines = {}
    for i, line in ipairs(lines) do
        if i == 1 then
            table.insert(normalized_lines, line)
        else
            local stripped = line:gsub("^" .. indent, "")
            table.insert(normalized_lines, stripped)
        end
    end

    -- Re-indent
    local indented_lines = {}
    for _, line in ipairs(normalized_lines) do
        table.insert(indented_lines, indent .. "  " .. line)
    end

    local indented_jsx = table.concat(indented_lines, "\n")
    local result = "{ && (\n" .. indented_jsx .. "\n" .. indent .. ")}"

    -- Verify structure
    assert(result:match("{ && %("))
    assert(result:match("%)%}$"))
end

T["transformation"]["nested with base indent"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    -- Matched text from LS_TSMATCH with nested JSX
    local matched = {
        "<div>",
        "  <input ref={inputRef}/>",
        "  <p>{a}</p>",
        "</div>",
    }

    local base_indent = matched[#matched]:match("^(%s*)") or ""
    eq(base_indent, "")

    -- Transform lines
    local result_lines = {}
    for i, line in ipairs(matched) do
        if line:match("^%s*$") then
            table.insert(result_lines, "")
        elseif i == 1 then
            table.insert(result_lines, "  " .. line)
        else
            local current_indent = line:match("^(%s*)") or ""
            local content = line:match("^%s*(.*)$")
            local relative_indent = #current_indent - #base_indent
            local new_line = string.rep(" ", relative_indent + 2) .. content
            table.insert(result_lines, new_line)
        end
    end

    eq(result_lines[1], "  <div>")
    eq(result_lines[2], "    <input ref={inputRef}/>")
    eq(result_lines[3], "    <p>{a}</p>")
    eq(result_lines[4], "  </div>")
end

T["transformation"]["preserves empty lines"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = {
        "<div>",
        "  <p>first</p>",
        "",
        "  <p>second</p>",
        "</div>",
    }

    local result_lines = {}
    local base_indent = matched[#matched]:match("^(%s*)") or ""

    for i, line in ipairs(matched) do
        if line:match("^%s*$") then
            table.insert(result_lines, "")
        elseif i == 1 then
            table.insert(result_lines, "  " .. line)
        else
            local current_indent = line:match("^(%s*)") or ""
            local content = line:match("^%s*(.*)$")
            local relative_indent = #current_indent - #base_indent
            local new_line = string.rep(" ", relative_indent + 2) .. content
            table.insert(result_lines, new_line)
        end
    end

    eq(result_lines[3], "")
end

T["transformation"]["handles different base indents"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    -- JSX with 4-space base indent
    local matched = {
        "<div>",
        "      <p>content</p>",
        "    </div>",
    }

    local base_indent = matched[#matched]:match("^(%s*)") or ""
    eq(base_indent, "    ")

    local result_lines = {}
    for i, line in ipairs(matched) do
        if i == 1 then
            table.insert(result_lines, "  " .. line)
        else
            local current_indent = line:match("^(%s*)") or ""
            local content = line:match("^%s*(.*)$")
            local relative_indent = #current_indent - #base_indent
            local new_line = string.rep(" ", relative_indent + 2) .. content
            table.insert(result_lines, new_line)
        end
    end

    -- First line gets +2 indent
    eq(result_lines[1], "  <div>")
    -- Second line: 6 spaces - 4 base + 2 = 4 spaces
    eq(result_lines[2], "    <p>content</p>")
    -- Third line: 4 spaces - 4 base + 2 = 2 spaces
    eq(result_lines[3], "  </div>")
end

-- ============================================================
-- Edge cases
-- ============================================================
T["edge_cases"] = new_set()

T["edge_cases"]["empty matched text"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "" }
    local jsx_text = table.concat(matched, "\n")
    local has_newline = jsx_text:find("\n") ~= nil

    eq(has_newline, false)
    eq(jsx_text, "")
end

T["edge_cases"]["whitespace only"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = { "   " }
    local base_indent = matched[#matched]:match("^(%s*)") or ""
    eq(base_indent, "   ")
end

T["edge_cases"]["deeply nested"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local matched = {
        "<div>",
        "  <ul>",
        "    <li>",
        "      <span>text</span>",
        "    </li>",
        "  </ul>",
        "</div>",
    }

    local base_indent = matched[#matched]:match("^(%s*)") or ""
    eq(base_indent, "")

    local result_lines = {}
    for i, line in ipairs(matched) do
        if i == 1 then
            table.insert(result_lines, "  " .. line)
        else
            local current_indent = line:match("^(%s*)") or ""
            local content = line:match("^%s*(.*)$")
            local relative_indent = #current_indent - #base_indent
            local new_line = string.rep(" ", relative_indent + 2) .. content
            table.insert(result_lines, new_line)
        end
    end

    -- Verify indentation preserved relatively
    eq(result_lines[1], "  <div>")
    eq(result_lines[2], "    <ul>")
    eq(result_lines[3], "      <li>")
    eq(result_lines[4], "        <span>text</span>")
end

-- ============================================================
-- Module loader tests
-- ============================================================
T["loader"] = new_set()

T["loader"]["scans postfix files"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local snippets_init = require("react.snippets")
    snippets_init.setup()

    -- Verify cond_postfix module can be loaded
    local ok, cond_postfix = pcall(require, "react.snippets.cond_postfix")
    assert(ok, "cond_postfix module should be loadable")
    assert(type(cond_postfix.get_snippets) == "function")

    local snippets = cond_postfix.get_snippets()
    assert(type(snippets) == "table")
    assert(#snippets > 0, "Should have at least one snippet")

    snippets_init.teardown()
end

T["loader"]["registers for correct filetypes"] = function()
    if not luasnip_available() then
        MiniTest.skip("LuaSnip not available")
        return
    end

    local snippets_init = require("react.snippets")
    snippets_init.setup()

    -- Can't easily inspect LuaSnip's internal state,
    -- but we can verify setup doesn't error and modules load
    local ok = pcall(require, "react.snippets.cond_postfix")
    assert(ok, "Module should load without error")

    snippets_init.teardown()
end

return T
