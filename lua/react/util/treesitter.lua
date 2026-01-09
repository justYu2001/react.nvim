local M = {}

---@param bufnr number: buffer number
---@param lang string: language name (e.g., "javascript", "typescript")
---@return boolean: true if parser is available
function M.has_parser(bufnr, lang)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)

    return ok and parser ~= nil
end

---@param bufnr number: buffer number
---@return TSNode|nil: node at cursor or nil
function M.get_node_at_cursor(bufnr)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })

    if not ok then
        return nil
    end

    return node
end

--- Find useState pattern at cursor position
---
---@param bufnr number: buffer number
---@return table|nil: {state_var: string, setter_var: string, state_range: table, setter_range: table} or nil
function M.find_use_state_at_cursor(bufnr)
    -- Try to get language for buffer
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "javascript",
        typescriptreact = "typescript",
    }

    local lang = lang_map[ft]

    if not lang or not M.has_parser(bufnr, lang) then
        return nil
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)

    if not ok or not parser then
        return nil
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]

    local trees = parser:parse()

    if not trees or #trees == 0 then
        return nil
    end

    local root = trees[1]:root()

    local query_str = [[
        (variable_declarator
          (array_pattern
            (identifier) @state
            (identifier) @setter)
          (call_expression
            (identifier) @fn (#eq? @fn "useState")))
    ]]

    ok, query_str = pcall(vim.treesitter.query.parse, lang, query_str)

    if not ok then
        return nil
    end

    -- Find matches at cursor position
    for _, match, _ in query_str:iter_matches(root, bufnr) do
        -- Build capture map: name -> node
        local captures = {}

        for id, node_or_nodes in pairs(match) do
            local name = query_str.captures[id]

            local nodes = node_or_nodes

            if nodes[1] and type(nodes[1].range) == "function" then
                captures[name] = nodes[1]
            end
        end

        local state_node = captures["state"]
        local setter_node = captures["setter"]

        if state_node and setter_node then
            local state_start_row, state_start_col, state_end_row, state_end_col =
                state_node:range()
            local setter_start_row, setter_start_col, setter_end_row, setter_end_col =
                setter_node:range()

            local is_cursor_on_state = row == state_start_row
                and col >= state_start_col
                and col <= state_end_col

            local is_cursor_on_setter = row == setter_start_row
                and col >= setter_start_col
                and col <= setter_end_col

            if is_cursor_on_state or is_cursor_on_setter then
                local state_var = vim.treesitter.get_node_text(state_node, bufnr)
                local setter_var = vim.treesitter.get_node_text(setter_node, bufnr)

                return {
                    state_var = state_var,
                    setter_var = setter_var,
                    state_range = {
                        state_start_row,
                        state_start_col,
                        state_end_row,
                        state_end_col,
                    },
                    setter_range = {
                        setter_start_row,
                        setter_start_col,
                        setter_end_row,
                        setter_end_col,
                    },
                    is_cursor_on_state = is_cursor_on_state,
                    is_cursor_on_setter = is_cursor_on_setter,
                }
            end
        end
    end

    return nil
end

return M
