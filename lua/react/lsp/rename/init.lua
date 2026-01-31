local use_state = require("react.lsp.rename.use_state")
local props = require("react.lsp.rename.props")
local component_props = require("react.lsp.rename.component_props")
local utils = require("react.lsp.rename.utils")
local ui = require("react.ui.select")
local log = require("react.util.log")

local M = {}

M._original_rename = vim.lsp.buf.rename
M._is_rename_operation = false

--- Enhanced rename with useState setter/state auto-renaming
---
---@param new_name string|nil: new name for the symbol
---@param opts table|nil: additional options
function M.rename(new_name, opts)
    M._is_rename_operation = true
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)

    if not new_name then
        -- Interactive rename not yet supported for useState
        -- TODO: Could enhance to support interactive rename + auto-setter
        log.debug("rename", "Interactive rename not yet supported, using original")
        M._is_rename_operation = false

        return M._original_rename(new_name, opts)
    end

    -- Check cross-file component rename first
    local cross_file_info = component_props.detect_cross_file_scenario(bufnr, pos)
    if cross_file_info and cross_file_info.is_cross_file then
        -- For named imports, show menu for direct vs alias
        if cross_file_info.import_type == "named" or cross_file_info.scenario == "usage" then
            local old_name = cross_file_info.component_name
            log.debug(
                "rename",
                "Detected cross-file component rename: %s → %s",
                old_name,
                new_name
            )

            ui.show_cross_file_rename_menu(old_name, new_name, function(choice)
                if choice == "alias" then
                    M._original_rename(new_name, opts)
                else
                    M.handle_cross_file_direct_rename(cross_file_info, bufnr, pos, new_name)
                end
                M._is_rename_operation = false
            end)
            return
        else
            -- Default import: just use normal LSP rename (already direct)
            log.debug("rename", "Default import rename, using original")
            M._is_rename_operation = false
            return M._original_rename(new_name, opts)
        end
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
                M._is_rename_operation = false
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
            M._is_rename_operation = false
        end)

        return
    end

    local rename_info = use_state.prepare_secondary_rename(bufnr, pos, new_name)

    if not rename_info then
        M._is_rename_operation = false
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
            M._is_rename_operation = false
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
        M._is_rename_operation = false
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

--- Check if workspace edit looks like a rename operation at cursor
---@param workspace_edit table
---@param bufnr number
---@param pos table cursor position {row, col}
---@return boolean
local function is_likely_rename_operation(workspace_edit, bufnr, pos)
    local uri = vim.uri_from_bufnr(bufnr)
    local row, col = pos[1] - 1, pos[2] -- Convert to 0-indexed

    local edits = {}
    if workspace_edit.changes and workspace_edit.changes[uri] then
        edits = workspace_edit.changes[uri]
    elseif workspace_edit.documentChanges then
        for _, doc_change in ipairs(workspace_edit.documentChanges) do
            if
                doc_change.textDocument
                and doc_change.textDocument.uri == uri
                and doc_change.edits
            then
                edits = doc_change.edits
                break
            end
        end
    end

    -- Check if any edit touches the cursor position
    for _, edit in ipairs(edits) do
        local range = edit.range
        local start_row, start_col = range.start.line, range.start.character
        local end_row, end_col = range["end"].line, range["end"].character

        -- Check if cursor is within or adjacent to the edit range
        if row >= start_row and row <= end_row then
            if row == start_row and row == end_row then
                if col >= start_col and col <= end_col then
                    return true
                end
            elseif row == start_row then
                if col >= start_col then
                    return true
                end
            elseif row == end_row then
                if col <= end_col then
                    return true
                end
            else
                return true
            end
        end
    end

    return false
end

--- Try to add useState secondary edits to workspace edit if applicable
--- Called during apply_workspace_edit hook for inc-rename integration
---
---@param workspace_edit table: workspace edit from LSP
---@return table|nil: enhanced workspace edit or nil if not useState
function M.try_add_use_state_edits(workspace_edit)
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)

    -- Only process if this is a rename operation
    -- Either explicitly flagged (M.rename called) or looks like inc-rename at cursor
    if not M._is_rename_operation then
        if not is_likely_rename_operation(workspace_edit, bufnr, pos) then
            return nil
        end
        -- Set flag for inc-rename operations
        M._is_rename_operation = true
    end

    -- Check cross-file component rename FIRST (before props)
    -- This is important because import identifiers might match prop patterns
    local cross_file_info = component_props.detect_cross_file_scenario(bufnr, pos)

    if cross_file_info and cross_file_info.is_cross_file then
        -- For named imports, defer menu to user
        if cross_file_info.import_type == "named" or cross_file_info.scenario == "usage" then
            local new_name = utils.extract_new_name_from_edit(workspace_edit)
            if new_name then
                M._pending_cross_file_edit = {
                    workspace_edit = workspace_edit,
                    cross_file_info = cross_file_info,
                    bufnr = bufnr,
                    pos = pos,
                    new_name = new_name,
                }
                vim.schedule(function()
                    M.show_deferred_cross_file_menu()
                end)
                return { _react_handled = true }
            end
        end
    end

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

                        M._is_rename_operation = false
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

                    M._is_rename_operation = false
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

                    M._is_rename_operation = false
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
                    M._is_rename_operation = false
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

---@param bufnr number
---@param new_name string
function M.cleanup_import_alias(bufnr, new_name)
    local ft = vim.bo[bufnr].filetype
    local lang_map = {
        typescript = "typescript",
        typescriptreact = "tsx",
        javascript = "javascript",
        javascriptreact = "tsx",
    }

    local lang = lang_map[ft]
    if not lang then
        return
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then
        return
    end

    local trees = parser:parse()
    if not trees or #trees == 0 then
        return
    end

    local root = trees[1]:root()

    -- Find import_specifier with pattern { NewName as NewName }
    local function traverse(node)
        if node:type() == "import_specifier" then
            local name_node = nil
            local alias_node = nil

            for child in node:iter_children() do
                if child:type() == "identifier" then
                    if not name_node then
                        name_node = child
                    else
                        alias_node = child
                    end
                end
            end

            if name_node and alias_node then
                local name = vim.treesitter.get_node_text(name_node, bufnr)
                local alias = vim.treesitter.get_node_text(alias_node, bufnr)

                if name == new_name and alias == new_name then
                    -- Replace entire import_specifier with just the name
                    local start_row, start_col, end_row, end_col = node:range()
                    vim.api.nvim_buf_set_text(
                        bufnr,
                        start_row,
                        start_col,
                        end_row,
                        end_col,
                        { new_name }
                    )
                    return true
                end
            end
        end

        for child in node:iter_children() do
            if traverse(child) then
                return true
            end
        end

        return false
    end

    traverse(root)
end

---@param import_bufnr number: buffer containing component
---@param component_name string: component name
---@param new_name string: new component name
function M.rename_props_in_buffer(import_bufnr, component_name, new_name)
    -- Check if TypeScript file
    local filetype = vim.api.nvim_buf_get_option(import_bufnr, "filetype")
    if filetype ~= "typescript" and filetype ~= "typescriptreact" then
        return
    end

    local old_props_type = component_props.calculate_props_type_name(component_name)
    local new_props_type = component_props.calculate_props_type_name(new_name)

    -- Check if the type exists by finding references in the imported file
    local references = utils.find_references(import_bufnr, old_props_type)

    if #references == 0 then
        return
    end

    -- Check if props type is shared
    if component_props.is_type_shared(import_bufnr, old_props_type) then
        vim.notify(
            string.format(
                "[react.nvim] Props type '%s' is used by multiple components. Skipping auto-rename.",
                old_props_type
            ),
            vim.log.levels.WARN
        )
        return
    end

    -- Check for conflicts
    if utils.check_conflict(import_bufnr, new_props_type) then
        vim.notify(
            string.format(
                "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                new_props_type
            ),
            vim.log.levels.WARN
        )
        return
    end

    log.debug(
        "rename.cross-file",
        "Renaming props type in imported file: %s → %s",
        old_props_type,
        new_props_type
    )

    -- Build workspace edit for props rename
    local props_edit = { changes = {} }
    for _, location in ipairs(references) do
        local uri = location.uri
        if not props_edit.changes[uri] then
            props_edit.changes[uri] = {}
        end
        table.insert(props_edit.changes[uri], {
            range = location.range,
            newText = new_props_type,
        })
    end

    -- Apply props rename using original to avoid hook
    local lsp_init = require("react.lsp")
    local clients = vim.lsp.get_clients({ bufnr = import_bufnr })
    local offset_encoding = clients[1] and clients[1].offset_encoding or "utf-16"
    lsp_init._original_apply_workspace_edit(props_edit, offset_encoding)
end

---@param current_bufnr number: current buffer with the import
---@param import_path string: relative import path like "./Rename"
---@param component_name string
---@param new_name string
function M.maybe_rename_props_in_imported_file(current_bufnr, import_path, component_name, new_name)
    -- Resolve import path to actual file
    local current_file = vim.api.nvim_buf_get_name(current_bufnr)
    local current_dir = vim.fn.fnamemodify(current_file, ":h")
    local resolved_path = vim.fn.resolve(current_dir .. "/" .. import_path)

    -- Try common extensions
    local extensions = { ".tsx", ".ts", ".jsx", ".js" }
    local import_file = nil

    for _, ext in ipairs(extensions) do
        local try_path = resolved_path .. ext
        if vim.fn.filereadable(try_path) == 1 then
            import_file = try_path
            break
        end
    end

    if not import_file then
        return
    end

    -- Load the imported file buffer
    local import_bufnr = vim.fn.bufadd(import_file)
    vim.fn.bufload(import_bufnr)

    -- Delegate to helper
    M.rename_props_in_buffer(import_bufnr, component_name, new_name)
end

---@param bufnr number
---@param component_name string
---@param new_name string
function M.maybe_rename_props_same_file(bufnr, component_name, new_name)
    -- Check if TypeScript file
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    if filetype ~= "typescript" and filetype ~= "typescriptreact" then
        return
    end

    -- Check if props type exists in current file (not component itself)
    -- We're renaming an import, so check if the props type exists here
    local old_props_type = component_props.calculate_props_type_name(component_name)
    local new_props_type = component_props.calculate_props_type_name(new_name)

    -- Check if the type exists by finding references
    local references = utils.find_references(bufnr, old_props_type)

    if #references == 0 then
        return
    end

    -- Check if props type is shared
    if component_props.is_type_shared(bufnr, old_props_type) then
        vim.notify(
            string.format(
                "[react.nvim] Props type '%s' is used by multiple components. Skipping auto-rename.",
                old_props_type
            ),
            vim.log.levels.WARN
        )
        return
    end

    -- Check for conflicts
    if utils.check_conflict(bufnr, new_props_type) then
        vim.notify(
            string.format(
                "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                new_props_type
            ),
            vim.log.levels.WARN
        )
        return
    end

    log.debug("rename.cross-file", "Renaming props type: %s → %s", old_props_type, new_props_type)

    -- Build workspace edit for props rename
    local props_edit = { changes = {} }
    for _, location in ipairs(references) do
        local uri = location.uri
        if not props_edit.changes[uri] then
            props_edit.changes[uri] = {}
        end
        table.insert(props_edit.changes[uri], {
            range = location.range,
            newText = new_props_type,
        })
    end

    -- Apply props rename using original to avoid hook
    local lsp_init = require("react.lsp")
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    local offset_encoding = clients[1] and clients[1].offset_encoding or "utf-16"
    lsp_init._original_apply_workspace_edit(props_edit, offset_encoding)
end

---@param bufnr number
---@param component_name string
---@param new_name string
---@param import_info table|nil
function M.maybe_rename_props_cross_file(bufnr, component_name, new_name, import_info)
    -- Only rename props if component is in same file as current buffer
    if not import_info or not import_info.component_info then
        return
    end

    local component_bufnr = import_info.component_info.bufnr
    if component_bufnr ~= bufnr then
        log.debug("rename.cross-file", "Skipping props rename: component in different file")
        return
    end

    -- Check TypeScript file
    local filetype = vim.api.nvim_buf_get_option(component_bufnr, "filetype")
    if filetype ~= "typescript" and filetype ~= "typescriptreact" then
        return
    end

    local old_props_type = component_props.calculate_props_type_name(component_name)
    local new_props_type = component_props.calculate_props_type_name(new_name)

    -- Check if props type is shared
    if component_props.is_type_shared(component_bufnr, old_props_type) then
        vim.notify(
            string.format(
                "[react.nvim] Props type '%s' is used by multiple components. Skipping auto-rename.",
                old_props_type
            ),
            vim.log.levels.WARN
        )
        return
    end

    -- Check for conflicts
    if utils.check_conflict(component_bufnr, new_props_type) then
        vim.notify(
            string.format(
                "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                new_props_type
            ),
            vim.log.levels.WARN
        )
        return
    end

    -- Find references and rename
    local references = utils.find_references(component_bufnr, old_props_type)
    if #references > 0 then
        log.debug(
            "rename.cross-file",
            "Renaming props type: %s → %s",
            old_props_type,
            new_props_type
        )

        -- Build workspace edit for props rename
        local props_edit = { changes = {} }
        for _, location in ipairs(references) do
            local uri = location.uri
            if not props_edit.changes[uri] then
                props_edit.changes[uri] = {}
            end
            table.insert(props_edit.changes[uri], {
                range = location.range,
                newText = new_props_type,
            })
        end

        -- Apply props rename using original to avoid hook
        local lsp_init = require("react.lsp")
        local clients = vim.lsp.get_clients({ bufnr = component_bufnr })
        local offset_encoding = clients[1] and clients[1].offset_encoding or "utf-16"
        lsp_init._original_apply_workspace_edit(props_edit, offset_encoding)
    end
end

---@param cross_file_info table
---@param bufnr number
---@param pos table
---@param new_name string
function M.handle_cross_file_direct_rename(cross_file_info, bufnr, pos, new_name)
    log.debug(
        "rename.cross-file",
        "Starting direct rename: %s → %s",
        cross_file_info.component_name,
        new_name
    )

    -- Get original apply_workspace_edit to avoid recursion
    local lsp_init = require("react.lsp")
    local original_apply = lsp_init._original_apply_workspace_edit

    local original_bufnr = bufnr
    local original_win = vim.api.nvim_get_current_win()
    local original_pos = pos -- Save original position before it gets overwritten
    local should_restore_cursor = false -- Only restore if we moved cursor

    -- For usage scenario, find the import first
    local import_pos = nil
    if cross_file_info.scenario == "usage" then
        should_restore_cursor = true -- We'll move cursor, need to restore
        -- Find import statement for this component
        local ft = vim.bo[bufnr].filetype
        local lang_map = {
            typescript = "typescript",
            typescriptreact = "tsx",
            javascript = "javascript",
            javascriptreact = "tsx",
        }
        local lang = lang_map[ft]

        if not lang then
            log.debug("rename.cross-file", "Unsupported filetype")
            return
        end

        local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
        if not ok or not parser then
            log.debug("rename.cross-file", "Failed to get parser")
            return
        end

        local trees = parser:parse()
        if not trees or #trees == 0 then
            return
        end

        local root = trees[1]:root()

        -- Find import for component
        local query_str = [[
            (import_statement
                (import_clause
                    (named_imports
                        (import_specifier
                            name: (identifier) @import_name)))
                source: (string) @import_path)
        ]]

        local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_str)
        if not ok_query then
            return
        end

        for _, match, _ in query:iter_matches(root, bufnr) do
            local import_name_node = nil

            for id, node_or_nodes in pairs(match) do
                local name = query.captures[id]
                local nodes = node_or_nodes
                local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil

                if name == "import_name" and node then
                    import_name_node = node
                end
            end

            if import_name_node then
                local import_name = vim.treesitter.get_node_text(import_name_node, bufnr)
                if import_name == cross_file_info.component_name then
                    local start_row, start_col = import_name_node:range()
                    import_pos = { start_row + 1, start_col }
                    break
                end
            end
        end

        if not import_pos then
            log.debug("rename.cross-file", "Could not find import statement")
            return
        end

        -- Move cursor to import
        vim.api.nvim_win_set_cursor(0, import_pos)
        pos = import_pos
    end

    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    local offset_encoding = clients[1] and clients[1].offset_encoding or "utf-16"

    -- Step 1: First LSP rename at import position
    -- IMPORTANT: Temporarily restore cursor to original position to get correct params
    vim.api.nvim_win_set_cursor(0, pos)

    local params = vim.lsp.util.make_position_params(0, offset_encoding)
    params.newName = new_name

    vim.lsp.buf_request_all(bufnr, "textDocument/rename", params, function(results)
        local first_edit = M.merge_workspace_edits(results)
        if not first_edit then
            log.debug("rename.cross-file", "No workspace edit from first rename")
            return
        end

        -- Apply first edit using ORIGINAL to avoid hook recursion
        original_apply(first_edit, offset_encoding)

        -- Step 2: Second LSP rename at same position
        vim.schedule(function()
            vim.lsp.buf_request_all(bufnr, "textDocument/rename", params, function(results2)
                local second_edit = M.merge_workspace_edits(results2)
                if not second_edit then
                    log.debug("rename.cross-file", "No workspace edit from second rename")
                    return
                end

                -- Apply second edit using ORIGINAL to avoid hook recursion
                original_apply(second_edit, offset_encoding)

                -- Step 3: Cleanup alias
                vim.schedule(function()
                    M.cleanup_import_alias(bufnr, new_name)

                    -- Step 4: Maybe rename props (only if in imported file)
                    if cross_file_info.scenario == "import" then
                        -- Resolve import path and check props in that file
                        M.maybe_rename_props_in_imported_file(
                            bufnr,
                            cross_file_info.import_path,
                            cross_file_info.component_name,
                            new_name
                        )
                    else
                        -- Usage scenario: use bufnr directly from import_info
                        local import_bufnr = cross_file_info.import_info.component_info.bufnr
                        M.rename_props_in_buffer(
                            import_bufnr,
                            cross_file_info.component_name,
                            new_name
                        )
                    end

                    -- Step 5: Restore cursor only if we moved it (usage scenario)
                    if should_restore_cursor then
                        vim.schedule(function()
                            if vim.api.nvim_win_is_valid(original_win) then
                                vim.api.nvim_set_current_win(original_win)
                                if vim.api.nvim_win_get_buf(original_win) == original_bufnr then
                                    -- Restore to original position (before we moved to import)
                                    vim.api.nvim_win_set_cursor(original_win, original_pos)
                                end
                            end
                            M._is_rename_operation = false
                        end)
                    else
                        -- For import scenario, don't restore - let LSP natural cursor position
                        M._is_rename_operation = false
                    end
                end)
            end)
        end)
    end)
end

--- Show deferred cross-file rename menu after renaming
function M.show_deferred_cross_file_menu()
    local pending = M._pending_cross_file_edit

    if not pending then
        return
    end

    M._pending_cross_file_edit = nil

    local lsp_init = require("react.lsp")
    local clients = vim.lsp.get_clients({ bufnr = pending.bufnr })
    local offset_encoding = clients[1] and clients[1].offset_encoding or "utf-16"

    -- Extract just the new name (strip any "as Xxx" alias syntax)
    local clean_new_name = pending.new_name:match("^%S+%s+as%s+(%S+)$") or pending.new_name

    ui.show_cross_file_rename_menu(
        pending.cross_file_info.component_name,
        clean_new_name,
        function(choice)
            -- Temporarily restore original apply_workspace_edit to avoid recursion
            local current = vim.lsp.util.apply_workspace_edit
            vim.lsp.util.apply_workspace_edit = lsp_init._original_apply_workspace_edit

            if choice == "alias" then
                -- Restore cursor to original position before applying
                vim.api.nvim_win_set_cursor(0, pending.pos)

                vim.lsp.util.apply_workspace_edit(pending.workspace_edit, offset_encoding)
                M._is_rename_operation = false
            else
                M.handle_cross_file_direct_rename(
                    pending.cross_file_info,
                    pending.bufnr,
                    pending.pos, -- Use ORIGINAL position where identifier was detected
                    clean_new_name -- Use cleaned name without "as" syntax
                )
            end

            -- Restore hook
            vim.lsp.util.apply_workspace_edit = current
        end
    )
end

return M
