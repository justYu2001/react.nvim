local helpers = require("tests.helpers")
local use_state = require("react.lsp.rename.use_state")

local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- Test setter name calculation
T["calculate_setter_name"] = new_set()

T["calculate_setter_name"]["converts camelCase state to setter"] = function()
    local result = use_state.calculate_setter_name("count")
    eq(result, "setCount")
end

T["calculate_setter_name"]["handles capitalized state names"] = function()
    local result = use_state.calculate_setter_name("isOpen")
    eq(result, "setIsOpen")
end

T["calculate_setter_name"]["handles single char"] = function()
    local result = use_state.calculate_setter_name("x")
    eq(result, "setX")
end

T["calculate_setter_name"]["handles empty string"] = function()
    local result = use_state.calculate_setter_name("")
    eq(result, "")
end

-- Test state name calculation
T["calculate_state_name"] = new_set()

T["calculate_state_name"]["converts setter to state"] = function()
    local result = use_state.calculate_state_name("setCount")
    eq(result, "count")
end

T["calculate_state_name"]["handles multi-word setters"] = function()
    local result = use_state.calculate_state_name("setIsOpen")
    eq(result, "isOpen")
end

T["calculate_state_name"]["handles single char after set"] = function()
    local result = use_state.calculate_state_name("setX")
    eq(result, "x")
end

T["calculate_state_name"]["returns nil for invalid setter"] = function()
    local result = use_state.calculate_state_name("count")
    eq(result, nil)
end

T["calculate_state_name"]["returns nil for lowercase after set"] = function()
    local result = use_state.calculate_state_name("setcount")
    eq(result, nil)
end

-- Test pattern detection (regex fallback)
T["is_state_variable"] = new_set()

T["is_state_variable"]["detects state variable with regex fallback"] = function()
    -- Create a buffer with useState code
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "const [count, setCount] = useState(0)" })

    -- Position cursor on "count" (row 1, col 7-11)
    local pos = { 1, 7 }
    local result = use_state.is_state_variable(bufnr, pos)

    eq(result.is_state, true)
    eq(result.state_name, "count")
    eq(result.setter_name, "setCount")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["is_state_variable"]["rejects non-setState pattern"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "const [count, updateCount] = useState(0)" })

    local pos = { 1, 7 }
    local result = use_state.is_state_variable(bufnr, pos)

    eq(result.is_state, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["is_state_variable"]["rejects when cursor not on state"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "const [count, setCount] = useState(0)" })

    -- Cursor on "const" instead of state var
    local pos = { 1, 0 }
    local result = use_state.is_state_variable(bufnr, pos)

    eq(result.is_state, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test setter detection
T["is_setter_variable"] = new_set()

T["is_setter_variable"]["detects setter variable with regex fallback"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "const [count, setCount] = useState(0)" })

    -- Position cursor on "setCount" (row 1, col 15-22)
    local pos = { 1, 16 }
    local result = use_state.is_setter_variable(bufnr, pos)

    eq(result.is_setter, true)
    eq(result.state_name, "count")
    eq(result.setter_name, "setCount")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["is_setter_variable"]["rejects non-setState pattern"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "const [count, updateCount] = useState(0)" })

    local pos = { 1, 16 }
    local result = use_state.is_setter_variable(bufnr, pos)

    eq(result.is_setter, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Test conflict detection
T["check_conflict"] = new_set()

T["check_conflict"]["detects existing identifier"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(
        bufnr,
        0,
        -1,
        false,
        { "const existing = 1", "const [count, setCount] = useState(0)" }
    )

    local has_conflict = use_state.check_conflict(bufnr, "existing")
    eq(has_conflict, true)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["check_conflict"]["returns false when no conflict"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "const [count, setCount] = useState(0)" })

    local has_conflict = use_state.check_conflict(bufnr, "newName")
    eq(has_conflict, false)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
