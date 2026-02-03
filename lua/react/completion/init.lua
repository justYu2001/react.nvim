local M = {}

local registered = false

function M.setup()
    if registered then
        return
    end

    registered = true

    local augroup = vim.api.nvim_create_augroup("ReactCompletion", { clear = true })

    vim.api.nvim_create_autocmd("CompleteDone", {
        group = augroup,
        pattern = { "*.jsx", "*.tsx", "*.js", "*.ts" },
        callback = function()
            local auto_props = require("react.completion.auto_props")
            auto_props.handle_completion()
        end,
    })
end

function M.teardown()
    if not registered then
        return
    end

    registered = false

    pcall(vim.api.nvim_del_augroup_by_name, "ReactCompletion")
end

return M
