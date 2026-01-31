local M = {}

-- Get React import info
function M.get_react_import_info(bufnr)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]

    if not lang then
        return nil
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)

    if not ok or not parser then
        return nil
    end

    local trees = parser:parse()

    if not trees or #trees == 0 then
        return nil
    end

    local root = trees[1]:root()

    local function find_react_import(node)
        if node:type() == "import_statement" then
            local source_node = nil

            for child in node:iter_children() do
                if child:type() == "string" then
                    source_node = child
                end
            end

            if source_node then
                local source_text = vim.treesitter.get_node_text(source_node, bufnr)

                if source_text:match("react") then
                    for child in node:iter_children() do
                        if child:type() == "import_clause" then
                            for ic_child in child:iter_children() do
                                if ic_child:type() == "named_imports" then
                                    return {
                                        type = "named",
                                        node = ic_child,
                                    }
                                end
                            end

                            for ic_child in child:iter_children() do
                                if ic_child:type() == "identifier" then
                                    return {
                                        type = "default",
                                        node = child,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end

        for child in node:iter_children() do
            local result = find_react_import(child)

            if result then
                return result
            end
        end

        return nil
    end

    return find_react_import(root)
end

-- Check if type already imported
function M.has_type_import(bufnr, event_type)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]

    if not lang then
        return false
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)

    if not ok or not parser then
        return false
    end

    local trees = parser:parse()

    if not trees or #trees == 0 then
        return false
    end

    local root = trees[1]:root()

    local function check_import(node)
        if node:type() == "import_statement" then
            local source_node = nil

            for child in node:iter_children() do
                if child:type() == "string" then
                    source_node = child
                end
            end

            if source_node then
                local source_text = vim.treesitter.get_node_text(source_node, bufnr)

                if source_text:match("react") then
                    for child in node:iter_children() do
                        if child:type() == "import_clause" then
                            for ic_child in child:iter_children() do
                                if ic_child:type() == "named_imports" then
                                    for ni_child in ic_child:iter_children() do
                                        if ni_child:type() == "import_specifier" then
                                            local name_node = ni_child:named_child(0)

                                            if name_node and name_node:type() == "identifier" then
                                                local name =
                                                    vim.treesitter.get_node_text(name_node, bufnr)

                                                -- Match both "MouseEvent" and "type MouseEvent"
                                                if
                                                    name == event_type
                                                    or name:match("^type%s+" .. event_type)
                                                then
                                                    return true
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        for child in node:iter_children() do
            if check_import(child) then
                return true
            end
        end

        return false
    end

    return check_import(root)
end

-- Create type import edit
function M.create_type_import_edit(bufnr, event_type)
    if not event_type then
        return nil
    end

    if M.has_type_import(bufnr, event_type) then
        return nil
    end

    local import_info = M.get_react_import_info(bufnr)

    if import_info then
        if import_info.type == "named" then
            local named_imports = import_info.node
            local imports = {}

            for child in named_imports:iter_children() do
                if child:type() == "import_specifier" then
                    local name_node = child:named_child(0)

                    if name_node and name_node:type() == "identifier" then
                        local name = vim.treesitter.get_node_text(name_node, bufnr)
                        table.insert(imports, { name = name, node = child })
                    end
                end
            end

            table.insert(imports, { name = "type " .. event_type, node = nil })

            table.sort(imports, function(a, b)
                return a.name < b.name
            end)

            local insert_pos = nil

            for i, imp in ipairs(imports) do
                if imp.name == "type " .. event_type then
                    if i == 1 then
                        local first_import = imports[2]

                        if first_import and first_import.node then
                            local sr, sc = first_import.node:range()
                            insert_pos = { row = sr, col = sc, is_beginning = true }
                        end
                    elseif i == #imports then
                        local last_import = imports[#imports - 1]

                        if last_import and last_import.node then
                            local _, _, er, ec = last_import.node:range()
                            insert_pos = { row = er, col = ec, is_beginning = false }
                        end
                    else
                        local prev_import = imports[i - 1]

                        if prev_import and prev_import.node then
                            local _, _, er, ec = prev_import.node:range()
                            insert_pos = { row = er, col = ec, is_beginning = false }
                        end
                    end

                    break
                end
            end

            if insert_pos then
                local text
                if insert_pos.is_beginning then
                    text = "type " .. event_type .. ", "
                else
                    text = ", type " .. event_type
                end

                return {
                    row = insert_pos.row,
                    col = insert_pos.col,
                    text = text,
                }
            end
        elseif import_info.type == "default" then
            local import_clause = import_info.node
            local _, _, er, ec = import_clause:range()

            return {
                row = er,
                col = ec,
                text = ", { type " .. event_type .. " }",
            }
        end
    else
        local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
        local insert_row = 0

        if first_line and first_line:match("^[\"']use client[\"']") then
            insert_row = 1
        end

        return {
            row = insert_row,
            col = 0,
            text = "import { type " .. event_type .. " } from 'react';\n",
        }
    end

    return nil
end

return M
