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

local function is_event_handler_prop(name)
    return name:match("^on[A-Z]") ~= nil
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

local function is_pascal_case(name)
    return name ~= nil and name:match("^[A-Z]") ~= nil
end

local function get_function_name(bufnr, function_node)
    -- Check function_declaration name
    for child in function_node:iter_children() do
        if child:type() == "identifier" then
            return vim.treesitter.get_node_text(child, bufnr)
        end
    end

    -- Check variable assignment (const Foo = () => {})
    return extract_component_name(bufnr, function_node)
end

local function has_jsx_return(_bufnr, function_node)
    local function check_node(node)
        local type = node:type()

        if
            type == "jsx_element"
            or type == "jsx_self_closing_element"
            or type == "jsx_fragment"
        then
            return true
        end

        for child in node:iter_children() do
            if check_node(child) then
                return true
            end
        end

        return false
    end

    return check_node(function_node)
end

local function is_react_component(bufnr, function_node)
    -- Check JSX return (primary signal)
    if has_jsx_return(bufnr, function_node) then
        return true
    end

    -- Check PascalCase naming convention
    local name = get_function_name(bufnr, function_node)

    return is_pascal_case(name)
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
            -- Check if this is a React component
            if not is_react_component(bufnr, current) then
                current = current:parent()
                goto continue
            end

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

        ::continue::
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

local function get_jsx_context_for_undefined_var(bufnr, row, col, var_name)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node or node:type() ~= "identifier" then
        return nil
    end

    local text = vim.treesitter.get_node_text(node, bufnr)
    if text ~= var_name then
        return nil
    end

    -- Walk up: identifier → jsx_expression → jsx_attribute → jsx_opening_element
    local current = node:parent()

    while current do
        if current:type() == "jsx_expression" then
            local jsx_attr = current:parent()
            if jsx_attr and jsx_attr:type() == "jsx_attribute" then
                -- Get prop name from property_identifier
                local prop_name = nil
                for child in jsx_attr:iter_children() do
                    if child:type() == "property_identifier" then
                        prop_name = vim.treesitter.get_node_text(child, bufnr)
                        break
                    end
                end

                if prop_name then
                    local jsx_opening = jsx_attr:parent()
                    if
                        jsx_opening
                        and (
                            jsx_opening:type() == "jsx_opening_element"
                            or jsx_opening:type() == "jsx_self_closing_element"
                        )
                    then
                        return {
                            prop_name = prop_name,
                            jsx_element_node = jsx_opening,
                        }
                    end
                end
            end
            break
        end
        current = current:parent()
    end

    return nil
end

local function find_component_from_jsx_usage(bufnr, jsx_element_node)
    -- Extract component name from jsx_element_node
    local component_name = nil
    for child in jsx_element_node:iter_children() do
        if child:type() == "identifier" or child:type() == "member_expression" then
            component_name = vim.treesitter.get_node_text(child, bufnr)
            break
        end
    end

    if not component_name then
        return nil
    end

    -- Search same file
    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        return nil
    end

    local trees = parser:parse()
    if not trees or #trees == 0 then
        return nil
    end

    local root = trees[1]:root()

    local filetype = vim.bo[bufnr].filetype
    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }
    local lang = lang_map[filetype]
    if not lang then
        return nil
    end

    -- Search for component in current file
    local query_str = [[
        (function_declaration
            name: (identifier) @func_name) @func

        (variable_declarator
            name: (identifier) @var_name
            value: [(arrow_function) (function_expression)] @func)
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)
    if not ok then
        return nil
    end

    for _, match, _ in query:iter_matches(root, bufnr) do
        local func_node = nil
        local name_node = nil

        for id, node_or_nodes in pairs(match) do
            local name = query.captures[id]
            local nodes = node_or_nodes
            local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil

            if name == "func" and node then
                func_node = node
            elseif (name == "func_name" or name == "var_name") and node then
                name_node = node
            end
        end

        if func_node and name_node then
            local found_name = vim.treesitter.get_node_text(name_node, bufnr)
            if found_name == component_name then
                return { bufnr = bufnr, component_node = func_node }
            end
        end
    end

    -- Search imports using props_rename module
    local props_rename = require("react.lsp.rename.props")
    local import_info = props_rename.find_component_import(bufnr, root, component_name, lang)

    if import_info and import_info.component_info then
        return {
            bufnr = import_info.component_info.bufnr,
            component_node = import_info.component_info.node,
        }
    end

    return nil
end

local function extract_type_string_from_node(type_node, bufnr)
    return vim.treesitter.get_node_text(type_node, bufnr)
end

local function extract_prop_type_from_component(bufnr, component_node, prop_name)
    -- Find formal_parameters
    local params_node = nil
    for child in component_node:iter_children() do
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
        return nil
    end

    -- Extract type annotation
    local type_annotation = nil
    if first_param:type() == "required_parameter" then
        local type_node = first_param:field("type")[1]
        if type_node and type_node:type() == "type_annotation" then
            type_annotation = type_node
        end
    elseif first_param:type() == "object_pattern" then
        type_annotation = get_type_annotation(first_param)
    end

    if not type_annotation then
        return nil
    end

    local type_node = type_annotation:named_child(0)
    if not type_node then
        return nil
    end

    -- Case 1: Inline object_type
    if type_node:type() == "object_type" then
        for child in type_node:iter_children() do
            if child:type() == "property_signature" then
                local prop_name_node = child:named_child(0)
                if prop_name_node then
                    local text = vim.treesitter.get_node_text(prop_name_node, bufnr)
                    if text == prop_name then
                        -- Check for optional marker
                        local has_optional = false
                        for prop_child in child:iter_children() do
                            if prop_child:type() == "?" then
                                has_optional = true
                            end
                        end
                        -- Extract type from property_signature
                        for prop_child in child:iter_children() do
                            if prop_child:type() == "type_annotation" then
                                local prop_type = prop_child:named_child(0)
                                if prop_type then
                                    return {
                                        type = extract_type_string_from_node(prop_type, bufnr),
                                        optional = has_optional,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Case 2: type_identifier reference
    if type_node:type() == "type_identifier" then
        local type_name = vim.treesitter.get_node_text(type_node, bufnr)
        local type_decl = find_type_declaration(bufnr, type_name)

        if type_decl and type_decl.node then
            for child in type_decl.node:iter_children() do
                if child:type() == "property_signature" then
                    local prop_name_node = child:named_child(0)
                    if prop_name_node then
                        local text = vim.treesitter.get_node_text(prop_name_node, bufnr)
                        if text == prop_name then
                            -- Check for optional marker
                            local has_optional = false
                            for prop_child in child:iter_children() do
                                if prop_child:type() == "?" then
                                    has_optional = true
                                end
                            end
                            for prop_child in child:iter_children() do
                                if prop_child:type() == "type_annotation" then
                                    local prop_type = prop_child:named_child(0)
                                    if prop_type then
                                        return {
                                            type = extract_type_string_from_node(prop_type, bufnr),
                                            optional = has_optional,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
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

    local decl_start_row

    -- For function_declaration, use the function node itself
    if function_node:type() == "function_declaration" then
        decl_start_row = (function_node:range())
    else
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

        decl_start_row = (decl_node:range())
    end

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

local function apply_edits(bufnr, edits, inferred_type, saved_cursor_pos)
    -- Use saved cursor position from when code action was triggered
    local initial_cursor_pos = saved_cursor_pos or vim.api.nvim_win_get_cursor(0)

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

    -- Track how normal edits affect cursor position
    local cursor_row_shift = 0
    for _, edit in ipairs(normal_edits) do
        local lines = vim.split(edit.text, "\n")
        local edit_row = edit.row_start or edit.row
        local initial_row_0indexed = initial_cursor_pos[1] - 1

        -- If edit is before cursor row, cursor shifts down
        if edit_row < initial_row_0indexed then
            cursor_row_shift = cursor_row_shift + (#lines - 1)
        end

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
        -- Direct insert when we have inferred type
        if inferred_type and inferred_type.type then
            local var_name = snippet_edit.snippet.var_name
            local indent = snippet_edit.snippet.indent
            local optional_marker = inferred_type.optional and "?" or ""
            local text =
                string.format("\n%s%s%s: %s", indent, var_name, optional_marker, inferred_type.type)

            vim.api.nvim_buf_set_text(
                bufnr,
                snippet_edit.row,
                snippet_edit.col,
                snippet_edit.row,
                snippet_edit.col,
                vim.split(text, "\n")
            )

            -- Restore cursor position using initial position
            local lines_added_by_snippet = #vim.split(text, "\n") - 1
            local initial_row_0indexed = initial_cursor_pos[1] - 1
            local initial_col = initial_cursor_pos[2]

            -- Calculate final cursor position
            local final_row = initial_cursor_pos[1] + cursor_row_shift
            local final_col = initial_col

            if initial_row_0indexed > snippet_edit.row then
                -- Cursor is after snippet insertion row, shift down by snippet lines
                final_row = final_row + lines_added_by_snippet
            elseif initial_row_0indexed == snippet_edit.row and initial_col >= snippet_edit.col then
                -- Cursor is on same row as snippet and after insertion point
                -- Content gets moved to next line
                final_row = final_row + lines_added_by_snippet
                final_col = initial_col - snippet_edit.col
            end

            vim.api.nvim_win_set_cursor(0, { final_row, final_col })
        else
            -- LuaSnip snippet for event handlers/unknown
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

                    -- Event handler heuristic or unknown
                    local type_placeholder = (is_event_handler_prop(var_name) and "() => void")
                        or "unknown"

                    local snip
                    if type_placeholder == "() => void" then
                        snip = s("", {
                            t("?"),
                            i(1),
                            t(": ("),
                            i(2),
                            t(") => "),
                            i(3, "void"),
                        })
                    else
                        snip = s("", {
                            t("?"),
                            i(1),
                            t(": "),
                            i(2, type_placeholder),
                        })
                    end

                    luasnip.snip_expand(snip, { pos = { expand_row, expand_col } })
                end)
            else
                print("Install LuaSnip for a better development experience.")

                -- Fallback: insert text and position cursor at type location
                local var_name = snippet_edit.snippet.var_name
                local indent = snippet_edit.snippet.indent
                local type_placeholder = (is_event_handler_prop(var_name) and "() => void")
                    or "unknown"
                local text = string.format("\n%s%s?: %s", indent, var_name, type_placeholder)

                vim.api.nvim_buf_set_text(
                    bufnr,
                    snippet_edit.row,
                    snippet_edit.col,
                    snippet_edit.row,
                    snippet_edit.col,
                    vim.split(text, "\n")
                )

                local col_offset = is_event_handler_prop(var_name) and #indent + #var_name + 4
                    or #indent + #var_name + 3
                vim.api.nvim_win_set_cursor(0, { snippet_edit.row + 2, col_offset })
                vim.cmd("startinsert")
            end
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
                -- Capture cursor position when code action is triggered
                local cursor_pos = vim.api.nvim_win_get_cursor(0)

                local var_name = get_undefined_var_at_cursor(params)

                if not var_name then
                    return nil
                end

                -- Try JSX context for type inference
                local jsx_ctx = get_jsx_context_for_undefined_var(
                    params.bufnr,
                    params.row - 1,
                    params.col,
                    var_name
                )
                local inferred_type = nil

                if jsx_ctx then
                    local comp_info =
                        find_component_from_jsx_usage(params.bufnr, jsx_ctx.jsx_element_node)
                    if comp_info then
                        inferred_type = extract_prop_type_from_component(
                            comp_info.bufnr,
                            comp_info.component_node,
                            jsx_ctx.prop_name
                        )
                    end
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
                            apply_edits(params.bufnr, edits, inferred_type, cursor_pos)
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
                                apply_edits(params.bufnr, { type_edit }, inferred_type, cursor_pos)
                            end,
                        })
                    end
                end

                if comp_params.type == "no_params" then
                    local filetype = vim.bo[params.bufnr].filetype
                    local is_typescript = filetype == "typescriptreact" or filetype == "typescript"

                    local edits = {}

                    if is_typescript then
                        local comp_name = get_function_name(params.bufnr, comp_params.function_node)

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
                                    apply_edits(params.bufnr, edits, inferred_type, cursor_pos)
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
                                    apply_edits(
                                        params.bufnr,
                                        { param_edit },
                                        inferred_type,
                                        cursor_pos
                                    )
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
                                apply_edits(params.bufnr, { param_edit }, inferred_type, cursor_pos)
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
M.is_event_handler_prop = is_event_handler_prop
M.get_jsx_context_for_undefined_var = get_jsx_context_for_undefined_var
M.find_component_from_jsx_usage = find_component_from_jsx_usage
M.extract_prop_type_from_component = extract_prop_type_from_component

return M
