local M = {}

local handler = require("react.code_actions.generate_handler")
local gen = require("react.code_actions.generate_event_handler")
local imports = require("react.util.imports")

local function is_pascal_case(name)
    return name ~= nil and name:match("^[A-Z]") ~= nil
end

-- camelCase a PascalCase name
local function to_camel_case(name)
    return name:sub(1, 1):lower() .. name:sub(2)
end

-- Generate ref name: HTML → <name>Ref, custom → camelCase + Ref
-- Conflict resolution mirrors generate_handler_name: append 2, 3, ...
function M.generate_ref_name(component_name, bufnr, component_node)
    local base_name
    if is_pascal_case(component_name) then
        base_name = to_camel_case(component_name) .. "Ref"
    else
        base_name = component_name .. "Ref"
    end

    -- Collect existing variable names in component scope
    local existing_names = {}

    local function collect_names(node)
        for child in node:iter_children() do
            if child:type() == "lexical_declaration" or child:type() == "variable_declaration" then
                for declarator in child:iter_children() do
                    if declarator:type() == "variable_declarator" then
                        local name_node = declarator:named_child(0)
                        if name_node and name_node:type() == "identifier" then
                            existing_names[vim.treesitter.get_node_text(name_node, bufnr)] = true
                        end
                    end
                end
            end
            if child:type() == "statement_block" then
                collect_names(child)
            end
        end
    end

    collect_names(component_node)

    local ref_name = base_name
    local counter = 2
    while existing_names[ref_name] do
        ref_name = base_name .. counter
        counter = counter + 1
    end

    return ref_name
end

-- Get ref type annotation and extra import name.
-- Returns: type_str (or nil for JS), extra_import (or nil)
-- _version_override: optional 4th arg to skip filesystem lookup (for tests)
function M.get_ref_type(component_name, is_typescript, bufnr, version_override)
    if not is_typescript then
        return nil, nil
    end

    local version = version_override or M.get_react_version(bufnr)

    if is_pascal_case(component_name) then
        if version and version >= 19 then
            return "ComponentRef<typeof " .. component_name .. ">", "ComponentRef"
        else
            return "ElementRef<typeof " .. component_name .. ">", "ElementRef"
        end
    else
        if version and version >= 19 then
            return 'ComponentRef<"' .. component_name .. '">', "ComponentRef"
        else
            return 'ElementRef<"' .. component_name .. '">', "ElementRef"
        end
    end
end

-- Walk up from buffer file to find package.json, parse react version.
-- Returns major version as integer, or nil.
function M.get_react_version(bufnr)
    local fname = bufnr and vim.api.nvim_buf_get_name(bufnr) or ""
    if fname == "" then
        return nil
    end

    local dir = fname:match("(.+)/")
    while dir and dir ~= "/" do
        local pkg_path = dir .. "/package.json"
        if vim.fn.filereadable(pkg_path) == 1 then
            local lines = vim.fn.readfile(pkg_path)
            if lines then
                local content = table.concat(lines, "\n")
                -- Look for "react": "..." in dependencies or devDependencies
                local version_str = content:match('"react"%s*:%s*"([^"]+)"')
                if version_str then
                    -- Strip leading ^ ~ >= etc
                    local clean = version_str:gsub("^[%^~>=< ]+", "")
                    local major = clean:match("^(%d+)")
                    if major then
                        return tonumber(major)
                    end
                end
            end
            -- Found package.json but no react dep — stop searching
            return nil
        end
        dir = dir:match("(.+)/")
    end
    return nil
end

-- Create useRef import edit (mirrors create_type_import_edit but without "type " prefix)
function M.create_use_ref_import_edit(bufnr)
    if imports.has_type_import(bufnr, "useRef") then
        return nil
    end

    local import_info = imports.get_react_import_info(bufnr)

    if import_info then
        if import_info.type == "named" then
            local named_imports = import_info.node
            local all_imports = {}

            for child in named_imports:iter_children() do
                if child:type() == "import_specifier" then
                    local name_node = child:named_child(0)
                    if name_node and name_node:type() == "identifier" then
                        local name = vim.treesitter.get_node_text(name_node, bufnr)
                        table.insert(all_imports, { name = name, node = child })
                    end
                end
            end

            table.insert(all_imports, { name = "useRef", node = nil })

            table.sort(all_imports, function(a, b)
                return a.name < b.name
            end)

            local insert_pos = nil

            for i, imp in ipairs(all_imports) do
                if imp.name == "useRef" then
                    if i == 1 then
                        local first_import = all_imports[2]
                        if first_import and first_import.node then
                            local sr, sc = first_import.node:range()
                            insert_pos = { row = sr, col = sc, is_beginning = true }
                        end
                    elseif i == #all_imports then
                        local last_import = all_imports[#all_imports - 1]
                        if last_import and last_import.node then
                            local _, _, er, ec = last_import.node:range()
                            insert_pos = { row = er, col = ec, is_beginning = false }
                        end
                    else
                        local prev_import = all_imports[i - 1]
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
                    text = "useRef, "
                else
                    text = ", useRef"
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
                text = ", { useRef }",
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
            text = "import { useRef } from 'react';\n",
        }
    end

    return nil
end

-- Helper to get indentation at a line
local function get_line_indent(bufnr, row)
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if not line then
        return ""
    end
    local indent = line:match("^%s*")
    return indent or ""
end

function M.get_source(null_ls)
    return {
        name = "react-create-ref",
        filetypes = { "typescriptreact", "javascriptreact", "typescript", "javascript" },
        method = null_ls.methods.CODE_ACTION,
        generator = {
            fn = function(params)
                local context = handler.detect_component_at_cursor(params)
                if not context then
                    return nil
                end

                local assigned = handler.get_assigned_props(context.jsx_element_node, params.bufnr)
                if assigned["ref"] then
                    return nil
                end

                local bufnr = params.bufnr
                local sr = context.jsx_element_node:range()
                local component_node = gen.find_component_scope(bufnr, sr, 0)

                if not component_node then
                    return nil
                end
                if component_node:type() == "class_declaration" then
                    return nil
                end

                return {
                    {
                        title = "Create ref",
                        action = function()
                            local filetype = vim.bo[bufnr].filetype
                            local is_typescript = filetype == "typescriptreact"
                                or filetype == "typescript"

                            local component_name = context.component_name
                            local ref_name =
                                M.generate_ref_name(component_name, bufnr, component_node)
                            local ref_type, extra_import =
                                M.get_ref_type(component_name, is_typescript, bufnr)

                            -- Find return statement for declaration insertion
                            local return_node = gen.find_return_statement(component_node)
                            local return_row

                            if return_node then
                                return_row = return_node:range()
                            else
                                local body = nil
                                for child in component_node:iter_children() do
                                    if child:type() == "statement_block" then
                                        body = child
                                        break
                                    end
                                end
                                if not body then
                                    return
                                end
                                local _, _, body_er, _ = body:range()
                                return_row = body_er - 1
                            end

                            -- Step 1: JSX attribute (no line count change)
                            local _, _, er, ec = context.jsx_element_node:range()
                            local line_text =
                                vim.api.nvim_buf_get_lines(bufnr, er, er + 1, false)[1]
                            local attr_insert_col = ec - 1

                            if line_text and line_text:sub(ec - 1, ec) == "/>" then
                                attr_insert_col = ec - 2
                            end

                            local prefix = line_text
                                    and line_text:sub(attr_insert_col, attr_insert_col) == " "
                                    and ""
                                or " "
                            local attr_text = prefix .. "ref={" .. ref_name .. "}"
                            vim.api.nvim_buf_set_text(
                                bufnr,
                                er,
                                attr_insert_col,
                                er,
                                attr_insert_col,
                                { attr_text }
                            )

                            local row_offset = 0

                            -- Step 2: Type import (ElementRef/ComponentRef) — only TS + custom
                            if extra_import then
                                local type_edit =
                                    imports.create_type_import_edit(bufnr, extra_import)
                                if type_edit then
                                    local type_lines = vim.split(type_edit.text, "\n")
                                    vim.api.nvim_buf_set_text(
                                        bufnr,
                                        type_edit.row,
                                        type_edit.col,
                                        type_edit.row,
                                        type_edit.col,
                                        type_lines
                                    )
                                    if type_edit.row <= return_row then
                                        row_offset = row_offset + #type_lines - 1
                                    end
                                end
                            end

                            -- Step 3: useRef import — re-parse after step 2
                            local use_ref_edit = M.create_use_ref_import_edit(bufnr)
                            if use_ref_edit then
                                local ur_lines = vim.split(use_ref_edit.text, "\n")
                                vim.api.nvim_buf_set_text(
                                    bufnr,
                                    use_ref_edit.row,
                                    use_ref_edit.col,
                                    use_ref_edit.row,
                                    use_ref_edit.col,
                                    ur_lines
                                )
                                if use_ref_edit.row <= return_row + row_offset then
                                    row_offset = row_offset + #ur_lines - 1
                                end
                            end

                            -- Step 4: useRef declaration before return
                            local decl_row = return_row + row_offset
                            local indent = get_line_indent(bufnr, decl_row)
                            local type_annotation = ""
                            if ref_type then
                                type_annotation = "<" .. ref_type .. ">"
                            end
                            local decl = indent
                                .. "const "
                                .. ref_name
                                .. " = useRef"
                                .. type_annotation
                                .. "(null);\n\n"
                            local decl_lines = vim.split(decl, "\n")
                            vim.api.nvim_buf_set_text(bufnr, decl_row, 0, decl_row, 0, decl_lines)

                            -- Position cursor on refName and trigger rename
                            vim.schedule(function()
                                local inserted_line = vim.api.nvim_buf_get_lines(
                                    bufnr,
                                    decl_row,
                                    decl_row + 1,
                                    false
                                )[1]
                                local name_start = inserted_line:find(ref_name, 1, true)
                                local name_row = decl_row + 1 -- 1-indexed
                                local name_col = (name_start or 7) - 1 -- 0-indexed

                                vim.api.nvim_win_set_cursor(0, { name_row, name_col })

                                local has_inc_rename, _ = pcall(require, "inc_rename")
                                if has_inc_rename then
                                    pcall(function()
                                        local keys = vim.api.nvim_replace_termcodes(
                                            ":IncRename " .. ref_name,
                                            true,
                                            false,
                                            true
                                        )
                                        vim.api.nvim_feedkeys(keys, "n", false)
                                    end)
                                else
                                    vim.lsp.buf.rename()
                                end
                            end)
                        end,
                    },
                }
            end,
        },
    }
end

return M
