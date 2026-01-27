local ts = require("react.util.treesitter")
local utils = require("react.lsp.rename.utils")

local M = {}

-- Check if file is TypeScript
local function is_typescript_file(bufnr)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    return filetype == "typescript" or filetype == "typescriptreact"
end

---@param component_name string: component name
---@return string: props type name
function M.calculate_props_type_name(component_name)
    if not component_name or component_name == "" then
        return ""
    end
    return component_name .. "Props"
end

---@param props_type_name string: props type name
---@return string|nil: component name or nil if not matching pattern
function M.calculate_component_name(props_type_name)
    if not props_type_name or not props_type_name:match("Props$") then
        return nil
    end

    local component_name = props_type_name:sub(1, -6) -- Remove "Props" suffix

    if component_name == "" then
        return nil
    end

    return component_name
end

-- Check if identifier is PascalCase (component naming convention)
local function is_pascal_case(name)
    return name ~= nil and name:match("^[A-Z]") ~= nil
end

-- Check if function node returns JSX (copied from add_to_props.lua)
local function has_jsx_return(function_node)
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

-- Find type declaration (interface or type alias) by name
local function find_type_declaration(bufnr, type_name)
    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        return nil
    end

    local trees = parser:parse()
    if not trees or #trees == 0 then
        return nil
    end

    local root = trees[1]:root()

    local function traverse(node)
        if node:type() == "interface_declaration" or node:type() == "type_alias_declaration" then
            local name_node = node:named_child(0)
            if name_node and name_node:type() == "type_identifier" then
                local name = vim.treesitter.get_node_text(name_node, bufnr)
                if name == type_name then
                    return {
                        node = node,
                        name_node = name_node,
                    }
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

-- Find component by name
local function find_component_by_name(bufnr, component_name)
    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local ft = vim.bo[bufnr].filetype
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

    local query_str = [[
        (function_declaration
            name: (identifier) @func_name) @func

        (variable_declarator
            name: (identifier) @var_name
            value: [(arrow_function) (function_expression)] @func)
    ]]

    local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_str)
    if not ok_query then
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
                return {
                    node = func_node,
                    name_node = name_node,
                }
            end
        end
    end

    return nil
end

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table|nil: {is_component: bool, component_name: string, props_type_name: string, type_location: table|nil}
function M.is_component_name(bufnr, pos)
    if not is_typescript_file(bufnr) then
        return { is_component = false }
    end

    local lang_map = {
        typescript = "typescript",
        typescriptreact = "tsx",
    }

    local ft = vim.bo[bufnr].filetype
    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
        return { is_component = false }
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then
        return { is_component = false }
    end

    local trees = parser:parse()
    if not trees or #trees == 0 then
        return { is_component = false }
    end

    local root = trees[1]:root()
    local row = pos[1] - 1
    local col = pos[2]

    local node = root:descendant_for_range(row, col, row, col)
    if not node or node:type() ~= "identifier" then
        return { is_component = false }
    end

    local component_name = vim.treesitter.get_node_text(node, bufnr)

    -- Check if PascalCase
    if not is_pascal_case(component_name) then
        return { is_component = false }
    end

    -- Check if this is a function declaration name
    local parent = node:parent()
    if not parent then
        return { is_component = false }
    end

    local is_func_decl = false
    local function_node = nil

    -- Direct function declaration: function Button() {}
    if parent:type() == "function_declaration" then
        is_func_decl = true
        function_node = parent
    end

    -- Variable declarator: const Button = ...
    if parent:type() == "variable_declarator" then
        -- Check if value is arrow_function or function_expression
        for child in parent:iter_children() do
            if child:type() == "arrow_function" or child:type() == "function_expression" then
                is_func_decl = true
                function_node = child
                break
            end
        end
    end

    if not is_func_decl or not function_node then
        return { is_component = false }
    end

    -- Verify it returns JSX (optional but recommended)
    if not has_jsx_return(function_node) then
        return { is_component = false }
    end

    -- Calculate expected props type name
    local props_type_name = M.calculate_props_type_name(component_name)

    -- Check if props type exists in buffer
    local type_info = find_type_declaration(bufnr, props_type_name)

    return {
        is_component = true,
        component_name = component_name,
        props_type_name = props_type_name,
        type_location = type_info and {
            bufnr = bufnr,
            node = type_info.name_node,
        } or nil,
    }
end

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table|nil: {is_props_type: bool, component_name: string, props_type_name: string, component_location: table|nil}
function M.is_props_type_name(bufnr, pos)
    if not is_typescript_file(bufnr) then
        return { is_props_type = false }
    end

    local lang_map = {
        typescript = "typescript",
        typescriptreact = "tsx",
    }

    local ft = vim.bo[bufnr].filetype
    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
        return { is_props_type = false }
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then
        return { is_props_type = false }
    end

    local trees = parser:parse()
    if not trees or #trees == 0 then
        return { is_props_type = false }
    end

    local root = trees[1]:root()
    local row = pos[1] - 1
    local col = pos[2]

    local node = root:descendant_for_range(row, col, row, col)
    if not node or node:type() ~= "type_identifier" then
        return { is_props_type = false }
    end

    local type_name = vim.treesitter.get_node_text(node, bufnr)

    -- Check if ends with "Props"
    local component_name = M.calculate_component_name(type_name)
    if not component_name then
        return { is_props_type = false }
    end

    -- Walk up to find interface_declaration or type_alias_declaration
    local current = node:parent()
    local is_type_decl = false

    while current do
        local node_type = current:type()
        if node_type == "interface_declaration" or node_type == "type_alias_declaration" then
            is_type_decl = true
            break
        end
        current = current:parent()
    end

    if not is_type_decl then
        return { is_props_type = false }
    end

    -- Check if component exists in buffer
    local component_info = find_component_by_name(bufnr, component_name)

    return {
        is_props_type = true,
        component_name = component_name,
        props_type_name = type_name,
        component_location = component_info and {
            bufnr = bufnr,
            node = component_info.name_node,
        } or nil,
    }
end

---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@return table: {is_usage: bool, component_name: string, props_type_name: string, type_location: table|nil}
function M.is_component_usage_in_same_file(bufnr, pos)
    if not is_typescript_file(bufnr) then
        return { is_usage = false }
    end

    local lang_map = {
        typescript = "typescript",
        typescriptreact = "tsx",
    }

    local ft = vim.bo[bufnr].filetype
    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
        return { is_usage = false }
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then
        return { is_usage = false }
    end

    local trees = parser:parse()
    if not trees or #trees == 0 then
        return { is_usage = false }
    end

    local root = trees[1]:root()
    local row = pos[1] - 1
    local col = pos[2]

    local node = root:descendant_for_range(row, col, row, col)
    if not node or node:type() ~= "identifier" then
        return { is_usage = false }
    end

    -- Check if parent is JSX opening or self-closing element
    local parent = node:parent()
    if not parent then
        return { is_usage = false }
    end

    local is_jsx_usage = parent:type() == "jsx_opening_element"
        or parent:type() == "jsx_self_closing_element"

    if not is_jsx_usage then
        return { is_usage = false }
    end

    local component_name = vim.treesitter.get_node_text(node, bufnr)

    -- Check if PascalCase
    if not is_pascal_case(component_name) then
        return { is_usage = false }
    end

    -- Find component definition in same file
    local component_info = find_component_by_name(bufnr, component_name)
    if not component_info then
        return { is_usage = false }
    end

    -- Calculate expected props type name
    local props_type_name = M.calculate_props_type_name(component_name)

    -- Check if props type exists in buffer
    local type_info = find_type_declaration(bufnr, props_type_name)

    return {
        is_usage = true,
        component_name = component_name,
        props_type_name = props_type_name,
        type_location = type_info and {
            bufnr = bufnr,
            node = type_info.name_node,
        } or nil,
    }
end

---@param bufnr number: buffer number
---@param type_name string: type name to check
---@return boolean: true if type is used by multiple components
function M.is_type_shared(bufnr, type_name)
    local lang_map = {
        typescript = "typescript",
        typescriptreact = "tsx",
    }

    local ft = vim.bo[bufnr].filetype
    local lang = lang_map[ft]

    if not lang or not ts.has_parser(bufnr, lang) then
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

    -- Find all components using this type
    local query_str = [[
        (variable_declarator
            name: (identifier)
            value: (arrow_function
                parameters: (formal_parameters
                    (required_parameter
                        type: (type_annotation
                            (type_identifier) @type_ref)))))

        (function_declaration
            parameters: (formal_parameters
                (required_parameter
                    type: (type_annotation
                        (type_identifier) @type_ref))))
    ]]

    local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_str)
    if not ok_query then
        return false
    end

    local usage_count = 0

    for _, match, _ in query:iter_matches(root, bufnr) do
        for id, node_or_nodes in pairs(match) do
            local name = query.captures[id]
            if name == "type_ref" then
                local nodes = node_or_nodes
                local node = nodes[1] and type(nodes[1].range) == "function" and nodes[1] or nil
                if node then
                    local ref_name = vim.treesitter.get_node_text(node, bufnr)
                    if ref_name == type_name then
                        usage_count = usage_count + 1
                        if usage_count > 1 then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

---@tag component_props.prepare_secondary_rename()
---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@param new_name string: new name for primary symbol
---@return table|nil: {secondary_old: string, secondary_name: string, references: table[]}
function M.prepare_secondary_rename(bufnr, pos, new_name)
    if not is_typescript_file(bufnr) then
        return nil
    end

    -- Check if renaming component usage in same file
    local usage_info = M.is_component_usage_in_same_file(bufnr, pos)
    if usage_info and usage_info.is_usage then
        local secondary_name = M.calculate_props_type_name(new_name)

        if not usage_info.type_location then
            -- Props type doesn't exist, skip
            return nil
        end

        -- Check if props type is shared
        if usage_info.props_type_name and M.is_type_shared(bufnr, usage_info.props_type_name) then
            vim.notify(
                string.format(
                    "[react.nvim] Props type '%s' is used by multiple components. Skipping auto-rename.",
                    usage_info.props_type_name
                ),
                vim.log.levels.WARN
            )
            return nil
        end

        if secondary_name and utils.check_conflict(bufnr, secondary_name) then
            vim.notify(
                string.format(
                    "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                    secondary_name
                ),
                vim.log.levels.WARN
            )
            return nil
        end

        local references = usage_info.props_type_name
                and utils.find_references(bufnr, usage_info.props_type_name)
            or {}

        if #references == 0 then
            return nil
        end

        return {
            secondary_old = usage_info.props_type_name,
            secondary_name = secondary_name,
            references = references,
        }
    end

    -- Check if renaming component
    local component_info = M.is_component_name(bufnr, pos)
    if component_info and component_info.is_component then
        local secondary_name = M.calculate_props_type_name(new_name)

        if not component_info.type_location then
            -- Props type doesn't exist, skip
            return nil
        end

        -- Check if props type is shared
        if
            component_info.props_type_name
            and M.is_type_shared(bufnr, component_info.props_type_name)
        then
            vim.notify(
                string.format(
                    "[react.nvim] Props type '%s' is used by multiple components. Skipping auto-rename.",
                    component_info.props_type_name
                ),
                vim.log.levels.WARN
            )
            return nil
        end

        if secondary_name and utils.check_conflict(bufnr, secondary_name) then
            vim.notify(
                string.format(
                    "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                    secondary_name
                ),
                vim.log.levels.WARN
            )
            return nil
        end

        local references = component_info.props_type_name
                and utils.find_references(bufnr, component_info.props_type_name)
            or {}

        if #references == 0 then
            return nil
        end

        return {
            secondary_old = component_info.props_type_name,
            secondary_name = secondary_name,
            references = references,
        }
    end

    -- Check if renaming props type
    local props_type_info = M.is_props_type_name(bufnr, pos)
    if props_type_info and props_type_info.is_props_type then
        -- Extract component name from new props type name
        local new_component_name = M.calculate_component_name(new_name)
        if not new_component_name then
            -- New name doesn't match pattern, skip
            return nil
        end

        if not props_type_info.component_location then
            -- Component doesn't exist, skip
            return nil
        end

        -- Check if props type is shared
        if
            props_type_info.props_type_name
            and M.is_type_shared(bufnr, props_type_info.props_type_name)
        then
            vim.notify(
                string.format(
                    "[react.nvim] Props type '%s' is used by multiple components. Skipping auto-rename.",
                    props_type_info.props_type_name
                ),
                vim.log.levels.WARN
            )
            return nil
        end

        if new_component_name and utils.check_conflict(bufnr, new_component_name) then
            vim.notify(
                string.format(
                    "[react.nvim] Conflict: %s already exists. Skipping auto-rename.",
                    new_component_name
                ),
                vim.log.levels.WARN
            )
            return nil
        end

        local references = props_type_info.component_name
                and utils.find_references(bufnr, props_type_info.component_name)
            or {}

        if #references == 0 then
            return nil
        end

        return {
            secondary_old = props_type_info.component_name,
            secondary_name = new_component_name,
            references = references,
        }
    end

    return nil
end

---@tag component_props.prepare_secondary_from_edit()
---@param bufnr number: buffer number
---@param pos table: cursor position {row, col}
---@param workspace_edit table: workspace edit from LSP
---@return table|nil: {secondary_old: string, secondary_name: string, references: table[]}
function M.prepare_secondary_from_edit(bufnr, pos, workspace_edit)
    if not is_typescript_file(bufnr) then
        return nil
    end

    local new_name = utils.extract_new_name_from_edit(workspace_edit)
    if not new_name then
        return nil
    end

    return M.prepare_secondary_rename(bufnr, pos, new_name)
end

return M
