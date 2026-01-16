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

return M
