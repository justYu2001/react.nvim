-- You can use this loaded variable to enable conditional parts of your plugin.
if _G.ReactLoaded then
    return
end

_G.ReactLoaded = true

vim.api.nvim_create_user_command("React", function()
    require("react").toggle()
end, {})
