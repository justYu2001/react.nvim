local ts = require("react.util.treesitter")
local utils = require("react.lsp.rename.utils")

local M = {}

---@param state_name string: state variable name
---@return string: setter name
function M.calculate_setter_name(state_name)
    if not state_name or state_name == "" then
        return ""
    end

    local capitalized = state_name:sub(1, 1):upper() .. state_name:sub(2)

    return "set" .. capitalized
end

---@param setter_name string: setter variable name
---@return string|nil: state name or nil if not valid setter
function M.calculate_state_name(setter_name)
    if not setter_name or not setter_name:match("^set%u") then
        return nil
    end

    local without_set = setter_name:sub(4)

    if without_set == "" then
        return nil
    end

    return without_set:sub(1, 1):lower() .. without_set:sub(2)
end

-- Pattern: const [state, setter] = useState(...) in one line
local use_state_pattern = "%s*const%s*%[%s*(%w+)%s*,%s*(set%u%w*)%s*%]%s*=%s*useState"

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table: {is_state: bool, setter_name: string, state_name: string}
function M.is_state_variable(bufnr, pos)
    local ts_result = ts.find_use_state_at_cursor(bufnr)

    if ts_result and ts_result.is_cursor_on_state then
        local expected_setter = M.calculate_setter_name(ts_result.state_var)

        if ts_result.setter_var == expected_setter then
            return {
                is_state = true,
                setter_name = ts_result.setter_var,
                state_name = ts_result.state_var,
            }
        end
    end

    -- Fallback to regex pattern matching
    local line = vim.api.nvim_buf_get_lines(bufnr, pos[1] - 1, pos[1], false)[1]

    if not line then
        return { is_state = false }
    end

    local state_var, setter_var = line:match(use_state_pattern)

    if state_var and setter_var then
        local expected_setter = M.calculate_setter_name(state_var)

        if setter_var == expected_setter then
            -- Check if cursor is on state variable
            local state_start = line:find(state_var, 1, true)
            local col = pos[2] + 1

            if state_start and col >= state_start and col < state_start + #state_var then
                return {
                    is_state = true,
                    setter_name = setter_var,
                    state_name = state_var,
                }
            end
        end
    end

    return { is_state = false }
end

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table: {is_setter: bool, state_name: string, setter_name: string}
function M.is_setter_variable(bufnr, pos)
    local ts_result = ts.find_use_state_at_cursor(bufnr)

    if ts_result and ts_result.is_cursor_on_setter then
        local expected_setter = M.calculate_setter_name(ts_result.state_var)

        if ts_result.setter_var == expected_setter then
            return {
                is_setter = true,
                setter_name = ts_result.setter_var,
                state_name = ts_result.state_var,
            }
        end
    end

    -- Fallback to regex pattern matching
    local line = vim.api.nvim_buf_get_lines(bufnr, pos[1] - 1, pos[1], false)[1]

    if not line then
        return { is_setter = false }
    end

    local state_var, setter_var = line:match(use_state_pattern)

    if state_var and setter_var then
        local expected_setter = M.calculate_setter_name(state_var)
        if setter_var == expected_setter then
            -- Check if cursor is on setter variable
            local setter_start = line:find(setter_var, 1, true)

            local col = pos[2] + 1

            if setter_start and col >= setter_start and col < setter_start + #setter_var then
                return {
                    is_setter = true,
                    setter_name = setter_var,
                    state_name = state_var,
                }
            end
        end
    end

    return { is_setter = false }
end

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table|nil: {is_state_rename: bool, secondary_old: string, state_name: string, setter_name: string}
function M.get_rename_context(bufnr, pos)
    local state_info = M.is_state_variable(bufnr, pos)
    local setter_info = M.is_setter_variable(bufnr, pos)

    if state_info.is_state then
        return {
            is_state_rename = true,
            secondary_old = state_info.setter_name,
            state_name = state_info.state_name,
            setter_name = state_info.setter_name,
        }
    elseif setter_info.is_setter then
        return {
            is_state_rename = false,
            secondary_old = setter_info.state_name,
            state_name = setter_info.state_name,
            setter_name = setter_info.setter_name,
        }
    end

    return nil
end

---@param new_primary string: new primary name
---@param is_state_rename boolean: true if renaming state, false if setter
---@return string|nil: secondary name
function M.calculate_secondary_from_primary(new_primary, is_state_rename)
    if is_state_rename then
        return M.calculate_setter_name(new_primary)
    else
        return M.calculate_state_name(new_primary)
    end
end

---@tag use_state.prepare_secondary_rename()
---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@param new_name string: new name for primary symbol
---@return table|nil: {secondary_old: string, secondary_name: string, references: table[]}
function M.prepare_secondary_rename(bufnr, pos, new_name)
    local context = M.get_rename_context(bufnr, pos)

    if not context then
        return nil
    end

    local secondary_name = M.calculate_secondary_from_primary(new_name, context.is_state_rename)

    if not secondary_name then
        return nil
    end

    if utils.check_conflict(bufnr, secondary_name) then
        vim.notify(
            string.format(
                "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                secondary_name
            ),
            vim.log.levels.WARN
        )
        return nil
    end

    local references = utils.find_references(bufnr, context.secondary_old)

    if #references == 0 then
        return nil
    end

    return {
        secondary_old = context.secondary_old,
        secondary_name = secondary_name,
        references = references,
    }
end

---@tag use_state.prepare_secondary_from_edit()
---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@param workspace_edit table: workspace edit from LSP
---@return table|nil: {secondary_old: string, secondary_name: string, references: table[]}
function M.prepare_secondary_from_edit(bufnr, pos, workspace_edit)
    local context = M.get_rename_context(bufnr, pos)

    if not context then
        return nil
    end

    local new_name = utils.extract_new_name_from_edit(workspace_edit)

    if not new_name then
        return nil
    end

    local secondary_name = M.calculate_secondary_from_primary(new_name, context.is_state_rename)

    if not secondary_name then
        return nil
    end

    if utils.check_conflict(bufnr, secondary_name) then
        vim.notify(
            string.format(
                "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                secondary_name
            ),
            vim.log.levels.WARN
        )
        return nil
    end

    local references = utils.find_references(bufnr, context.secondary_old)

    if #references == 0 then
        return nil
    end

    return {
        secondary_old = context.secondary_old,
        secondary_name = secondary_name,
        references = references,
    }
end

return M
