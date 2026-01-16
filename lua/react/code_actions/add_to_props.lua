local M = {}

-- Helper to get indentation at a line
local function get_line_indent(bufnr, row)
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]

    if not line then
        return ""
    end

    local indent = line:match("^%s*")

    return indent or ""
end

local function get_undefined_var_at_cursor(params)
    local bufnr = params.bufnr
    local row = params.row - 1
    local col = params.col

    local diagnostics = vim.diagnostic.get(bufnr, { lnum = row })

    for _, diag in ipairs(diagnostics) do
        local msg = diag.message

        -- tsserver: "Cannot find name 'foo'"
        -- eslint: "'foo' is not defined"
        local var_name = msg:match("Cannot find name '([%w_]+)'")
            or msg:match("'([%w_]+)' is not defined")

        -- ts-error-translator.nvim: "I can't find the variable you're trying to access."
        local is_matched_error = msg == "I can't find the variable you're trying to access."

        if var_name or is_matched_error then
            local node = vim.treesitter.get_node({
                bufnr = bufnr,
                pos = { row, col },
            })

            if node and node:type() == "identifier" then
                local text = vim.treesitter.get_node_text(node, bufnr)

                if is_matched_error then
                    return text
                end

                if text == var_name then
                    return var_name
                end
            end
        end
    end

    return nil
end

local function get_type_annotation(node)
    local parent = node:parent()

    if not parent then
        return nil
    end

    for child in parent:iter_children() do
        if child:type() == "type_annotation" then
            return child
        end
    end

    return nil
end

local function extract_component_name(bufnr, function_node)
    if not function_node then
        return nil
    end

    -- Traverse up to find lexical_declaration or variable_declaration
    local current = function_node:parent()

    while current do
        local node_type = current:type()

        if node_type == "lexical_declaration" or node_type == "variable_declaration" then
            -- Look for variable_declarator child
            for child in current:iter_children() do
                if child:type() == "variable_declarator" then
                    -- Get the identifier (first named child)
                    local identifier = child:named_child(0)

                    if identifier and identifier:type() == "identifier" then
                        return vim.treesitter.get_node_text(identifier, bufnr)
                    end
                end
            end
            break
        end

        current = current:parent()
    end

    return nil
end

local function find_component_params(bufnr, row, col)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    -- Find enclosing function
    local current = node

    while current do
        local type = current:type()

        if
            type == "function_declaration"
            or type == "arrow_function"
            or type == "function"
            or type == "function_expression"
        then
            -- Get formal_parameters
            local params_node = nil

            for child in current:iter_children() do
                if child:type() == "formal_parameters" then
                    params_node = child

                    break
                end
            end

            if not params_node then
                return nil
            end

            local first_param = params_node:named_child(0)

            if not first_param then
                return {
                    type = "no_params",
                    formal_parameters = params_node,
                    function_node = current,
                }
            end

            if first_param:type() == "object_pattern" then
                return {
                    type = "destructured",
                    pattern_node = first_param,
                    type_annotation = get_type_annotation(first_param),
                }
            end

            -- required_parameter can be destructured or not
            if first_param:type() == "required_parameter" then
                local pattern_node = first_param:field("pattern")[1]

                local type_node = first_param:field("type")[1]

                if pattern_node then
                    if pattern_node:type() == "object_pattern" then
                        return {
                            type = "destructured",
                            pattern_node = pattern_node,
                            type_annotation = type_node,
                        }
                    elseif type_node then
                        return {
                            type = "typed_not_destructured",
                            type_annotation = type_node,
                        }
                    end
                end
            end

            return nil
        end

        current = current:parent()
    end

    return nil
end

local function find_type_declaration(bufnr, type_ref_name)
    local parser = vim.treesitter.get_parser(bufnr)

    if not parser then
        return nil
    end

    local trees = parser:parse()

    if not trees or #trees == 0 then
        return nil
    end

    local root = trees[1]:root()

    -- Manual traversal to find interface or type alias
    local function traverse(node)
        if node:type() == "interface_declaration" then
            local name_node = node:named_child(0)

            if name_node and name_node:type() == "type_identifier" then
                local name = vim.treesitter.get_node_text(name_node, bufnr)

                if name == type_ref_name then
                    local body_node = node:named_child(1)

                    if body_node and body_node:type() == "interface_body" then
                        return { type = "interface", node = body_node }
                    end
                end
            end
        elseif node:type() == "type_alias_declaration" then
            local name_node = node:named_child(0)

            if name_node and name_node:type() == "type_identifier" then
                local name = vim.treesitter.get_node_text(name_node, bufnr)

                if name == type_ref_name then
                    local value_node = node:named_child(1)

                    if value_node and value_node:type() == "object_type" then
                        return { type = "type_alias", node = value_node }
                    end
                end
            end
        end

        for child in node:iter_children() do
            local result = traverse(child)

            if result then
                return result
            end
        end

        return nil
    end

    return traverse(root)
end

local function already_in_destructuring(bufnr, pattern_node, var_name)
    for child in pattern_node:iter_children() do
        if child:type() == "shorthand_property_identifier_pattern" then
            local text = vim.treesitter.get_node_text(child, bufnr)

            if text == var_name then
                return true
            end
        elseif child:type() == "pair_pattern" then
            -- Handle renamed props: { foo: bar }
            local key_node = child:named_child(0)

            if key_node then
                local key_text = vim.treesitter.get_node_text(key_node, bufnr)

                if key_text == var_name then
                    return true
                end
            end
        end
    end

    return false
end

local function already_in_type(bufnr, type_node, var_name)
    for child in type_node:iter_children() do
        if child:type() == "property_signature" then
            local prop_name_node = child:named_child(0)

            if prop_name_node then
                local text = vim.treesitter.get_node_text(prop_name_node, bufnr)

                if text == var_name then
                    return true
                end
            end
        end
    end

    return false
end

local function create_destructuring_edit(pattern_node, var_name)
    local last_prop = nil

    for child in pattern_node:iter_children() do
        if child:type() == "rest_pattern" then
            break
        elseif
            child:type() == "shorthand_property_identifier_pattern"
            or child:type() == "pair_pattern"
        then
            last_prop = child
        end
    end

    local insert_row, insert_col

    if last_prop then
        local _, _, er, ec = last_prop:range()

        insert_row, insert_col = er, ec
    else
        local sr, sc = pattern_node:range()

        insert_row, insert_col = sr, sc + 1
    end

    local new_text = last_prop and (", " .. var_name) or var_name

    return {
        row = insert_row,
        col = insert_col,
        text = new_text,
    }
end

local function create_no_params_destructuring_edit(params_node, var_name, type_name)
    local sr, sc, er, ec = params_node:range()

    local replacement

    if type_name then
        replacement = string.format("({ %s }: %s)", var_name, type_name)
    else
        replacement = string.format("({ %s })", var_name)
    end

    return {
        row_start = sr,
        col_start = sc,
        row_end = er,
        col_end = ec,
        text = replacement,
    }
end

local function create_type_edit(bufnr, type_node, var_name)
    local last_prop = nil

    for child in type_node:iter_children() do
        if child:type() == "property_signature" then
            last_prop = child
        end
    end

    local insert_row, insert_col

    if last_prop then
        local _, _, er, _ = last_prop:range()
        local line = vim.api.nvim_buf_get_lines(bufnr, er, er + 1, false)[1]

        insert_row = er
        insert_col = #line
    else
        -- Empty type - insert after opening brace
        local sr, sc = type_node:range()

        insert_row, insert_col = sr, sc + 1
    end

    local indent = get_line_indent(bufnr, insert_row)

    return {
        row = insert_row,
        col = insert_col,
        snippet = {
            var_name = var_name,
            indent = indent,
        },
    }
end

-- Create interface declaration above component
-- Returns array of edits (structure + snippet) or nil if interface already exists
local function create_interface_edit(bufnr, function_node, interface_name, var_name)
    local existing_type = find_type_declaration(bufnr, interface_name)

    if existing_type then
        return nil
    end

    -- Find the declaration node (lexical_declaration or variable_declaration)
    local decl_node = function_node:parent()

    while decl_node do
        local node_type = decl_node:type()

        if node_type == "lexical_declaration" or node_type == "variable_declaration" then
            break
        end

        decl_node = decl_node:parent()
    end

    if not decl_node then
        return nil
    end

    local decl_start_row, _ = decl_node:range()

    local indent = get_line_indent(bufnr, decl_start_row)
    local prop_indent = indent .. "  "

    return {
        {
            row = decl_start_row,
            col = 0,
            text = string.format("%sinterface %s {\n%s}\n\n", indent, interface_name, indent),
        },
        {
            row = decl_start_row,
            col = #indent + #interface_name + 12, -- End of "interface Name {"
            snippet = {
                var_name = var_name,
                indent = prop_indent,
            },
        },
    }
end

local function create_type_annotation_edit(bufnr, type_annotation, var_name)
    if not type_annotation then
        return nil
    end

    local type_node = type_annotation:named_child(0)

    if not type_node then
        return nil
    end

    -- Case 1: Inline object type { x: string }
    if type_node:type() == "object_type" then
        if already_in_type(bufnr, type_node, var_name) then
            return nil
        end

        return create_type_edit(bufnr, type_node, var_name)
    end

    -- Case 2: Type reference (Props)
    if type_node:type() == "type_identifier" then
        local type_name = vim.treesitter.get_node_text(type_node, bufnr)

        local type_decl = find_type_declaration(bufnr, type_name)

        if type_decl and type_decl.node then
            if already_in_type(bufnr, type_decl.node, var_name) then
                return nil
            end

            return create_type_edit(bufnr, type_decl.node, var_name)
        end
    end

    return nil
end

local function apply_edits(bufnr, edits)
    local normal_edits = {}
    local snippet_edit = nil

    for _, edit in ipairs(edits) do
        if edit.snippet then
            snippet_edit = edit
        else
            table.insert(normal_edits, edit)
        end
    end

    -- Apply normal edits first (sorted reverse order)
    table.sort(normal_edits, function(a, b)
        local a_row = a.row_start or a.row
        local b_row = b.row_start or b.row

        if a_row == b_row then
            local a_col = a.col_start or a.col
            local b_col = b.col_start or b.col

            return a_col > b_col
        end

        return a_row > b_row
    end)

    for _, edit in ipairs(normal_edits) do
        local lines = vim.split(edit.text, "\n")

        if edit.row_start then
            vim.api.nvim_buf_set_text(
                bufnr,
                edit.row_start,
                edit.col_start,
                edit.row_end,
                edit.col_end,
                lines
            )
        else
            vim.api.nvim_buf_set_text(bufnr, edit.row, edit.col, edit.row, edit.col, lines)
        end
    end

    if snippet_edit then
        local ok, luasnip = pcall(require, "luasnip")

        if ok then
            local s = luasnip.snippet
            local t = luasnip.text_node
            local i = luasnip.insert_node

            local var_name = snippet_edit.snippet.var_name
            local indent = snippet_edit.snippet.indent

            local text = string.format("\n%s%s", indent, var_name)

            vim.api.nvim_buf_set_text(
                bufnr,
                snippet_edit.row,
                snippet_edit.col,
                snippet_edit.row,
                snippet_edit.col,
                vim.split(text, "\n")
            )

            vim.schedule(function()
                local expand_row = snippet_edit.row + 1
                local expand_col = #indent + #var_name

                local snip = s("", {
                    t("?"),
                    i(1),
                    t(": "),
                    i(2, "unknown"),
                })

                luasnip.snip_expand(snip, { pos = { expand_row, expand_col } })
            end)
        else
            print("Install LuaSnip for a better development experience.")

            -- Fallback: insert text and position cursor at type location
            local var_name = snippet_edit.snippet.var_name
            local indent = snippet_edit.snippet.indent
            local text = string.format("\n%s%s?: ", indent, var_name)

            vim.api.nvim_buf_set_text(
                bufnr,
                snippet_edit.row,
                snippet_edit.col,
                snippet_edit.row,
                snippet_edit.col,
                vim.split(text, "\n")
            )
            vim.api.nvim_win_set_cursor(0, { snippet_edit.row + 2, #indent + #var_name + 3 })
            vim.cmd("startinsert")
        end
    end
end

function M.get_source(null_ls)
    return {
        name = "react-add-to-props",
        filetypes = { "javascriptreact", "typescriptreact", "javascript", "typescript" },
        method = null_ls.methods.CODE_ACTION,
        generator = {
            fn = function(params)
                local var_name = get_undefined_var_at_cursor(params)

                if not var_name then
                    return nil
                end

                local comp_params = find_component_params(params.bufnr, params.row - 1, params.col)

                if not comp_params then
                    return nil
                end

                local actions = {}

                if comp_params.type == "destructured" then
                    if
                        already_in_destructuring(params.bufnr, comp_params.pattern_node, var_name)
                    then
                        return nil
                    end

                    local edits = {}

                    table.insert(
                        edits,
                        create_destructuring_edit(comp_params.pattern_node, var_name)
                    )

                    if comp_params.type_annotation then
                        local type_edit = create_type_annotation_edit(
                            params.bufnr,
                            comp_params.type_annotation,
                            var_name
                        )

                        if type_edit then
                            table.insert(edits, type_edit)
                        end
                    end

                    local title = string.format("Add '%s' to props", var_name)

                    table.insert(actions, {
                        title = title,
                        action = function()
                            apply_edits(params.bufnr, edits)
                        end,
                    })
                end

                if comp_params.type == "typed_not_destructured" then
                    local type_edit = create_type_annotation_edit(
                        params.bufnr,
                        comp_params.type_annotation,
                        var_name
                    )

                    if type_edit then
                        table.insert(actions, {
                            title = string.format("Add '%s' to Props type", var_name),
                            action = function()
                                apply_edits(params.bufnr, { type_edit })
                            end,
                        })
                    end
                end

                if comp_params.type == "no_params" then
                    local filetype = vim.bo[params.bufnr].filetype
                    local is_typescript = filetype == "typescriptreact" or filetype == "typescript"

                    local edits = {}

                    if is_typescript then
                        local comp_name =
                            extract_component_name(params.bufnr, comp_params.function_node)

                        if comp_name then
                            local interface_name = comp_name .. "Props"

                            local interface_edits = create_interface_edit(
                                params.bufnr,
                                comp_params.function_node,
                                interface_name,
                                var_name
                            )

                            if interface_edits then
                                for _, edit in ipairs(interface_edits) do
                                    table.insert(edits, edit)
                                end
                            end

                            local param_edit = create_no_params_destructuring_edit(
                                comp_params.formal_parameters,
                                var_name,
                                interface_name
                            )

                            table.insert(edits, param_edit)

                            table.insert(actions, {
                                title = string.format(
                                    "Add '%s' to props (create %s)",
                                    var_name,
                                    interface_name
                                ),
                                action = function()
                                    apply_edits(params.bufnr, edits)
                                end,
                            })
                        else
                            -- Fallback: no component name, just destructure
                            local param_edit = create_no_params_destructuring_edit(
                                comp_params.formal_parameters,
                                var_name,
                                nil
                            )

                            table.insert(actions, {
                                title = string.format("Add '%s' to props", var_name),
                                action = function()
                                    apply_edits(params.bufnr, { param_edit })
                                end,
                            })
                        end
                    else
                        -- JavaScript: just destructuring
                        local param_edit = create_no_params_destructuring_edit(
                            comp_params.formal_parameters,
                            var_name,
                            nil
                        )

                        table.insert(actions, {
                            title = string.format("Add '%s' to props", var_name),
                            action = function()
                                apply_edits(params.bufnr, { param_edit })
                            end,
                        })
                    end
                end

                return #actions > 0 and actions or nil
            end,
        },
    }
end

-- Exported for testing
M.find_component_params = find_component_params
M.already_in_destructuring = already_in_destructuring
M.already_in_type = already_in_type
M.create_destructuring_edit = create_destructuring_edit
M.create_type_edit = create_type_edit
M.extract_component_name = extract_component_name
M.create_no_params_destructuring_edit = create_no_params_destructuring_edit
M.create_interface_edit = create_interface_edit
M.find_type_declaration = find_type_declaration

return M
