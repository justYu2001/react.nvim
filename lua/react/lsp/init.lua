local rename = require("react.lsp.rename")
local log = require("react.util.log")

local M = {}

M._original_apply_workspace_edit = nil
M._inc_rename_wrapped = false

function M.setup()
    local has_inc_rename, _ = pcall(require, "inc_rename")

    -- Always hook apply_workspace_edit to catch all rename operations
    M.setup_inc_rename_hook()

    if has_inc_rename then
        log.debug("lsp.setup", "Hooked into inc-rename.nvim")
    else
        -- Also replace vim.lsp.buf.rename for direct calls
        vim.lsp.buf.rename = rename.rename

        log.debug(
            "lsp.setup",
            "useState rename hook installed (apply_workspace_edit + vim.lsp.buf.rename)"
        )
    end
end

function M.setup_inc_rename_hook()
    -- Wrap vim.lsp.util.apply_workspace_edit during rename operations
    -- This intercepts inc-rename's workspace edit application

    if M._inc_rename_wrapped then
        return
    end

    M._original_apply_workspace_edit = vim.lsp.util.apply_workspace_edit
    M._inc_rename_wrapped = true

    vim.lsp.util.apply_workspace_edit = function(workspace_edit, offset_encoding, ...)
        local enhanced_edit = rename.try_add_use_state_edits(workspace_edit)

        -- Check if we're handling this asynchronously
        if enhanced_edit and enhanced_edit._react_handled then
            return -- Don't apply, deferred handler will do it
        end

        return M._original_apply_workspace_edit(
            enhanced_edit or workspace_edit,
            offset_encoding,
            ...
        )
    end
end

function M.teardown()
    if M._inc_rename_wrapped then
        vim.lsp.util.apply_workspace_edit = M._original_apply_workspace_edit

        M._inc_rename_wrapped = false

        log.debug("lsp.teardown", "Restored vim.lsp.util.apply_workspace_edit")
    else
        vim.lsp.buf.rename = rename._original_rename

        log.debug("lsp.teardown", "Restored vim.lsp.buf.rename")
    end
end

return M
