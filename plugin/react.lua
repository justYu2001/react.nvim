-- You can use this loaded variable to enable conditional parts of your plugin.
if _G.ReactLoaded then
    return
end

_G.ReactLoaded = true

vim.api.nvim_create_autocmd("BufEnter", {
    pattern = { "*.jsx", "*.tsx", "*.js", "*.ts" },
    callback = function()
        require("react").enable()
    end,
})

vim.api.nvim_create_user_command("React", function(opts)
    local react = require("react")
    local arg = opts.args

    if arg == "status" then
        local enabled = react.is_enabled()

        vim.notify(
            string.format("[react.nvim] Status: %s", enabled and "enabled" or "disabled"),
            vim.log.levels.INFO
        )
    else
        react.toggle()

        local enabled = react.is_enabled()

        vim.notify(
            string.format("[react.nvim] %s", enabled and "enabled" or "disabled"),
            vim.log.levels.INFO
        )
    end
end, {
    nargs = "?",
    complete = function()
        return { "status" }
    end,
})
