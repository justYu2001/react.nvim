local M = {}

local registered = false

---@param null_ls table The null-ls module
function M.setup(null_ls)
    if registered then
        return
    end

    registered = true

    local sources = M.get_sources(null_ls)

    for _, source in ipairs(sources) do
        null_ls.register(source)
    end
end

---@param null_ls table The null-ls module
---@return table[] List of source definitions
function M.get_sources(null_ls)
    return {
        require("react.code_actions.add_to_props").get_source(null_ls),
        require("react.code_actions.introduce_props").get_source(null_ls),
        require("react.code_actions.wrap_use_callback").get_source(null_ls),
        require("react.code_actions.generate_event_handler").get_source(null_ls),
    }
end

return M
