local use_state = require("react.lsp.rename.use_state")
local props = require("react.lsp.rename.props")
local component_props = require("react.lsp.rename.component_props")
local utils = require("react.lsp.rename.utils")
local ui = require("react.ui.select")
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
        -- Interactive rename not yet supported for useState
        -- TODO: Could enhance to support interactive rename + auto-setter
        log.debug("rename", "Interactive rename not yet supported, using original")

        return M._original_rename(new_name, opts)
    end

    -- Check component-props rename first
    local cp_info = component_props.prepare_secondary_rename(bufnr, pos, new_name)
    if cp_info then
        log.debug("rename", "Detected component-props pattern")
        log.debug("rename", "Will rename %s → %s", cp_info.secondary_old, cp_info.secondary_name)

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
                cp_info.references,
                cp_info.secondary_old,
                cp_info.secondary_name
            )

            log.debug(
                "rename",
                "Added %d edits for %s→%s",
                #cp_info.references,
                cp_info.secondary_old,
                cp_info.secondary_name
            )

            -- Apply combined edit
            vim.lsp.util.apply_workspace_edit(workspace_edit, offset_encoding)
        end)

        return
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

    local props_info = props.detect_prop_at_cursor(bufnr, pos)

    if props_info and props_info.is_prop then
        return M.handle_props_workspace_edit(workspace_edit, bufnr, pos, props_info)
    end

    -- Check component-props rename
    local cp_info = component_props.prepare_secondary_from_edit(bufnr, pos, workspace_edit)
    if cp_info then
        log.debug("rename.hook", "Detected component-props pattern in workspace edit")

        -- Clone workspace_edit and add secondary edits
        local enhanced_edit = vim.deepcopy(workspace_edit)
        M.add_secondary_edits(
            enhanced_edit,
            cp_info.references,
            cp_info.secondary_old,
            cp_info.secondary_name
        )

        log.debug(
            "rename.hook",
            "Added %d edits for %s→%s",
            #cp_info.references,
            cp_info.secondary_old,
            cp_info.secondary_name
        )

        return enhanced_edit
    end

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

---@param workspace_edit table
---@param bufnr number
---@param pos table
---@param props_info table
---@return table|nil
function M.handle_props_workspace_edit(workspace_edit, bufnr, pos, props_info)
    local new_name = utils.extract_new_name_from_edit(workspace_edit)

    if not new_name then
        return nil
    end

    local component_info = props.find_component_for_prop(bufnr, props_info.prop_name, pos)

    local destructure_info =
        props.find_destructure_location(bufnr, component_info, props_info.prop_name)

    if not destructure_info.found then
        return nil -- Not destructured, use normal rename
    end

    -- For shorthand destructuring, LSP creates "oldName: newName"
    -- We need to extract just the newName part
    -- Check cursor_target for destructure context, or is_aliased for body context
    if
        props_info.cursor_target == "shorthand"
        or (props_info.context == "body" and not destructure_info.is_aliased)
    then
        local colon_pos = new_name:find(": ")

        if colon_pos then
            new_name = new_name:sub(colon_pos + 2) -- Extract part after ": "
        end
    end

    -- Store context for deferred handling
    M._pending_props_edit = {
        workspace_edit = workspace_edit,
        bufnr = bufnr,
        props_info = props_info,
        component_info = component_info,
        destructure_info = destructure_info,
        new_name = new_name,
        cursor_context = (function()
            local identifier_at_cursor = props_info.prop_name

            if props_info.cursor_target == "alias" and destructure_info.current_alias then
                identifier_at_cursor = destructure_info.current_alias
            end

            local offset = props.calculate_cursor_offset(bufnr, pos, identifier_at_cursor) or 0

            return {
                original_pos = pos,
                offset_in_prop = offset,
                original_window = vim.api.nvim_get_current_win(),
            }
        end)(),
    }

    -- Defer menu to after hook returns
    vim.schedule(function()
        M.show_deferred_props_menu()
    end)

    -- Return marker to skip original apply
    return { _react_handled = true }
end

---@param pending table pending props edit context
---@param offset_encoding string LSP offset encoding
function M.apply_direct_from_workspace_edit(pending, offset_encoding)
    local lsp_init = require("react.lsp")

    -- Apply first edit (from inc-rename)
    lsp_init._original_apply_workspace_edit(pending.workspace_edit, offset_encoding)

    -- Wait for buffer to update, then do second rename
    vim.schedule(function()
        local alias_pos = props.find_alias_variable_position(
            pending.component_info.bufnr or pending.bufnr,
            pending.destructure_info.range,
            pending.props_info.prop_name
        )

        if alias_pos then
            local params = {
                textDocument = {
                    uri = vim.uri_from_bufnr(pending.component_info.bufnr or pending.bufnr),
                },
                position = alias_pos,
                newName = pending.new_name,
            }

            vim.lsp.buf_request_all(
                pending.component_info.bufnr or pending.bufnr,
                "textDocument/rename",
                params,
                function(results)
                    local second_edit = M.merge_workspace_edits(results)

                    if not second_edit then
                        log.debug("rename.inc", "No workspace edit returned from second rename")
                        return
                    end

                    -- Apply second edit (creates { bar: bar })
                    lsp_init._original_apply_workspace_edit(second_edit, offset_encoding)

                    -- Convert { bar: bar } to { bar } after edit is applied
                    vim.schedule(function()
                        local target_bufnr = pending.component_info.bufnr or pending.bufnr
                        props.convert_to_shorthand_in_buffer(target_bufnr, pending.new_name)

                        -- Restore cursor position
                        if pending.cursor_context then
                            props.restore_cursor_position(
                                target_bufnr,
                                pending.cursor_context.original_window,
                                pending.new_name,
                                pending.cursor_context.original_pos,
                                pending.cursor_context.offset_in_prop
                            )
                        end
                    end)
                end
            )
        end
    end)
end

---@param pending table pending props edit context
---@param offset_encoding string LSP offset encoding
function M.apply_direct_from_destructure_inc_rename(pending, offset_encoding)
    local lsp_init = require("react.lsp")
    local target_bufnr = pending.component_info.bufnr or pending.bufnr

    -- Apply first edit (from inc-rename)
    lsp_init._original_apply_workspace_edit(pending.workspace_edit, offset_encoding)

    -- Wait for buffer to update, then do second rename
    vim.schedule(function()
        local second_pos

        if pending.props_info.cursor_target == "shorthand" then
            -- Shorthand: after first rename { oldName: newName }
            -- For inc-rename, we need to find the key position
            -- since we don't have the original cursor position
            second_pos = props.find_key_position(
                target_bufnr,
                pending.destructure_info.range,
                pending.props_info.prop_name
            )
        elseif pending.props_info.cursor_target == "key" then
            -- Key in pair: after first rename { newName: alias }
            -- Find alias position
            second_pos = props.find_alias_variable_position(
                target_bufnr,
                pending.destructure_info.range,
                pending.destructure_info.current_alias
            )
        elseif pending.props_info.cursor_target == "alias" then
            -- Alias in pair: after first rename { oldKey: newName }
            -- Find key position
            second_pos = props.find_key_position(
                target_bufnr,
                pending.destructure_info.range,
                pending.props_info.prop_name
            )
        end

        if second_pos then
            local params = {
                textDocument = {
                    uri = vim.uri_from_bufnr(target_bufnr),
                },
                position = second_pos,
                newName = pending.new_name,
            }

            vim.lsp.buf_request_all(target_bufnr, "textDocument/rename", params, function(results)
                local second_edit = M.merge_workspace_edits(results)

                if not second_edit then
                    log.debug("rename.inc", "No workspace edit returned from second rename")
                    return
                end

                -- Apply second edit (creates { newName: newName })
                lsp_init._original_apply_workspace_edit(second_edit, offset_encoding)

                -- Convert { newName: newName } to { newName }
                vim.schedule(function()
                    props.convert_to_shorthand_in_buffer(target_bufnr, pending.new_name)

                    if pending.cursor_context then
                        props.restore_cursor_position(
                            target_bufnr,
                            pending.cursor_context.original_window,
                            pending.new_name,
                            pending.cursor_context.original_pos,
                            pending.cursor_context.offset_in_prop
                        )
                    end
                end)
            end)
        end
    end)
end

---@param pending table
---@param offset_encoding string
function M.apply_direct_from_body_inc_rename(pending, offset_encoding)
    local lsp_init = require("react.lsp")
    local target_bufnr = pending.component_info.bufnr or pending.bufnr

    -- Apply first edit (from inc-rename, renames body + destructuring)
    lsp_init._original_apply_workspace_edit(pending.workspace_edit, offset_encoding)

    -- Wait for buffer to update, then do second rename on key
    vim.schedule(function()
        -- Find key position using original key name (from check_body_variable)
        local second_pos = props.find_key_position(
            target_bufnr,
            pending.destructure_info.range,
            pending.props_info.prop_name
        )

        if second_pos then
            local params = {
                textDocument = {
                    uri = vim.uri_from_bufnr(target_bufnr),
                },
                position = second_pos,
                newName = pending.new_name,
            }

            vim.lsp.buf_request_all(target_bufnr, "textDocument/rename", params, function(results)
                local second_edit = M.merge_workspace_edits(results)

                if not second_edit then
                    log.debug("rename.inc", "No workspace edit returned from second rename")
                    return
                end

                -- Apply second edit (creates { newName: newName })
                lsp_init._original_apply_workspace_edit(second_edit, offset_encoding)

                -- Convert { newName: newName } to { newName }
                vim.schedule(function()
                    props.convert_to_shorthand_in_buffer(target_bufnr, pending.new_name)

                    -- Restore cursor position
                    if pending.cursor_context then
                        props.restore_cursor_position(
                            target_bufnr,
                            pending.cursor_context.original_window,
                            pending.new_name,
                            pending.cursor_context.original_pos,
                            pending.cursor_context.offset_in_prop
                        )
                    end
                end)
            end)
        end
    end)
end

--- Show deferred props rename menu after renaming
function M.show_deferred_props_menu()
    local pending = M._pending_props_edit

    if not pending then
        return
    end

    M._pending_props_edit = nil

    local clients = vim.lsp.get_clients({ bufnr = pending.bufnr })
    local offset_encoding = clients[1] and clients[1].offset_encoding or "utf-16"
    local lsp_init = require("react.lsp")

    ui.show_rename_menu(
        pending.props_info.prop_name,
        pending.new_name,
        pending.props_info.context,
        function(choice)
            -- Temporarily restore original apply_workspace_edit to avoid recursion
            local current = vim.lsp.util.apply_workspace_edit
            vim.lsp.util.apply_workspace_edit = lsp_init._original_apply_workspace_edit

            if choice == "alias" then
                vim.lsp.util.apply_workspace_edit(pending.workspace_edit, offset_encoding)

                -- Restore cursor position for alias choice
                -- When alias chosen: abc->xyz becomes { abc: xyz }
                -- Key stays original name, cursor stays on key
                vim.schedule(function()
                    if pending.cursor_context then
                        local target_bufnr = pending.component_info.bufnr or pending.bufnr

                        props.restore_cursor_position(
                            target_bufnr,
                            pending.cursor_context.original_window,
                            pending.props_info.prop_name, -- original name (still the key)
                            pending.cursor_context.original_pos,
                            pending.cursor_context.offset_in_prop
                        )
                    end
                end)
            else
                if pending.props_info.context == "destructure" then
                    M.apply_direct_from_destructure_inc_rename(pending, offset_encoding)
                elseif pending.props_info.context == "body" then
                    M.apply_direct_from_body_inc_rename(pending, offset_encoding)
                else
                    M.apply_direct_from_workspace_edit(pending, offset_encoding)
                end
            end

            -- Restore hook
            vim.lsp.util.apply_workspace_edit = current
        end
    )
end

return M
