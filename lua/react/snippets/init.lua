local M = {}

local registered = false

function M.setup()
    if registered then
        return
    end

    local ok, luasnip = pcall(require, "luasnip")
    if not ok then
        return
    end

    registered = true

    local snippets_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
    local all_snippets = {}

    -- Scan for *_postfix.lua files
    for name, kind in vim.fs.dir(snippets_dir) do
        if kind == "file" and name:match("_postfix%.lua$") then
            local module_name = name:gsub("%.lua$", "")
            local module_ok, module = pcall(require, "react.snippets." .. module_name)

            if module_ok and module.get_snippets then
                local snippets = module.get_snippets()
                if type(snippets) == "table" then
                    for _, snippet in ipairs(snippets) do
                        table.insert(all_snippets, snippet)
                    end
                end
            end
        end
    end

    luasnip.add_snippets("javascript", all_snippets)
    luasnip.add_snippets("typescript", all_snippets)

    luasnip.filetype_extend("javascriptreact", { "javascript" })
    luasnip.filetype_extend("typescriptreact", { "typescript" })
end

function M.teardown()
    if not registered then
        return
    end

    registered = false
end

return M
