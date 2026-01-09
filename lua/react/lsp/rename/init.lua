local use_state = require("react.lsp.rename.use_state")
local log = require("react.util.log")

local M = {}

M._original_rename = vim.lsp.buf.rename

--- Enhanced rename with useState setter/state auto-renaming
---
---@param new_name string|nil: new name for the symbol
---@param opts table|nil: additional options
function M.rename(new_name, opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)

    if not new_name then
        -- Interactive rename not yet supported
        -- TODO: Could enhance to support interactive rename + auto-setter
        log.debug("rename", "Interactive rename not yet supported, using original")

        return M._original_rename(new_name, opts)
    end

    local rename_info = use_state.prepare_secondary_rename(bufnr, pos, new_name)

    if not rename_info then
        return M._original_rename(new_name, opts)
    end

    log.debug("rename", "Detected useState pattern")

    log.debug(
        "rename",
        "Will rename %s → %s",
        rename_info.secondary_old,
        rename_info.secondary_name
    )

    -- Build LSP params for primary rename
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    local offset_encoding = clients[1] and clients[1].offset_encoding or "utf-16"
    local params = vim.lsp.util.make_position_params(0, offset_encoding)
    params.newName = new_name

    -- Request primary rename from all clients
    vim.lsp.buf_request_all(bufnr, "textDocument/rename", params, function(results)
        -- Merge workspace edits from all LSP clients
        local workspace_edit = M.merge_workspace_edits(results)

        if not workspace_edit then
            log.debug("rename", "No workspace edit returned")
            return
        end

        -- Add secondary edits
        M.add_secondary_edits(
            workspace_edit,
            rename_info.references,
            rename_info.secondary_old,
            rename_info.secondary_name
        )

        log.debug(
            "rename",
            "Added %d edits for %s→%s",
            #rename_info.references,
            rename_info.secondary_old,
            rename_info.secondary_name
        )

        -- Apply combined edit
        vim.lsp.util.apply_workspace_edit(workspace_edit, offset_encoding)
    end)
end

---@param results table: results from vim.lsp.buf_request_all
---@return table|nil: merged workspace edit or nil
function M.merge_workspace_edits(results)
    if not results or vim.tbl_isempty(results) then
        return nil
    end

    local merged = {
        changes = {},
        documentChanges = {},
    }

    local has_changes = false
    local has_doc_changes = false

    for _, result in pairs(results) do
        if result.result then
            local edit = result.result

            -- Merge changes (uri -> TextEdit[])
            if edit.changes then
                has_changes = true

                for uri, text_edits in pairs(edit.changes) do
                    if not merged.changes[uri] then
                        merged.changes[uri] = {}
                    end

                    vim.list_extend(merged.changes[uri], text_edits)
                end
            end

            -- Merge documentChanges
            if edit.documentChanges then
                has_doc_changes = true

                vim.list_extend(merged.documentChanges, edit.documentChanges)
            end
        end
    end

    -- Return appropriate format
    if not has_changes and not has_doc_changes then
        return nil
    end

    -- Prefer documentChanges if available
    if has_doc_changes then
        merged.changes = nil
        return merged
    end

    merged.documentChanges = nil
    return merged
end

---@param workspace_edit table: workspace edit to modify
---@param locations table[]: LSP Location objects
---@param _old_name string: old symbol name (unused, uses locations)
---@param new_name string: new symbol name
function M.add_secondary_edits(workspace_edit, locations, _old_name, new_name)
    -- Convert locations to TextEdit objects and add to workspace_edit
    for _, location in ipairs(locations) do
        local uri = location.uri
        local range = location.range

        -- Create TextEdit
        local text_edit = {
            range = range,
            newText = new_name,
        }

        -- Add to workspace_edit.changes
        if workspace_edit.changes then
            if not workspace_edit.changes[uri] then
                workspace_edit.changes[uri] = {}
            end

            table.insert(workspace_edit.changes[uri], text_edit)
        elseif workspace_edit.documentChanges then
            -- Find or create TextDocumentEdit for this uri
            local found = false

            for _, doc_change in ipairs(workspace_edit.documentChanges) do
                if doc_change.textDocument and doc_change.textDocument.uri == uri then
                    table.insert(doc_change.edits, text_edit)
                    found = true
                    break
                end
            end

            if not found then
                -- Create new TextDocumentEdit
                table.insert(workspace_edit.documentChanges, {
                    textDocument = {
                        uri = uri,
                        version = vim.NIL, -- Use NIL to indicate we don't know version
                    },
                    edits = { text_edit },
                })
            end
        end
    end
end

--- Try to add useState secondary edits to workspace edit if applicable
--- Called during apply_workspace_edit hook for inc-rename integration
---
---@param workspace_edit table: workspace edit from LSP
---@return table|nil: enhanced workspace edit or nil if not useState
function M.try_add_use_state_edits(workspace_edit)
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)

    local rename_info = use_state.prepare_secondary_from_edit(bufnr, pos, workspace_edit)

    if not rename_info then
        return nil
    end

    log.debug("rename.hook", "Detected useState pattern in workspace edit")

    -- Clone workspace_edit and add secondary edits
    local enhanced_edit = vim.deepcopy(workspace_edit)
    M.add_secondary_edits(
        enhanced_edit,
        rename_info.references,
        rename_info.secondary_old,
        rename_info.secondary_name
    )

    log.debug(
        "rename.hook",
        "Added %d edits for %s→%s",
        #rename_info.references,
        rename_info.secondary_old,
        rename_info.secondary_name
    )

    return enhanced_edit
end

return M
