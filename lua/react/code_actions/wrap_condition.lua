local M = {}

-- Check if node is inside binary_expression with && operator
local function is_inside_condition(node)
    local current = node:parent()

    while current do
        if current:type() == "binary_expression" then
            -- Check for && operator
            for child in current:iter_children() do
                if child:type() == "&&" then
                    return true
                end
            end
        end
        current = current:parent()
    end

    return false
end

-- Detect wrappable JSX at cursor
local function detect_wrappable_jsx_at_cursor(params)
    local bufnr = params.bufnr
    local row = params.row - 1
    local col = params.col
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    local current = node

    while current do
        local t = current:type()

        if t == "jsx_element" or t == "jsx_self_closing_element" or t == "jsx_fragment" then
            -- Check if already wrapped
            if is_inside_condition(current) then
                return nil
            end

            return {
                jsx_node = current,
            }
        end

        current = current:parent()
    end

    return nil
end

function M.get_source(null_ls)
    return {
        name = "react-wrap-condition",
        filetypes = { "typescriptreact", "javascriptreact", "typescript", "javascript" },
        method = null_ls.methods.CODE_ACTION,
        generator = {
            fn = function(params)
                local context = detect_wrappable_jsx_at_cursor(params)
                if not context then
                    return nil
                end

                return {
                    {
                        title = "Wrap into condition",
                        action = function()
                            local bufnr = params.bufnr
                            local jsx_node = context.jsx_node
                            local jsx_text = vim.treesitter.get_node_text(jsx_node, bufnr)
                            local has_newline = jsx_text:find("\n") ~= nil

                            local sr, sc, er, ec = jsx_node:range()

                            local wrapped
                            if has_newline then
                                -- Get base indentation from start column
                                local indent = string.rep(" ", sc)
                                local lines = vim.split(jsx_text, "\n")

                                -- Normalize indentation: remove base indent from all lines
                                local normalized_lines = {}
                                for i, line in ipairs(lines) do
                                    if i == 1 then
                                        -- First line has no leading indent in node text
                                        table.insert(normalized_lines, line)
                                    else
                                        -- Remove base indentation from subsequent lines
                                        local stripped = line:gsub("^" .. indent, "")
                                        table.insert(normalized_lines, stripped)
                                    end
                                end

                                -- Add new indentation (base + 2 spaces)
                                local indented_lines = {}
                                for _, line in ipairs(normalized_lines) do
                                    table.insert(indented_lines, indent .. "  " .. line)
                                end

                                local indented_jsx = table.concat(indented_lines, "\n")
                                wrapped = "{ && (\n" .. indented_jsx .. "\n" .. indent .. ")}"
                            else
                                wrapped = "{ && " .. jsx_text .. "}"
                            end

                            vim.api.nvim_buf_set_text(
                                bufnr,
                                sr,
                                sc,
                                er,
                                ec,
                                vim.split(wrapped, "\n")
                            )

                            -- Position cursor after '{' in insert mode
                            vim.schedule(function()
                                vim.api.nvim_win_set_cursor(0, { sr + 1, sc + 1 })
                                vim.cmd("startinsert")
                            end)
                        end,
                    },
                }
            end,
        },
    }
end

return M
