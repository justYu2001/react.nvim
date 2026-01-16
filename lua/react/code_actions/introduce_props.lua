local add_to_props = require("react.code_actions.add_to_props")
local props_rename = require("react.lsp.rename.props")

local M = {}

---@param params table null-ls params
---@return table|nil {prop_name: string, jsx_element_node: TSNode, value_node: TSNode}
local function get_undefined_prop_at_cursor(params)
    local bufnr = params.bufnr
    local row = params.row - 1
    local col = params.col

    local diagnostics = vim.diagnostic.get(bufnr, { lnum = row })

    for _, diag in ipairs(diagnostics) do
        local msg = diag.message

        -- Match TypeScript prop type errors
        -- "Type '{ unknownProp: ... }' is not assignable to type 'Props'"
        -- "Property 'unknownProp' does not exist on type 'Props'"
        local prop_name = msg:match("Property '([%w_]+)' does not exist")

        if not prop_name then
            local matched = msg:match("Type '{ ([%w_]+):")

            if matched then
                prop_name = matched
            end
        end

        if prop_name then
            -- Verify cursor is on property_identifier in jsx_attribute
            local node = vim.treesitter.get_node({
                bufnr = bufnr,
                pos = { row, col },
            })

            if not node then
                goto continue
            end

            -- Check if we're on property_identifier
            if node:type() == "property_identifier" then
                local text = vim.treesitter.get_node_text(node, bufnr)

                if text == prop_name then
                    -- Walk up to find jsx_attribute
                    local jsx_attr = node:parent()

                    if jsx_attr and jsx_attr:type() == "jsx_attribute" then
                        -- Get value node
                        local value_node = nil

                        for child in jsx_attr:iter_children() do
                            if
                                child:type() == "jsx_expression"
                                or child:type() == "string"
                                or child:type() == "number"
                            then
                                value_node = child
                                break
                            end
                        end

                        -- Find jsx element (opening or self-closing)
                        local jsx_element = jsx_attr:parent()

                        if
                            jsx_element
                            and (
                                jsx_element:type() == "jsx_opening_element"
                                or jsx_element:type() == "jsx_self_closing_element"
                            )
                        then
                            return {
                                prop_name = prop_name,
                                jsx_element_node = jsx_element,
                                value_node = value_node,
                            }
                        end
                    end
                end
            end
        end

        ::continue::
    end

    return nil
end

---@param bufnr number
---@param jsx_element_node TSNode
---@return string|nil component name
local function extract_component_name(bufnr, jsx_element_node)
    -- Find identifier or member_expression child
    for child in jsx_element_node:iter_children() do
        local child_type = child:type()

        if child_type == "identifier" then
            return vim.treesitter.get_node_text(child, bufnr)
        elseif child_type == "member_expression" then
            -- Skip member expressions like <Lib.Button />
            return nil
        end
    end

    return nil
end

--- Find component definition from JSX element
---@param bufnr number
---@param jsx_element_node TSNode
---@return table|nil {bufnr: number, component_node: TSNode, file_path: string}
local function find_component_from_jsx_element(bufnr, jsx_element_node)
    local component_name = extract_component_name(bufnr, jsx_element_node)

    if not component_name then
        return nil
    end

    -- Try same file first
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

    -- Search same file
    local component_node = props_rename.find_component_by_name(bufnr, root, component_name, lang)

    if component_node then
        return {
            bufnr = bufnr,
            component_node = component_node,
            file_path = vim.api.nvim_buf_get_name(bufnr),
        }
    end

    -- Search imported files
    local import_info = props_rename.find_component_import(bufnr, root, component_name, lang)

    if import_info and import_info.component_info then
        return {
            bufnr = import_info.component_info.bufnr,
            component_node = import_info.component_info.node,
            file_path = import_info.file_path,
        }
    end

    return nil
end

---@param value_node TSNode|nil
---@return string inferred type
local function infer_type_from_literal(value_node)
    if not value_node then
        return "unknown"
    end

    local node_type = value_node:type()

    -- Handle jsx_expression wrapper
    if node_type == "jsx_expression" then
        local inner_node = value_node:named_child(0)

        if inner_node then
            value_node = inner_node
            node_type = value_node:type()
        end
    end

    if node_type == "string" or node_type == "template_string" then
        return "string"
    end

    if node_type == "number" then
        return "number"
    end

    if node_type == "true" or node_type == "false" then
        return "boolean"
    end

    if node_type == "array" then
        return "unknown[]"
    end

    if node_type == "object" then
        return "object"
    end

    return "unknown"
end

---@param type_annotation_node TSNode
---@param bufnr number
---@return string|nil type string or nil
local function extract_type_from_annotation(type_annotation_node, bufnr)
    if not type_annotation_node then
        return nil
    end

    -- Type annotation has one child: the actual type
    local type_node = type_annotation_node:named_child(0)

    if not type_node then
        return nil
    end

    local node_type = type_node:type()

    -- Primitive types
    if node_type == "predefined_type" then
        return vim.treesitter.get_node_text(type_node, bufnr)
    end

    -- Type identifiers (custom types)
    if node_type == "type_identifier" then
        return vim.treesitter.get_node_text(type_node, bufnr)
    end

    if node_type == "array_type" then
        return "unknown[]"
    end

    if node_type == "object_type" then
        return "object"
    end

    if node_type == "union_type" then
        local first_type = type_node:named_child(0)

        if first_type then
            if first_type:type() == "predefined_type" or first_type:type() == "type_identifier" then
                return vim.treesitter.get_node_text(first_type, bufnr)
            end
        end

        return "unknown"
    end

    if node_type == "intersection_type" then
        local first_type = type_node:named_child(0)

        if first_type then
            if first_type:type() == "predefined_type" or first_type:type() == "type_identifier" then
                return vim.treesitter.get_node_text(first_type, bufnr)
            end
        end

        return "unknown"
    end

    return nil
end

---@param bufnr number
---@param identifier_name string
---@param start_node TSNode
---@return TSNode|nil variable_declarator node or nil
local function find_variable_declaration(bufnr, identifier_name, start_node)
    ---@type TSNode|nil
    local current = start_node

    -- Traverse upward through scopes
    while current do
        local node_type = current:type()

        -- Check if we're in a block-like scope
        if
            node_type == "statement_block"
            or node_type == "program"
            or node_type == "arrow_function"
            or node_type == "function_declaration"
            or node_type == "function_expression"
        then
            -- Search for variable declarations in this scope
            for child in current:iter_children() do
                local child_type = child:type()

                if child_type == "lexical_declaration" or child_type == "variable_declaration" then
                    -- Check variable_declarator children
                    for declarator in child:iter_children() do
                        if declarator:type() == "variable_declarator" then
                            -- Get identifier from declarator
                            local name_node = declarator:named_child(0)

                            if name_node and name_node:type() == "identifier" then
                                local name = vim.treesitter.get_node_text(name_node, bufnr)

                                if name == identifier_name then
                                    return declarator
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Move to parent scope
        current = current:parent()
    end

    return nil
end

---@param bufnr number
---@param function_name string
---@param start_node TSNode
---@return TSNode|nil function node with return type or nil
local function find_function_declaration(bufnr, function_name, start_node)
    ---@type TSNode|nil
    local current = start_node

    -- Traverse upward through scopes
    while current do
        local node_type = current:type()

        -- Check if we're in a block-like scope
        if
            node_type == "statement_block"
            or node_type == "program"
            or node_type == "arrow_function"
            or node_type == "function_declaration"
            or node_type == "function_expression"
        then
            -- Search for function declarations in this scope
            for child in current:iter_children() do
                local child_type = child:type()

                -- Function declarations
                if child_type == "function_declaration" then
                    -- Get function name
                    for func_child in child:iter_children() do
                        if func_child:type() == "identifier" then
                            local name = vim.treesitter.get_node_text(func_child, bufnr)

                            if name == function_name then
                                return child
                            end

                            break
                        end
                    end
                end

                -- Arrow functions assigned to const
                if child_type == "lexical_declaration" or child_type == "variable_declaration" then
                    for declarator in child:iter_children() do
                        if declarator:type() == "variable_declarator" then
                            local name_node = declarator:named_child(0)

                            if name_node and name_node:type() == "identifier" then
                                local name = vim.treesitter.get_node_text(name_node, bufnr)

                                if name == function_name then
                                    -- Check if value is arrow_function or function_expression
                                    local value_node = declarator:named_child(1)

                                    if
                                        value_node
                                        and (
                                            value_node:type() == "arrow_function"
                                            or value_node:type() == "function_expression"
                                        )
                                    then
                                        return value_node
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Move to parent scope
        current = current:parent()
    end

    return nil
end

---@param bufnr number
---@param value_node TSNode
---@param depth number|nil recursion depth (default 0)
---@return string|nil inferred type or nil
local function infer_type_from_variable_declaration(bufnr, value_node, depth)
    depth = depth or 0

    -- Prevent infinite recursion
    if depth > 5 then
        return nil
    end

    if not value_node then
        return nil
    end

    local node = value_node
    local node_type = node:type()

    -- Unwrap jsx_expression
    if node_type == "jsx_expression" then
        local inner_node = node:named_child(0)

        if inner_node then
            node = inner_node
            node_type = node:type()
        end
    end

    -- Handle identifier (variable reference)
    if node_type == "identifier" then
        local identifier_name = vim.treesitter.get_node_text(node, bufnr)

        -- Find variable declaration
        local declarator = find_variable_declaration(bufnr, identifier_name, node)

        if declarator then
            -- Check for type annotation first
            for child in declarator:iter_children() do
                if child:type() == "type_annotation" then
                    return extract_type_from_annotation(child, bufnr)
                end
            end

            -- No type annotation, try to infer from initializer
            local initializer = declarator:named_child(1)

            if initializer then
                -- Recursively infer from initializer
                local inferred = infer_type_from_variable_declaration(bufnr, initializer, depth + 1)

                if inferred then
                    return inferred
                end

                -- Try literal inference on initializer
                local literal_type = infer_type_from_literal(initializer)

                if literal_type ~= "unknown" then
                    return literal_type
                end
            end
        end

        return nil
    end

    -- Handle call expression (function call)
    if node_type == "call_expression" then
        -- Get callee (function being called)
        local callee = node:named_child(0)

        if callee and callee:type() == "identifier" then
            local function_name = vim.treesitter.get_node_text(callee, bufnr)

            -- Find function declaration
            local func_node = find_function_declaration(bufnr, function_name, node)

            if func_node then
                -- Look for return type annotation
                for child in func_node:iter_children() do
                    if child:type() == "type_annotation" then
                        return extract_type_from_annotation(child, bufnr)
                    end
                end
            end
        end

        return nil
    end

    -- Handle member expression (obj.prop)
    if node_type == "member_expression" then
        -- For simple cases, try to get object type
        local object_node = node:named_child(0)

        if object_node and object_node:type() == "identifier" then
            local object_name = vim.treesitter.get_node_text(object_node, bufnr)

            -- Find object declaration
            local declarator = find_variable_declaration(bufnr, object_name, node)

            if declarator then
                -- Check for type annotation
                for child in declarator:iter_children() do
                    if child:type() == "type_annotation" then
                        -- Complex member type resolution is difficult
                        -- Return nil to fallback to LSP
                        return nil
                    end
                end

                -- Try to infer from object literal initializer
                local initializer = declarator:named_child(1)

                if initializer and initializer:type() == "object" then
                    -- Get property name from member expression
                    local property_node = node:named_child(1)

                    if property_node and property_node:type() == "property_identifier" then
                        local prop_name = vim.treesitter.get_node_text(property_node, bufnr)

                        -- Search object for matching property
                        for obj_child in initializer:iter_children() do
                            if obj_child:type() == "pair" then
                                local key_node = obj_child:named_child(0)

                                if
                                    key_node
                                    and (
                                        key_node:type() == "property_identifier"
                                        or key_node:type() == "string"
                                    )
                                then
                                    local key_text = vim.treesitter.get_node_text(key_node, bufnr)

                                    -- Clean up string keys
                                    key_text = key_text:gsub("^[\"']", ""):gsub("[\"']$", "")

                                    if key_text == prop_name then
                                        local value = obj_child:named_child(1)

                                        if value then
                                            -- Try literal inference
                                            local literal_type = infer_type_from_literal(value)

                                            if literal_type ~= "unknown" then
                                                return literal_type
                                            end

                                            -- Recursively infer
                                            return infer_type_from_variable_declaration(
                                                bufnr,
                                                value,
                                                depth + 1
                                            )
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

    return nil
end

---@param bufnr number
---@param value_node TSNode
---@return string|nil inferred type or nil
local function infer_type_from_lsp_hover(bufnr, value_node)
    ---@diagnostic disable-next-line: unused-local
    local sr, sc = value_node:range()

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = sr, character = sc },
    }

    -- Synchronous request with timeout
    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", params, 500)

    if not result then
        return nil
    end

    -- Parse hover response
    for _, res in pairs(result) do
        if res.result and res.result.contents then
            local contents = res.result.contents

            -- Handle MarkedString or MarkupContent
            local text = ""

            if type(contents) == "string" then
                text = contents
            elseif contents.value then
                text = contents.value
            elseif type(contents) == "table" and contents[1] then
                text = contents[1].value or contents[1]
            end

            -- Extract type from markdown code block
            -- Example: ```typescript\nconst foo: string\n```
            local type_match = text:match(": ([^\n]+)")

            if type_match then
                -- Clean up type (remove trailing semicolons, etc.)
                type_match = type_match:gsub(";$", ""):gsub("%s+$", "")

                return type_match
            end
        end
    end

    return nil
end

---@param bufnr number
---@param value_node TSNode|nil
---@return string inferred type
local function infer_type(bufnr, value_node)
    -- Try literals first (fast)
    local literal_type = infer_type_from_literal(value_node)

    if literal_type ~= "unknown" then
        return literal_type
    end

    -- Try static analysis (medium)
    if value_node then
        local var_type = infer_type_from_variable_declaration(bufnr, value_node)

        if var_type then
            return var_type
        end
    end

    -- Try LSP (slow, fallback)
    if value_node then
        local lsp_type = infer_type_from_lsp_hover(bufnr, value_node)

        if lsp_type then
            return lsp_type
        end
    end

    return "unknown"
end

---@param target_bufnr number buffer where component is defined
---@param comp_params table component params info
---@param prop_name string
---@param prop_type string
---@return table[] edits
local function create_prop_edits(target_bufnr, comp_params, prop_name, prop_type)
    local edits = {}

    if comp_params.type == "destructured" then
        -- Add to destructuring
        if
            not add_to_props.already_in_destructuring(
                target_bufnr,
                comp_params.pattern_node,
                prop_name
            )
        then
            table.insert(
                edits,
                add_to_props.create_destructuring_edit(comp_params.pattern_node, prop_name)
            )
        end

        -- Add to type if exists
        if comp_params.type_annotation then
            local type_annotation = comp_params.type_annotation

            -- Get type node
            local type_node = type_annotation:named_child(0)

            if type_node then
                if type_node:type() == "object_type" then
                    if not add_to_props.already_in_type(target_bufnr, type_node, prop_name) then
                        local type_edit =
                            add_to_props.create_type_edit(target_bufnr, type_node, prop_name)
                        -- Override snippet to include inferred type
                        type_edit.snippet.prop_type = prop_type
                        table.insert(edits, type_edit)
                    end
                elseif type_node:type() == "type_identifier" then
                    local type_name = vim.treesitter.get_node_text(type_node, target_bufnr)

                    local type_decl = add_to_props.find_type_declaration(target_bufnr, type_name)

                    if type_decl and type_decl.node then
                        if
                            not add_to_props.already_in_type(
                                target_bufnr,
                                type_decl.node,
                                prop_name
                            )
                        then
                            local type_edit = add_to_props.create_type_edit(
                                target_bufnr,
                                type_decl.node,
                                prop_name
                            )
                            -- Override snippet to include inferred type
                            type_edit.snippet.prop_type = prop_type
                            table.insert(edits, type_edit)
                        end
                    end
                end
            end
        end
    elseif comp_params.type == "typed_not_destructured" then
        -- Add to type only
        if comp_params.type_annotation then
            local type_annotation = comp_params.type_annotation
            local type_node = type_annotation:named_child(0)

            if type_node then
                if type_node:type() == "object_type" then
                    if not add_to_props.already_in_type(target_bufnr, type_node, prop_name) then
                        local type_edit =
                            add_to_props.create_type_edit(target_bufnr, type_node, prop_name)

                        type_edit.snippet.prop_type = prop_type

                        table.insert(edits, type_edit)
                    end
                elseif type_node:type() == "type_identifier" then
                    local type_name = vim.treesitter.get_node_text(type_node, target_bufnr)
                    local type_decl = add_to_props.find_type_declaration(target_bufnr, type_name)

                    if type_decl and type_decl.node then
                        if
                            not add_to_props.already_in_type(
                                target_bufnr,
                                type_decl.node,
                                prop_name
                            )
                        then
                            local type_edit = add_to_props.create_type_edit(
                                target_bufnr,
                                type_decl.node,
                                prop_name
                            )

                            type_edit.snippet.prop_type = prop_type

                            table.insert(edits, type_edit)
                        end
                    end
                end
            end
        end
    elseif comp_params.type == "no_params" then
        -- Create interface + destructuring
        local comp_name =
            add_to_props.extract_component_name(target_bufnr, comp_params.function_node)

        if comp_name then
            local interface_name = comp_name .. "Props"

            local interface_edits = add_to_props.create_interface_edit(
                target_bufnr,
                comp_params.function_node,
                interface_name,
                prop_name
            )

            if interface_edits then
                for _, edit in ipairs(interface_edits) do
                    -- Override snippet to include inferred type
                    if edit.snippet then
                        edit.snippet.prop_type = prop_type
                    end

                    table.insert(edits, edit)
                end
            end

            local param_edit = add_to_props.create_no_params_destructuring_edit(
                comp_params.formal_parameters,
                prop_name,
                interface_name
            )

            table.insert(edits, param_edit)
        end
    end

    return edits
end

---@param bufnr number
---@param edits table[]
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
            local prop_type = snippet_edit.snippet.prop_type or "unknown"

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
                    i(2, prop_type),
                })

                luasnip.snip_expand(snip, { pos = { expand_row, expand_col } })
            end)
        else
            -- Fallback without Luasnip
            local var_name = snippet_edit.snippet.var_name
            local indent = snippet_edit.snippet.indent
            local prop_type = snippet_edit.snippet.prop_type or "unknown"
            local text = string.format("\n%s%s?: %s", indent, var_name, prop_type)

            vim.api.nvim_buf_set_text(
                bufnr,
                snippet_edit.row,
                snippet_edit.col,
                snippet_edit.row,
                snippet_edit.col,
                vim.split(text, "\n")
            )
        end
    end
end

--- Get null-ls source
---@param null_ls table
---@return table source definition
function M.get_source(null_ls)
    return {
        name = "react-introduce-prop",
        filetypes = { "typescriptreact", "typescript" },
        method = null_ls.methods.CODE_ACTION,
        generator = {
            fn = function(params)
                local prop_info = get_undefined_prop_at_cursor(params)

                if not prop_info then
                    return nil
                end

                -- Find component definition
                local component_info =
                    find_component_from_jsx_element(params.bufnr, prop_info.jsx_element_node)

                if not component_info then
                    return nil
                end

                -- Get component params
                local sr, sc = component_info.component_node:range()
                local comp_params = add_to_props.find_component_params(component_info.bufnr, sr, sc)

                if not comp_params then
                    return nil
                end

                -- Infer type
                local prop_type = infer_type(params.bufnr, prop_info.value_node)

                -- Create edits
                local edits = create_prop_edits(
                    component_info.bufnr,
                    comp_params,
                    prop_info.prop_name,
                    prop_type
                )

                if #edits == 0 then
                    return nil
                end

                local title = string.format("Introduce prop '%s'", prop_info.prop_name)

                return {
                    {
                        title = title,
                        action = function()
                            local target_bufnr = component_info.bufnr

                            -- Ensure target buffer loaded
                            vim.fn.bufload(target_bufnr)
                            vim.bo[target_bufnr].buflisted = true

                            -- Switch to target buffer if cross-file
                            if target_bufnr ~= params.bufnr then
                                -- Find window showing target buffer
                                local target_win = nil
                                for _, win in ipairs(vim.api.nvim_list_wins()) do
                                    if vim.api.nvim_win_get_buf(win) == target_bufnr then
                                        target_win = win
                                        break
                                    end
                                end

                                if target_win then
                                    -- Switch to existing window
                                    vim.api.nvim_set_current_win(target_win)
                                else
                                    -- Switch to target buffer (vim.cmd respects buffer list)
                                    vim.cmd("buffer " .. target_bufnr)
                                end
                            end

                            -- Now in target buffer context, apply edits
                            apply_edits(target_bufnr, edits)
                        end,
                    },
                }
            end,
        },
    }
end

-- Export for testing
M.get_undefined_prop_at_cursor = get_undefined_prop_at_cursor
M.find_component_from_jsx_element = find_component_from_jsx_element
M.infer_type = infer_type

return M
