local M = {}

---@param workspace_edit table: workspace edit from LSP
---@return string|nil: new name from first edit
function M.extract_new_name_from_edit(workspace_edit)
    if workspace_edit.changes then
        for _, edits in pairs(workspace_edit.changes) do
            if edits[1] then
                return edits[1].newText
            end
        end
    elseif workspace_edit.documentChanges then
        for _, doc_change in ipairs(workspace_edit.documentChanges) do
            if doc_change.edits and doc_change.edits[1] then
                return doc_change.edits[1].newText
            end
        end
    end

    return nil
end

---@param bufnr number: buffer number
---@param symbol_name string: symbol to find
---@return table[]: array of LSP-like Location objects
function M.find_references(bufnr, symbol_name)
    if not symbol_name or symbol_name == "" then
        return {}
    end

    local uri = vim.uri_from_bufnr(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local locations = {}

    local pattern = "()(" .. vim.pesc(symbol_name) .. ")()"

    for row, line in ipairs(lines) do
        local search_start = 1

        while true do
            local match_start, _, match_end = line:match(pattern, search_start)

            if not match_start then
                break
            end

            local before_char = match_start > 1 and line:sub(match_start - 1, match_start - 1) or ""
            local after_char = line:sub(match_end, match_end) or ""

            local is_word_start = before_char == "" or not before_char:match("[%w_]")
            local is_word_end = after_char == "" or not after_char:match("[%w_]")

            if is_word_start and is_word_end then
                table.insert(locations, {
                    uri = uri,
                    range = {
                        start = { line = row - 1, character = match_start - 1 },
                        ["end"] = { line = row - 1, character = match_end - 1 },
                    },
                })
            end

            search_start = match_end
        end
    end

    return locations
end

---@param bufnr number: buffer number
---@param new_name string: proposed new name
---@return boolean: true if conflict exists
function M.check_conflict(bufnr, new_name)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local pattern = "%f[%w_]" .. vim.pesc(new_name) .. "%f[^%w_]"

    for _, line in ipairs(lines) do
        if line:match(pattern) then
            return true
        end
    end

    return false
end

return M
