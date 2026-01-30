local ts = require("react.util.treesitter")

local M = {}

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table|nil: {is_prop: bool, prop_name: string, context: string} or nil
function M.detect_prop_at_cursor(bufnr, pos)
    local ts_result = M.detect_prop_treesitter(bufnr)

    if ts_result then
        return ts_result
    end

    local regex_result = M.detect_prop_regex(bufnr, pos)
    return regex_result
end

---@param bufnr number: buffer number
---@return table|nil: prop info or nil
function M.detect_prop_treesitter(bufnr)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
        return nil
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)

    if not ok or not parser then
        return nil
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]

    local trees = parser:parse()
    if not trees or #trees == 0 then
        return nil
    end

    local root = trees[1]:root()

    local jsx_result = M.check_jsx_attribute(bufnr, root, row, col, lang)

    if jsx_result then
        return jsx_result
    end

    local destructure_result = M.check_destructuring(bufnr, root, row, col, lang)

    if destructure_result then
        return destructure_result
    end

    local body_var_result = M.check_body_variable(bufnr, root, row, col, lang)

    if body_var_result then
        return body_var_result
    end

    local type_result = M.check_type_signature(bufnr, root, row, col, lang)

    if type_result then
        return type_result
    end

    return nil
end

---Check if function is a React component (PascalCase name + returns JSX)
---@param function_node TSNode
---@param bufnr number
---@return boolean
function M.is_react_component(function_node, bufnr)
    -- Check if returns JSX
    local function check_jsx(node)
        local type = node:type()
        if
            type == "jsx_element"
            or type == "jsx_self_closing_element"
            or type == "jsx_fragment"
        then
            return true
        end
        for child in node:iter_children() do
            if check_jsx(child) then
                return true
            end
        end
        return false
    end

    local has_jsx = check_jsx(function_node)
    if not has_jsx then
        return false
    end

    -- Find function name
    local func_name = nil
    local func_type = function_node:type()

    if func_type == "function_declaration" then
        -- function MyComponent() {}
        for child in function_node:iter_children() do
            if child:type() == "identifier" then
                func_name = vim.treesitter.get_node_text(child, bufnr)
                break
            end
        end
    elseif func_type == "arrow_function" or func_type == "function_expression" then
        -- const MyComponent = () => {} or const MyComponent = function() {}
        local parent = function_node:parent()
        if parent and parent:type() == "variable_declarator" then
            for child in parent:iter_children() do
                if child:type() == "identifier" then
                    func_name = vim.treesitter.get_node_text(child, bufnr)
                    break
                end
            end
        end
    end

    -- Check if PascalCase (starts with uppercase)
    if not func_name or not func_name:match("^[A-Z]") then
        return false
    end

    return true
end

---@param bufnr number
---@param root TSNode
---@param row number
---@param col number
---@param lang string
---@return table|nil
function M.check_jsx_attribute(bufnr, root, row, col, lang)
    local query_str = [[
        (jsx_attribute
            (property_identifier) @prop_name)
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)

    if not ok then
        return nil
    end

    for _, match, _ in query:iter_matches(root, bufnr) do
        for id, node_or_nodes in pairs(match) do
            local name = query.captures[id]

            if name == "prop_name" then
                local nodes = node_or_nodes
                local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil

                if node then
                    local start_row, start_col, _, end_col = node:range()

                    local is_cursor_on_node = row == start_row
                        and col >= start_col
                        and col <= end_col

                    if is_cursor_on_node then
                        local prop_name = vim.treesitter.get_node_text(node, bufnr)

                        return {
                            is_prop = true,
                            prop_name = prop_name,
                            context = "jsx",
                        }
                    end
                end
            end
        end
    end

    return nil
end

---@param bufnr number
---@param root TSNode
---@param row number
---@param col number
---@param lang string
---@return table|nil
function M.check_destructuring(bufnr, root, row, col, lang)
    local query_str = [[
        (object_pattern
            (shorthand_property_identifier_pattern) @prop_name)

        (object_pattern
            (pair_pattern
                key: (property_identifier) @prop_key
                value: (identifier) @prop_alias))
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)

    if not ok then
        return nil
    end

    for _, match, _ in query:iter_matches(root, bufnr) do
        for id, node_or_nodes in pairs(match) do
            local name = query.captures[id]
            local nodes = node_or_nodes
            local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil

            if node and (name == "prop_name" or name == "prop_key" or name == "prop_alias") then
                local start_row, start_col, _, end_col = node:range()
                local is_cursor_on_node = row == start_row and col >= start_col and col <= end_col

                if is_cursor_on_node then
                    -- Check if this is in a function parameter (first param)
                    local parent = node:parent()

                    while parent do
                        local parent_type = parent:type()

                        if
                            parent_type == "formal_parameters"
                            or parent_type == "required_parameter"
                        then
                            -- Check if it's the first parameter
                            -- For required_parameter, parent is formal_parameters, grandparent is function
                            -- For formal_parameters (direct), parent is function
                            local function_node = nil

                            if parent_type == "required_parameter" then
                                -- Go up two levels: required_parameter -> formal_parameters -> function
                                local formal_params = parent:parent()

                                if
                                    formal_params
                                    and formal_params:type() == "formal_parameters"
                                then
                                    function_node = formal_params:parent()
                                end
                            else
                                -- parent is formal_parameters, so parent of that is function
                                function_node = parent:parent()
                            end

                            if
                                function_node
                                and (
                                    function_node:type() == "function_declaration"
                                    or function_node:type() == "arrow_function"
                                    or function_node:type() == "function_expression"
                                )
                            then
                                -- Check if React component
                                if not M.is_react_component(function_node, bufnr) then
                                    break
                                end

                                local _prop_name
                                local cursor_target

                                if name == "prop_name" then
                                    -- Shorthand { name }
                                    _prop_name = vim.treesitter.get_node_text(node, bufnr)
                                    cursor_target = "shorthand"
                                elseif name == "prop_key" then
                                    -- Cursor on KEY in { name: alias }
                                    _prop_name = vim.treesitter.get_node_text(node, bufnr)
                                    cursor_target = "key"
                                elseif name == "prop_alias" then
                                    -- Cursor on ALIAS in { name: alias }
                                    -- Get the key name
                                    local pair_parent = node:parent()

                                    if pair_parent and pair_parent:type() == "pair_pattern" then
                                        for child in pair_parent:iter_children() do
                                            if child:type() == "property_identifier" then
                                                _prop_name =
                                                    vim.treesitter.get_node_text(child, bufnr)
                                                break
                                            end
                                        end
                                    end
                                    cursor_target = "alias"
                                end

                                if _prop_name then
                                    return {
                                        is_prop = true,
                                        prop_name = _prop_name,
                                        context = "destructure",
                                        cursor_target = cursor_target,
                                    }
                                end
                            end
                            break
                        end
                        parent = parent:parent()
                    end
                end
            end
        end
    end

    return nil
end

---@param bufnr number
---@param _root TSNode
---@param row number
---@param col number
---@param _lang string
---@return table|nil
function M.check_body_variable(bufnr, _root, row, col, _lang)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    if node:type() ~= "identifier" then
        return nil
    end

    local var_name = vim.treesitter.get_node_text(node, bufnr)

    local current = node

    while current do
        local node_type = current:type()

        if
            node_type == "arrow_function"
            or node_type == "function_declaration"
            or node_type == "function_expression"
        then
            -- Check if React component
            if not M.is_react_component(current, bufnr) then
                break
            end

            -- Found function, check if it has props destructuring
            local params_node = nil

            for child in current:iter_children() do
                if child:type() == "formal_parameters" then
                    params_node = child
                    break
                end
            end

            if params_node then
                -- Check if any parameter has destructuring with var_name
                for param in params_node:iter_children() do
                    local param_type = param:type()

                    if param_type == "required_parameter" or param_type == "object_pattern" then
                        local obj_pattern = nil

                        if param_type == "required_parameter" then
                            -- Get object_pattern from required_parameter
                            for child in param:iter_children() do
                                if child:type() == "object_pattern" then
                                    obj_pattern = child
                                    break
                                end
                            end
                        else
                            obj_pattern = param
                        end

                        if obj_pattern then
                            -- Check if obj_pattern contains var_name
                            for prop in obj_pattern:iter_children() do
                                local prop_type = prop:type()

                                if prop_type == "shorthand_property_identifier_pattern" then
                                    local prop_name = vim.treesitter.get_node_text(prop, bufnr)

                                    if prop_name == var_name then
                                        return {
                                            is_prop = true,
                                            prop_name = var_name,
                                            context = "body",
                                        }
                                    end
                                elseif prop_type == "pair_pattern" then
                                    -- Check both key and alias
                                    for pair_child in prop:iter_children() do
                                        local pair_child_type = pair_child:type()

                                        -- Skip property_identifier (the key), we want the identifier (the alias)
                                        if pair_child_type == "identifier" then
                                            -- This is the alias - the variable used in body
                                            local alias =
                                                vim.treesitter.get_node_text(pair_child, bufnr)

                                            if alias == var_name then
                                                -- Return the KEY name, not the alias
                                                -- Find the key
                                                for key_child in prop:iter_children() do
                                                    if
                                                        key_child:type() == "property_identifier"
                                                    then
                                                        local key_name =
                                                            vim.treesitter.get_node_text(
                                                                key_child,
                                                                bufnr
                                                            )

                                                        return {
                                                            is_prop = true,
                                                            prop_name = key_name,
                                                            context = "body",
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
                end
            end

            -- Found function but no matching prop, stop searching
            break
        end
        current = current:parent()
    end

    return nil
end

---@param bufnr number
---@param root TSNode
---@param row number
---@param col number
---@param lang string
---@return table|nil
function M.check_type_signature(bufnr, root, row, col, lang)
    if lang ~= "typescript" and lang ~= "tsx" then
        return nil
    end

    local query_str = [[
        (property_signature
            name: (property_identifier) @prop_name)
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)

    if not ok then
        return nil
    end

    for _, match, _ in query:iter_matches(root, bufnr) do
        for id, node_or_nodes in pairs(match) do
            local name = query.captures[id]

            if name == "prop_name" then
                local nodes = node_or_nodes

                local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil

                if node then
                    local start_row, start_col, _, end_col = node:range()
                    local is_cursor_on_node = row == start_row
                        and col >= start_col
                        and col <= end_col

                    if is_cursor_on_node then
                        local prop_name = vim.treesitter.get_node_text(node, bufnr)

                        -- Check if this type is used by a React component
                        -- First try to find named type/interface
                        local type_name = M.find_type_name_for_node(node)
                        if type_name then
                            local component_node =
                                M.find_component_using_type(bufnr, root, type_name, lang)
                            if component_node then
                                if not M.is_react_component(component_node, bufnr) then
                                    return nil
                                end
                            end
                        else
                            -- Inline type: walk up to find function
                            local current = node
                            while current do
                                local node_type = current:type()
                                if
                                    node_type == "arrow_function"
                                    or node_type == "function_declaration"
                                    or node_type == "function_expression"
                                then
                                    if not M.is_react_component(current, bufnr) then
                                        return nil
                                    end
                                    break
                                end
                                current = current:parent()
                            end
                        end

                        return {
                            is_prop = true,
                            prop_name = prop_name,
                            context = "type",
                        }
                    end
                end
            end
        end
    end

    return nil
end

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table|nil: prop info or nil
function M.detect_prop_regex(bufnr, pos)
    local line = vim.api.nvim_buf_get_lines(bufnr, pos[1] - 1, pos[1], false)[1]

    if not line then
        return nil
    end

    local col = pos[2] + 1

    -- Check JSX attribute: <Component propName={...}
    local jsx_pattern = "(%w+)%s*=%s*{"

    for prop_name in line:gmatch(jsx_pattern) do
        local prop_start = line:find(prop_name, 1, true)

        if prop_start and col >= prop_start and col < prop_start + #prop_name then
            return {
                is_prop = true,
                prop_name = prop_name,
                context = "jsx",
            }
        end
    end

    -- NOTE: Regex fallback is only for cases where treesitter parsing fails
    -- Destructuring and type checks need React component validation
    -- which regex can't do reliably, so we skip them here
    return nil
end

---@param node TSNode
---@return string|nil: type/interface name if node is inside type declaration
function M.find_type_name_for_node(node)
    ---@type TSNode|nil
    local current = node

    while current do
        local node_type = current:type()
        -- Check for interface or type alias declaration

        if node_type == "interface_declaration" or node_type == "type_alias_declaration" then
            -- Find the name child
            for child in current:iter_children() do
                if child:type() == "type_identifier" then
                    return vim.treesitter.get_node_text(child, vim.api.nvim_get_current_buf())
                end
            end
        end
        current = current:parent()
    end
    return nil
end

---@param bufnr number
---@param root TSNode
---@param type_name string
---@param lang string
---@return TSNode|nil: function node that uses this type
function M.find_component_using_type(bufnr, root, type_name, lang)
    -- Query for functions with typed parameters
    local query_str = [[
        (variable_declarator
            name: (identifier)
            value: (arrow_function
                parameters: (formal_parameters
                    (required_parameter
                        pattern: (object_pattern)
                        type: (type_annotation
                            (type_identifier) @type_ref)))) @func)

        (function_declaration
            parameters: (formal_parameters
                (required_parameter
                    pattern: (object_pattern)
                    type: (type_annotation
                        (type_identifier) @type_ref))) @func)
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)

    if not ok then
        return nil
    end

    for _, match, _ in query:iter_matches(root, bufnr) do
        local func_node = nil
        local type_ref_node = nil

        for id, node_or_nodes in pairs(match) do
            local name = query.captures[id]
            local nodes = node_or_nodes
            local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil

            if name == "func" and node then
                func_node = node
            elseif name == "type_ref" and node then
                type_ref_node = node
            end
        end

        -- Check if type_ref matches our type_name
        if func_node and type_ref_node then
            local ref_name = vim.treesitter.get_node_text(type_ref_node, bufnr)

            if ref_name == type_name then
                return func_node
            end
        end
    end

    return nil
end

--- Find JSX component name from node (walks up to jsx element)
---@param node TSNode
---@return string|nil: component name if in JSX usage
function M.find_jsx_component_name(node)
    ---@type TSNode|nil
    local current = node

    while current do
        local node_type = current:type()

        -- Check for JSX opening or self-closing element
        if node_type == "jsx_opening_element" or node_type == "jsx_self_closing_element" then
            -- Find the identifier/member_expression child
            for child in current:iter_children() do
                local child_type = child:type()

                if child_type == "identifier" or child_type == "member_expression" then
                    return vim.treesitter.get_node_text(child, vim.api.nvim_get_current_buf())
                end
            end
        end

        current = current:parent()
    end
    return nil
end

--- Find component definition by name in buffer
---@param bufnr number
---@param root TSNode
---@param component_name string
---@param lang string
---@return TSNode|nil: function node or nil
function M.find_component_by_name(bufnr, root, component_name, lang)
    -- Query for function declarations and variable declarations with arrow functions
    local query_str = [[
        (function_declaration
            name: (identifier) @func_name) @func

        (variable_declarator
            name: (identifier) @var_name
            value: [(arrow_function) (function_expression)] @func)

        (export_statement
            declaration: (function_declaration
                name: (identifier) @func_name) @func)

        (export_statement
            declaration: (lexical_declaration
                (variable_declarator
                    name: (identifier) @var_name
                    value: [(arrow_function) (function_expression)] @func)))
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

        -- Check if name matches
        if func_node and name_node then
            local found_name = vim.treesitter.get_node_text(name_node, bufnr)

            if found_name == component_name then
                return func_node
            end
        end
    end

    return nil
end

--- Find component in imported files
---@param bufnr number
---@param root TSNode
---@param component_name string
---@param lang string
---@return table|nil: {file_path: string, component_info: table}
function M.find_component_import(bufnr, root, component_name, lang)
    -- Query for import statements
    local query_str = [[
        (import_statement
            (import_clause
                (named_imports
                    (import_specifier
                        name: (identifier) @import_name)))
            source: (string) @import_path)
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)
    if not ok then
        return nil
    end

    -- Find import for component
    local import_path = nil

    for _, match, _ in query:iter_matches(root, bufnr) do
        local import_name_node = nil
        local import_path_node = nil

        for id, node_or_nodes in pairs(match) do
            local name = query.captures[id]
            local nodes = node_or_nodes
            local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil

            if name == "import_name" and node then
                import_name_node = node
            elseif name == "import_path" and node then
                import_path_node = node
            end
        end

        if import_name_node and import_path_node then
            local import_name = vim.treesitter.get_node_text(import_name_node, bufnr)

            if import_name == component_name then
                local raw_path = vim.treesitter.get_node_text(import_path_node, bufnr)

                -- Remove quotes
                import_path = raw_path:gsub("^['\"]", ""):gsub("['\"]$", "")
                break
            end
        end
    end

    if not import_path then
        return nil
    end

    -- Resolve import path
    local current_file = vim.api.nvim_buf_get_name(bufnr)
    local current_dir = vim.fn.fnamemodify(current_file, ":h")
    local resolved_path = vim.fn.resolve(current_dir .. "/" .. import_path)

    -- Try common extensions
    local extensions = { ".tsx", ".ts", ".jsx", ".js" }
    local import_file = nil

    for _, ext in ipairs(extensions) do
        local try_path = resolved_path .. ext

        if vim.fn.filereadable(try_path) == 1 then
            import_file = try_path
            break
        end
    end

    if not import_file then
        return nil
    end

    -- Read and parse imported file
    local import_bufnr = vim.fn.bufadd(import_file)
    vim.fn.bufload(import_bufnr)

    local ok_parser, import_parser = pcall(vim.treesitter.get_parser, import_bufnr, lang)

    if not ok_parser or not import_parser then
        return nil
    end

    local import_trees = import_parser:parse()

    if not import_trees or #import_trees == 0 then
        return nil
    end

    local import_root = import_trees[1]:root()

    -- Search for component in imported file
    local component_node = M.find_component_by_name(import_bufnr, import_root, component_name, lang)
    if component_node then
        local start_row, start_col, end_row, end_col = component_node:range()

        return {
            file_path = import_file,
            component_info = {
                node = component_node,
                bufnr = import_bufnr,
                range = {
                    start = { line = start_row, character = start_col },
                    ["end"] = { line = end_row, character = end_col },
                },
            },
        }
    end

    return nil
end

---@param bufnr number: buffer number
---@param _prop_name string: prop name to find
---@param context_pos table: cursor position where detection happened
---@return table|nil: component info or nil
function M.find_component_for_prop(bufnr, _prop_name, context_pos)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
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
    local row = context_pos[1] - 1
    local col = context_pos[2]

    -- Get node at cursor
    local node = root:descendant_for_range(row, col, row, col)

    if not node then
        return nil
    end

    -- Check if we're in JSX usage
    local jsx_component_name = M.find_jsx_component_name(node)

    if jsx_component_name then
        -- Search for component definition in buffer
        local component_node = M.find_component_by_name(bufnr, root, jsx_component_name, lang)

        if component_node then
            local start_row, start_col, end_row, end_col = component_node:range()

            return {
                node = component_node,
                bufnr = bufnr,
                range = {
                    start = { line = start_row, character = start_col },
                    ["end"] = { line = end_row, character = end_col },
                },
            }
        else
            -- Try to find in imported files
            local import_info = M.find_component_import(bufnr, root, jsx_component_name, lang)

            if import_info then
                return import_info.component_info
            end
        end
    end

    -- Check if we're in a type/interface declaration
    local type_name = M.find_type_name_for_node(node)

    if type_name then
        -- Search for component using this type
        local component_node = M.find_component_using_type(bufnr, root, type_name, lang)

        if component_node then
            local start_row, start_col, end_row, end_col = component_node:range()
            return {
                node = component_node,
                bufnr = bufnr,
                range = {
                    start = { line = start_row, character = start_col },
                    ["end"] = { line = end_row, character = end_col },
                },
            }
        end
    end

    -- Search upward for function/arrow_function (original logic)
    local search_node = node

    while search_node do
        local node_type = search_node:type()

        if
            node_type == "function_declaration"
            or node_type == "arrow_function"
            or node_type == "function_expression"
        then
            local start_row, start_col, end_row, end_col = search_node:range()

            return {
                node = search_node,
                bufnr = bufnr,
                range = {
                    start = { line = start_row, character = start_col },
                    ["end"] = { line = end_row, character = end_col },
                },
            }
        end

        search_node = search_node:parent()
    end

    return nil
end

---@param bufnr number: buffer number
---@param component_info table|nil: component info from find_component_for_prop
---@param prop_name string: prop name to find
---@return table: {found: bool, range: table|nil, is_aliased: bool, current_alias: string|nil}
function M.find_destructure_location(bufnr, component_info, prop_name)
    if not component_info or not component_info.node then
        return { found = false }
    end

    -- Use component_info.bufnr if available (for imported components)
    local target_bufnr = component_info.bufnr or bufnr
    local component_node = component_info.node

    -- Find formal_parameters
    for child in component_node:iter_children() do
        if child:type() == "formal_parameters" then
            -- Look for object_pattern in first parameter
            for param_child in child:iter_children() do
                local param_type = param_child:type()

                if param_type == "required_parameter" or param_type == "object_pattern" then
                    -- Find the object_pattern
                    local object_pattern_node = nil

                    if param_type == "object_pattern" then
                        object_pattern_node = param_child
                    else
                        for sub_child in param_child:iter_children() do
                            if sub_child:type() == "object_pattern" then
                                object_pattern_node = sub_child
                                break
                            end
                        end
                    end

                    if object_pattern_node then
                        -- Search for prop in object_pattern
                        for prop_child in object_pattern_node:iter_children() do
                            local prop_type = prop_child:type()

                            -- Check shorthand
                            if prop_type == "shorthand_property_identifier_pattern" then
                                local name = vim.treesitter.get_node_text(prop_child, target_bufnr)

                                if name == prop_name then
                                    local start_row, start_col, end_row, end_col =
                                        prop_child:range()

                                    return {
                                        found = true,
                                        range = {
                                            start = { line = start_row, character = start_col },
                                            ["end"] = { line = end_row, character = end_col },
                                        },
                                        is_aliased = false,
                                    }
                                end
                            elseif prop_type == "pair_pattern" then
                                -- Check pair_pattern (aliased)
                                local key_node = nil
                                local value_node = nil

                                for pair_child in prop_child:iter_children() do
                                    if pair_child:type() == "property_identifier" then
                                        key_node = pair_child
                                    elseif pair_child:type() == "identifier" then
                                        value_node = pair_child
                                    end
                                end

                                if key_node then
                                    local key_name =
                                        vim.treesitter.get_node_text(key_node, target_bufnr)

                                    if key_name == prop_name then
                                        local start_row, start_col, end_row, end_col =
                                            prop_child:range()

                                        local current_alias = value_node
                                                and vim.treesitter.get_node_text(
                                                    value_node,
                                                    target_bufnr
                                                )
                                            or nil

                                        return {
                                            found = true,
                                            range = {
                                                start = { line = start_row, character = start_col },
                                                ["end"] = { line = end_row, character = end_col },
                                            },
                                            is_aliased = true,
                                            current_alias = current_alias,
                                        }
                                    end
                                end
                            end
                        end
                    end
                    break
                end
            end
            break
        end
    end

    return { found = false }
end

---@param bufnr number: buffer number
---@param destructure_info table: destructure location info
---@param old_name string: old prop name
---@param new_name string: new prop name
---@return table: TextEdit for alias transformation
function M.create_alias_edit(bufnr, destructure_info, old_name, new_name)
    local range = destructure_info.range

    -- Get current text
    local start_line = range.start.line
    local end_line = range["end"].line

    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)

    if #lines == 0 then
        return {
            range = range,
            newText = old_name .. ": " .. new_name,
        }
    end

    -- Transform to alias syntax
    local new_text

    if destructure_info.is_aliased then
        -- Already aliased: { foo: bar } → { foo: newName }
        new_text = old_name .. ": " .. new_name
    else
        -- Shorthand: { foo } → { foo: newName }
        new_text = old_name .. ": " .. new_name
    end

    return {
        range = range,
        newText = new_text,
    }
end

---Find position of alias variable in destructure pattern after first rename
---After first rename applied, buffer has { newName: oldName }, find position of oldName
---@param bufnr number
---@param destructure_range table LSP range (original range before any edits)
---@param old_name string original prop name to find in alias position
---@return table|nil LSP Position {line, character}
function M.find_alias_variable_position(bufnr, destructure_range, old_name)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
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

    -- Get node at destructure_range start position
    local row = destructure_range.start.line
    local col = destructure_range.start.character
    local node = root:descendant_for_range(row, col, row, col)

    if not node then
        return nil
    end

    -- Walk up to find object_pattern
    local current = node

    while current do
        if current:type() == "object_pattern" then
            -- Found object_pattern, look for pair_pattern with value = old_name
            for child in current:iter_children() do
                if child:type() == "pair_pattern" then
                    -- Get the value node (identifier)
                    for pair_child in child:iter_children() do
                        if pair_child:type() == "identifier" then
                            local text = vim.treesitter.get_node_text(pair_child, bufnr)

                            if text == old_name then
                                -- Found it! Return LSP position
                                local start_row, start_col = pair_child:range()

                                return {
                                    line = start_row,
                                    character = start_col,
                                }
                            end
                        end
                    end
                end
            end
            break
        end

        current = current:parent()
    end

    return nil
end

---Find position of key in destructure pattern after renaming alias
---After renaming alias, buffer has { oldKey: newName }, find position of oldKey
---@param bufnr number
---@param destructure_range table LSP range
---@param key_name string the key name to find
---@return table|nil LSP Position {line, character}
function M.find_key_position(bufnr, destructure_range, key_name)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
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

    -- Get node at destructure_range start position
    local row = destructure_range.start.line
    local col = destructure_range.start.character
    local node = root:descendant_for_range(row, col, row, col)

    if not node then
        return nil
    end

    -- Walk up to find object_pattern
    local current = node

    while current do
        if current:type() == "object_pattern" then
            -- Found object_pattern, look for pair_pattern with key = key_name
            for child in current:iter_children() do
                if child:type() == "pair_pattern" then
                    -- Get the key node (property_identifier)
                    for pair_child in child:iter_children() do
                        if pair_child:type() == "property_identifier" then
                            local text = vim.treesitter.get_node_text(pair_child, bufnr)

                            if text == key_name then
                                -- Found it! Return LSP position
                                local start_row, start_col = pair_child:range()

                                return {
                                    line = start_row,
                                    character = start_col,
                                }
                            end
                        end
                    end
                end
            end
            break
        end

        current = current:parent()
    end

    return nil
end

---Convert { bar: bar } to { bar } in buffer after rename is applied
---Finds pair_pattern nodes where key and value match, converts to shorthand
---@param bufnr number
---@param name string the prop name
function M.convert_to_shorthand_in_buffer(bufnr, name)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]
    if not lang then
        return
    end

    local parser = vim.treesitter.get_parser(bufnr, lang)
    local root = parser:parse()[1]:root()

    local replacements = {}

    -- Recursive function to traverse tree
    local function traverse(node)
        if node:type() == "pair_pattern" then
            local key_node = nil
            local value_node = nil

            -- Find key and value children
            for child in node:iter_children() do
                if child:type() == "property_identifier" then
                    key_node = child
                elseif child:type() == "identifier" then
                    value_node = child
                end
            end

            -- Check if both exist and match target name
            if key_node and value_node then
                local key_text = vim.treesitter.get_node_text(key_node, bufnr)
                local value_text = vim.treesitter.get_node_text(value_node, bufnr)

                if key_text == name and value_text == name then
                    local start_row, start_col, end_row, end_col = node:range()

                    table.insert(replacements, {
                        start_row = start_row,
                        start_col = start_col,
                        end_row = end_row,
                        end_col = end_col,
                        text = name,
                    })
                end
            end
        end

        -- Recurse to children
        for child in node:iter_children() do
            traverse(child)
        end
    end

    traverse(root)

    -- Apply replacements (reverse order to maintain positions)
    table.sort(replacements, function(a, b)
        if a.start_row ~= b.start_row then
            return a.start_row > b.start_row
        end

        return a.start_col > b.start_col
    end)

    for _, replacement in ipairs(replacements) do
        vim.api.nvim_buf_set_text(
            bufnr,
            replacement.start_row,
            replacement.start_col,
            replacement.end_row,
            replacement.end_col,
            { replacement.text }
        )
    end
end

--- Calculate cursor offset within prop name
--- @param bufnr number buffer number
--- @param pos table {row, col} cursor position (1-indexed row, 0-indexed col)
--- @param prop_name string the prop name at cursor
--- @return number|nil offset from start of prop name, or nil if can't determine
function M.calculate_cursor_offset(bufnr, pos, prop_name)
    local row, col = pos[1] - 1, pos[2] -- Convert to 0-indexed

    -- Get line content
    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)

    if not lines or #lines == 0 then
        return nil
    end

    local line = lines[1]

    -- Find prop name at or before cursor position
    -- Search backward from cursor to find start of identifier
    -- Note: col is 0-indexed, line:sub is 1-indexed, so add 1
    local prop_start = col

    while prop_start > 0 do
        local char = line:sub(prop_start + 1, prop_start + 1)

        if not char:match("[%w_]") then
            break
        end

        prop_start = prop_start - 1
    end

    -- Search forward to find end
    local prop_end = col + 1

    while prop_end <= #line do
        local char = line:sub(prop_end + 1, prop_end + 1)

        if not char:match("[%w_]") then
            break
        end

        prop_end = prop_end + 1
    end

    local found_name = line:sub(prop_start + 2, prop_end)

    -- Verify this matches the prop name we expect
    if found_name ~= prop_name then
        -- Try to find exact match near cursor
        local pattern = "%f[%w_]" .. vim.pesc(prop_name) .. "%f[^%w_]"
        local start_idx, end_idx = line:find(pattern)

        if start_idx and col >= start_idx - 1 and col < end_idx then
            -- start_idx is 1-indexed position of first char, convert to 0-indexed and go back one
            prop_start = start_idx - 2
        else
            return 0 -- Fallback to beginning
        end
    end

    -- Calculate offset: cursor position - start of identifier
    -- prop_start is position before identifier, so identifier starts at prop_start + 1
    local offset = col - (prop_start + 1)

    return math.max(0, offset)
end

--- Restore cursor position after prop rename
--- @param bufnr number buffer number
--- @param win number window handle
--- @param new_prop_name string renamed prop name
--- @param original_pos table|nil original cursor position {row, col} (1-indexed row, 0-indexed col)
--- @param offset number cursor offset within prop name (0-indexed)
function M.restore_cursor_position(bufnr, win, new_prop_name, original_pos, offset)
    -- Validate window is still valid
    if not vim.api.nvim_win_is_valid(win) then
        return
    end

    -- Ensure window is showing the correct buffer
    if vim.api.nvim_win_get_buf(win) ~= bufnr then
        return
    end

    -- Use original position to stay at rename location
    if not original_pos then
        return
    end

    local row = original_pos[1] - 1 -- Convert to 0-indexed
    local col = original_pos[2]

    -- Get line at original position
    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)

    if not lines or #lines == 0 then
        return
    end

    local line = lines[1]

    -- Find identifier start at or before cursor position
    -- Search backward from cursor to find start of identifier
    -- Note: col is 0-indexed, line:sub is 1-indexed, so add 1
    local prop_start = col

    while prop_start > 0 do
        local char = line:sub(prop_start + 1, prop_start + 1)

        if not char:match("[%w_]") then
            break
        end

        prop_start = prop_start - 1
    end

    -- Calculate new cursor position: identifier start + offset
    -- prop_start is 0-indexed position before identifier, so identifier starts at prop_start + 1
    local clamped_offset = math.min(offset, #new_prop_name)
    local new_col = prop_start + 1 + clamped_offset

    -- Set cursor at original row with adjusted column
    vim.api.nvim_win_set_cursor(win, { row + 1, new_col })
end

return M
