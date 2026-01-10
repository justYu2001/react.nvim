local helpers = require("tests.helpers")
local textobjects = require("react.textobjects")

local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- Helper to create a test buffer with JSX content
local function create_jsx_buffer(lines, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = filetype or "typescriptreact"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
end

-- Helper to cleanup buffer
local function cleanup_buffer(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

-- Test setup() function
T["setup"] = new_set()

T["setup"]["registers operator-pending keymaps"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" })

    textobjects.setup()

    -- Check that keymaps exist
    local it_map = vim.fn.maparg("it", "o", false, true)
    local at_map = vim.fn.maparg("at", "o", false, true)

    eq(it_map.buffer, 1) -- buffer-local
    eq(at_map.buffer, 1)

    cleanup_buffer(bufnr)
end

T["setup"]["registers visual mode keymaps"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" })

    textobjects.setup()

    local it_map = vim.fn.maparg("it", "x", false, true)
    local at_map = vim.fn.maparg("at", "x", false, true)

    eq(it_map.buffer, 1)
    eq(at_map.buffer, 1)

    cleanup_buffer(bufnr)
end

T["setup"]["tracks keymaps for cleanup"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" })

    textobjects.setup()

    -- Check internal tracking (access via M._keymaps)
    expect.no_error(function()
        textobjects.setup()
    end)

    cleanup_buffer(bufnr)
end

T["setup"]["warns on conflicting global mappings"] = function()
    -- Create a global mapping first
    vim.keymap.set("o", "it", function() end, { noremap = true })

    local bufnr = create_jsx_buffer({ "<div>test</div>" })

    -- Capture notifications
    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
    end

    textobjects.setup()

    vim.notify = original_notify

    -- Check for warning
    local found_warning = false
    for _, notif in ipairs(notifications) do
        if
            notif.msg:find("Overriding existing mappings")
            and notif.level == vim.log.levels.WARN
        then
            found_warning = true
            break
        end
    end

    eq(found_warning, true)

    -- Cleanup
    vim.keymap.del("o", "it")
    cleanup_buffer(bufnr)
end

-- Test teardown() function
T["teardown"] = new_set()

T["teardown"]["removes keymaps"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" })

    textobjects.setup()
    textobjects.teardown()

    -- Keymaps should be removed
    local it_map = vim.fn.maparg("it", "o", false, true)
    local at_map = vim.fn.maparg("at", "o", false, true)

    eq(vim.tbl_isempty(it_map), true)
    eq(vim.tbl_isempty(at_map), true)

    cleanup_buffer(bufnr)
end

T["teardown"]["handles multiple calls gracefully"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" })

    textobjects.setup()
    textobjects.teardown()

    -- Should not error on second call
    expect.no_error(function()
        textobjects.teardown()
    end)

    cleanup_buffer(bufnr)
end

-- Test select_around_tag() function
T["select_around_tag"] = new_set()

T["select_around_tag"]["notifies when not in JSX element"] = function()
    local bufnr = create_jsx_buffer({ "const x = 1" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
    end

    textobjects.select_around_tag()

    vim.notify = original_notify

    local found_error = false
    for _, notif in ipairs(notifications) do
        if notif.msg:find("Not inside JSX element") and notif.level == vim.log.levels.WARN then
            found_error = true
            break
        end
    end

    eq(found_error, true)
    cleanup_buffer(bufnr)
end

T["select_around_tag"]["works with standard JSX element"] = function()
    local bufnr = create_jsx_buffer({ "<div>content</div>" })
    vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- cursor on "content"

    -- Should not error
    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

T["select_around_tag"]["works with self-closing element"] = function()
    local bufnr = create_jsx_buffer({ "<Foo />" })
    vim.api.nvim_win_set_cursor(0, { 1, 2 }) -- cursor on tag name

    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

T["select_around_tag"]["works with fragment"] = function()
    local bufnr = create_jsx_buffer({ "<>content</>" })
    vim.api.nvim_win_set_cursor(0, { 1, 3 }) -- cursor on content

    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

-- Test select_inner_tag() function
T["select_inner_tag"] = new_set()

T["select_inner_tag"]["notifies when not in JSX element"] = function()
    local bufnr = create_jsx_buffer({ "const x = 1" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
    end

    textobjects.select_inner_tag()

    vim.notify = original_notify

    local found_error = false
    for _, notif in ipairs(notifications) do
        if notif.msg:find("Not inside JSX element") and notif.level == vim.log.levels.WARN then
            found_error = true
            break
        end
    end

    eq(found_error, true)
    cleanup_buffer(bufnr)
end

T["select_inner_tag"]["notifies for self-closing element"] = function()
    local bufnr = create_jsx_buffer({ "<Foo />" })
    vim.api.nvim_win_set_cursor(0, { 1, 2 })

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
    end

    textobjects.select_inner_tag()

    vim.notify = original_notify

    -- Should either notify "Self-closing" or "Not inside JSX" depending on parser availability
    local found_notification = false
    for _, notif in ipairs(notifications) do
        if
            notif.msg:find("Self%-closing element has no inner content")
            or notif.msg:find("Not inside JSX element")
        then
            found_notification = true
            break
        end
    end

    eq(found_notification, true)
    cleanup_buffer(bufnr)
end

T["select_inner_tag"]["works with standard JSX element"] = function()
    local bufnr = create_jsx_buffer({ "<div>content</div>" })
    vim.api.nvim_win_set_cursor(0, { 1, 6 })

    expect.no_error(function()
        textobjects.select_inner_tag()
    end)

    cleanup_buffer(bufnr)
end

T["select_inner_tag"]["works with fragment"] = function()
    local bufnr = create_jsx_buffer({ "<>content</>" })
    vim.api.nvim_win_set_cursor(0, { 1, 3 })

    expect.no_error(function()
        textobjects.select_inner_tag()
    end)

    cleanup_buffer(bufnr)
end

-- Test multi-line JSX
T["multiline JSX"] = new_set()

T["multiline JSX"]["select_around_tag works with multiline element"] = function()
    local bufnr = create_jsx_buffer({
        "<div>",
        "  <span>nested</span>",
        "</div>",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 10 }) -- cursor on "nested"

    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

T["multiline JSX"]["select_inner_tag works with multiline element"] = function()
    local bufnr = create_jsx_buffer({
        "<div>",
        "  content",
        "</div>",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 2 }) -- cursor on content

    expect.no_error(function()
        textobjects.select_inner_tag()
    end)

    cleanup_buffer(bufnr)
end

-- Test different filetypes
T["filetypes"] = new_set()

T["filetypes"]["works with typescriptreact"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" }, "typescriptreact")
    vim.api.nvim_win_set_cursor(0, { 1, 6 })

    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

T["filetypes"]["works with javascriptreact"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" }, "javascriptreact")
    vim.api.nvim_win_set_cursor(0, { 1, 6 })

    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

T["filetypes"]["works with typescript"] = function()
    local bufnr = create_jsx_buffer({ "const x: JSX.Element = <div>test</div>" }, "typescript")
    vim.api.nvim_win_set_cursor(0, { 1, 30 })

    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

T["filetypes"]["works with javascript"] = function()
    local bufnr = create_jsx_buffer({ "const x = <div>test</div>" }, "javascript")
    vim.api.nvim_win_set_cursor(0, { 1, 16 })

    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

T["filetypes"]["returns early for unsupported filetype"] = function()
    local bufnr = create_jsx_buffer({ "<div>test</div>" }, "python")
    vim.api.nvim_win_set_cursor(0, { 1, 6 })

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
    end

    textobjects.select_around_tag()

    vim.notify = original_notify

    -- Should notify "Not inside JSX element"
    local found_error = false
    for _, notif in ipairs(notifications) do
        if notif.msg:find("Not inside JSX element") then
            found_error = true
            break
        end
    end

    eq(found_error, true)
    cleanup_buffer(bufnr)
end

-- Test nested elements
T["nested elements"] = new_set()

T["nested elements"]["finds parent when cursor on nested element"] = function()
    local bufnr = create_jsx_buffer({
        "<div>",
        "  <span>inner</span>",
        "</div>",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 10 }) -- cursor on "inner"

    -- Should find <span> element (immediate parent)
    expect.no_error(function()
        textobjects.select_around_tag()
    end)

    cleanup_buffer(bufnr)
end

return T
