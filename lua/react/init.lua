local main = require("react.main")
local config = require("react.config")

local React = {}

--- Toggle the plugin by calling the `enable`/`disable` methods respectively.
function React.toggle()
    if _G.React.config == nil then
        _G.React.config = config.options
    end

    main.toggle("public_api_toggle")
end

--- Initializes the plugin, sets event listeners and internal state.
function React.enable(scope)
    if _G.React.config == nil then
        _G.React.config = config.options
    end

    main.enable(scope or "public_api_enable")
end

--- Disables the plugin, clear highlight groups and autocmds, closes side buffers and resets the internal state.
function React.disable()
    main.disable("public_api_disable")
end

function React.is_enabled()
    if _G.React.state == nil then
        return false
    end

    local state = require("react.state")

    return state.get_enabled(state)
end

-- setup React options and merge them with user provided ones.
function React.setup(opts)
    _G.React.config = config.setup(opts)
end

_G.React = React

return _G.React
