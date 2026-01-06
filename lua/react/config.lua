local log = require("react.util.log")

local React = {}

--- React configuration with its default values.
---
---@type table
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
React.options = {
    -- Prints useful logs about what event are triggered, and reasons actions are executed.
    debug = false,
}

---@private
local defaults = vim.deepcopy(React.options)

--- Defaults React options by merging user provided options with the default plugin values.
---
---@param options table Module config table. See |React.options|.
---
---@private
function React.defaults(options)
    React.options =
        vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, defaults or {}))

    -- let your user know that they provided a wrong value, this is reported when your plugin is executed.
    assert(
        type(React.options.debug) == "boolean",
        "`debug` must be a boolean (`true` or `false`)."
    )

    return React.options
end

--- Define your react setup.
---
---@param options table Module config table. See |React.options|.
---
---@usage `require("react").setup()` (add `{}` with your |React.options| table)
function React.setup(options)
    React.options = React.defaults(options or {})

    log.warn_deprecation(React.options)

    return React.options
end

return React
