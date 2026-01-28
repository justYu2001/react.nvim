local is_jsx_or_type = {
    jsx = true,
    type = true,
}

local M = {}

---@param old_name string: original prop name
---@param new_name string: new prop name
---@param context string Rename target context (e.g. "jsx", "body", "type")
---@param callback function: callback with choice ("direct" or "alias")
function M.show_rename_menu(old_name, new_name, context, callback)
    local key = is_jsx_or_type[context] and new_name or old_name
    local alias = is_jsx_or_type[context] and old_name or new_name

    local items = {
        {
            label = string.format("Rename prop directly: { %s }", new_name),
            value = "direct",
        },
        {
            label = string.format("Use alias: { %s: %s }", key, alias),
            value = "alias",
        },
    }

    vim.ui.select(items, {
        prompt = "Rename prop:",
        format_item = function(item)
            return item.label
        end,
    }, function(choice)
        if choice then
            callback(choice.value)
        end
    end)
end

---@param old_name string: original component name
---@param new_name string: new component name
---@param callback function: callback with choice ("direct" or "alias")
function M.show_cross_file_rename_menu(old_name, new_name, callback)
    local items = {
        {
            label = string.format("Direct rename: import { %s }", new_name),
            value = "direct",
        },
        {
            label = string.format("Use alias: import { %s as %s }", old_name, new_name),
            value = "alias",
        },
    }

    vim.ui.select(items, {
        prompt = "Rename component:",
        format_item = function(item)
            return item.label
        end,
    }, function(choice)
        if choice then
            callback(choice.value)
        end
    end)
end

---@param old_filename string: current filename
---@param new_filename string: proposed new filename
---@param callback function: callback with choice ("rename" or "skip")
function M.show_file_rename_menu(old_filename, new_filename, callback)
    local items = {
        {
            label = string.format("Rename file: %s → %s", old_filename, new_filename),
            value = "rename",
        },
        {
            label = "Skip file rename",
            value = "skip",
        },
    }

    vim.ui.select(items, {
        prompt = "Component matches filename:",
        format_item = function(item)
            return item.label
        end,
    }, function(choice)
        if choice then
            callback(choice.value)
        end
    end)
end

return M
