local helpers = require("tests.helpers")

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

-- Helper to invoke wrap_condition code action
local function trigger_wrap_condition(bufnr, row, col)
    local wrap_condition = require("react.code_actions.wrap_condition")
    local null_ls = { methods = { CODE_ACTION = "code_action" } }
    local source = wrap_condition.get_source(null_ls)

    local params = {
        bufnr = bufnr,
        row = row,
        col = col,
    }

    local actions = source.generator.fn(params)
    if not actions or #actions == 0 then
        return nil
    end

    return actions[1]
end

-- ============================================================
-- Single-line wrap
-- ============================================================
T["single-line element wrap"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div>content</div>;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 10 })
    local action = trigger_wrap_condition(bufnr, 2, 10)
    assert(action, "Expected code action")
    eq(action.title, "Wrap into condition")

    action.action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[2], "  return { && <div>content</div>};")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Multi-line wrap with parens
-- ============================================================
T["multi-line element wrap with parens"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return (",
        "    <div>",
        "      content",
        "    </div>",
        "  );",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 3, 5 })
    local action = trigger_wrap_condition(bufnr, 3, 5)
    assert(action, "Expected code action")

    action.action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[2], "  return (")
    eq(lines[3], "    { && (")
    eq(lines[4], "      <div>")
    eq(lines[5], "        content")
    eq(lines[6], "      </div>")
    eq(lines[7], "    )}")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Self-closing element
-- ============================================================
T["self-closing element wrap"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <Component />;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 10 })
    local action = trigger_wrap_condition(bufnr, 2, 10)
    assert(action, "Expected code action")

    action.action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[2], "  return { && <Component />};")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Fragment wrap
-- ============================================================
T["fragment wrap"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <>content</>;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 10 })
    local action = trigger_wrap_condition(bufnr, 2, 10)
    assert(action, "Expected code action")

    action.action()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[2], "  return { && <>content</>};")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Already wrapped (no action)
-- ============================================================
T["already wrapped shows no action"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return {x && <div>content</div>};",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 20 })
    local action = trigger_wrap_condition(bufnr, 2, 20)
    eq(action, nil, "Expected no code action for already wrapped element")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- Cursor positioning
-- ============================================================
T["cursor positioned after opening brace"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div>test</div>;",
        "}",
    })

    vim.api.nvim_win_set_cursor(0, { 2, 10 })
    local action = trigger_wrap_condition(bufnr, 2, 10)
    assert(action, "Expected code action")

    action.action()

    -- Wait for scheduled cursor positioning
    vim.wait(100)

    local cursor = vim.api.nvim_win_get_cursor(0)
    eq(cursor[1], 2) -- row (1-indexed)
    eq(cursor[2], 10) -- col after '{' (0-indexed)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
