local M = {}

-- Helper to detect if node is arrow_function, function_declaration, or function_expression
local function is_function_node(node_type)
    return node_type == "arrow_function"
        or node_type == "function_declaration"
        or node_type == "function_expression"
end

-- Helper to check PascalCase
local function is_pascal_case(name)
    return name ~= nil and name:match("^[A-Z]") ~= nil
end

-- Extract component name from variable declaration
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

-- Get function name
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

-- Check if function returns JSX
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

-- Check if function is a React component
local function is_react_component(bufnr, function_node)
    -- Check JSX return (primary signal)
    if has_jsx_return(bufnr, function_node) then
        return true
    end

    -- Check PascalCase naming convention
    local name = get_function_name(bufnr, function_node)

    return is_pascal_case(name)
end

-- Check if function is already wrapped in useCallback
local function is_wrapped_in_use_callback(bufnr, function_node)
    -- Check if parent is call_expression with useCallback
    -- For arrow functions assigned to variables: const x = useCallback(() => {}, [])
    -- Need to check if parent of parent is call_expression

    -- Check direct parent first
    local parent = function_node:parent()

    if parent and parent:type() == "call_expression" then
        local callee = parent:named_child(0)

        if callee and callee:type() == "identifier" then
            local callee_text = vim.treesitter.get_node_text(callee, bufnr)

            if callee_text == "useCallback" then
                return true
            end
        end
    end

    -- For variable declarators, check if the value is useCallback call
    -- const x = useCallback(() => {}, [])
    -- function_node parent is call_expression, which is value of variable_declarator
    if parent and parent:type() == "arguments" then
        local call_expr = parent:parent()

        if call_expr and call_expr:type() == "call_expression" then
            local callee = call_expr:named_child(0)

            if callee and callee:type() == "identifier" then
                local callee_text = vim.treesitter.get_node_text(callee, bufnr)

                if callee_text == "useCallback" then
                    return true
                end
            end
        end
    end

    return false
end

-- Check if identifier is a React component or hook
local function is_react_component_or_hook(bufnr, function_node)
    -- Check if React component
    if is_react_component(bufnr, function_node) then
        return true
    end

    -- Check for hook pattern (use* prefix)
    local name = get_function_name(bufnr, function_node)

    return name and name:match("^use[A-Z]") ~= nil
end

-- Check if function is inline in JSX attribute
local function is_inline_jsx_function(function_node)
    local parent = function_node:parent()

    if not parent or parent:type() ~= "jsx_expression" then
        return false
    end

    local jsx_attr = parent:parent()

    local is_inline = jsx_attr and jsx_attr:type() == "jsx_attribute"
    return is_inline
end

-- Find enclosing component/hook and inner function at cursor
local function find_function_context(bufnr, row, col)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    local functions = {}
    local current = node

    -- Collect all enclosing functions
    while current do
        local type = current:type()

        if is_function_node(type) then
            table.insert(functions, current)
        end

        current = current:parent()
    end

    -- If we found enough functions, proceed normally
    if #functions >= 2 then
        -- Find the outermost component/hook first
        local component_node = nil
        local component_index = nil

        for i = #functions, 1, -1 do
            if is_react_component_or_hook(bufnr, functions[i]) then
                component_node = functions[i]
                component_index = i
                break
            end
        end

        if not component_node then
            return nil
        end

        -- The function to wrap should be the outermost non-component function
        -- i.e., the function directly inside the component (at component_index - 1)
        local inner_function
        if component_index > 1 then
            inner_function = functions[component_index - 1]
        else
            return nil
        end

        -- Check if already wrapped
        if is_wrapped_in_use_callback(bufnr, inner_function) then
            return nil
        end

        -- Check if this is an inline JSX function
        local is_inline = is_inline_jsx_function(inner_function)

        return {
            function_node = inner_function,
            component_node = component_node,
            is_inline = is_inline,
        }
    end

    -- Fallback: Check if cursor is on function name identifier
    if node:type() == "identifier" then
        local parent = node:parent()
        local function_node = nil

        -- Case 1: const handleClick = () => {}
        if parent and parent:type() == "variable_declarator" then
            local value_node = parent:named_child(1)
            if value_node and is_function_node(value_node:type()) then
                function_node = value_node
            end
        -- Case 2: function handleClick() {}
        elseif parent and is_function_node(parent:type()) then
            function_node = parent
        end

        if function_node then
            -- Find component context by traversing up
            local component_node = nil
            local comp_current = function_node:parent()

            while comp_current do
                if
                    is_function_node(comp_current:type())
                    and is_react_component_or_hook(bufnr, comp_current)
                then
                    component_node = comp_current
                    break
                end
                comp_current = comp_current:parent()
            end

            if component_node and not is_wrapped_in_use_callback(bufnr, function_node) then
                local is_inline = is_inline_jsx_function(function_node)
                return {
                    function_node = function_node,
                    component_node = component_node,
                    is_inline = is_inline,
                }
            end
        end
    end

    return nil
end

-- Find function from JSX event handler
local function find_function_from_jsx_handler(bufnr, row, col)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node or node:type() ~= "identifier" then
        return nil
    end

    -- Check if inside jsx_expression inside jsx_attribute
    local jsx_expr = node:parent()

    if not jsx_expr or jsx_expr:type() ~= "jsx_expression" then
        return nil
    end

    local jsx_attr = jsx_expr:parent()

    if not jsx_attr or jsx_attr:type() ~= "jsx_attribute" then
        return nil
    end

    -- Check if attribute is event handler (on[A-Z])
    local attr_name_node = jsx_attr:named_child(0)

    if not attr_name_node or attr_name_node:type() ~= "property_identifier" then
        return nil
    end

    local attr_name = vim.treesitter.get_node_text(attr_name_node, bufnr)

    if not attr_name:match("^on[A-Z]") then
        return nil
    end

    -- Find function declaration using identifier name
    local handler_name = vim.treesitter.get_node_text(node, bufnr)

    -- Find variable declaration in scope
    local current = node

    while current do
        local type = current:type()

        if
            type == "statement_block"
            or type == "program"
            or type == "arrow_function"
            or type == "function_declaration"
            or type == "function_expression"
        then
            -- Search for variable declarations in this scope
            for child in current:iter_children() do
                local child_type = child:type()

                if child_type == "lexical_declaration" or child_type == "variable_declaration" then
                    for declarator in child:iter_children() do
                        if declarator:type() == "variable_declarator" then
                            local name_node = declarator:named_child(0)

                            if name_node and name_node:type() == "identifier" then
                                local name = vim.treesitter.get_node_text(name_node, bufnr)

                                if name == handler_name then
                                    -- Get function value
                                    local value_node = declarator:named_child(1)

                                    if value_node and is_function_node(value_node:type()) then
                                        -- Find component context
                                        local component_node = nil
                                        local comp_current = current

                                        while comp_current do
                                            if
                                                is_function_node(comp_current:type())
                                                and is_react_component_or_hook(bufnr, comp_current)
                                            then
                                                component_node = comp_current
                                                break
                                            end

                                            comp_current = comp_current:parent()
                                        end

                                        if not component_node then
                                            return nil
                                        end

                                        if is_wrapped_in_use_callback(bufnr, value_node) then
                                            return nil
                                        end

                                        return {
                                            function_node = value_node,
                                            component_node = component_node,
                                            declarator_node = declarator,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        current = current:parent()
    end

    return nil
end

-- Generate handler name from JSX context
local function generate_handler_name(bufnr, jsx_attribute_node)
    -- Extract event name from attribute (onClick → Click)
    local attr_name_node = jsx_attribute_node:named_child(0)
    local attr_name = vim.treesitter.get_node_text(attr_name_node, bufnr)
    local event_name = attr_name:gsub("^on", "")

    -- Get JSX element name (Button, div, etc.)
    local jsx_element = jsx_attribute_node:parent()
    local element_name = nil

    for child in jsx_element:iter_children() do
        if child:type() == "identifier" or child:type() == "jsx_identifier" then
            element_name = vim.treesitter.get_node_text(child, bufnr)
            break
        end
    end

    -- Capitalize element name
    if element_name then
        element_name = element_name:sub(1, 1):upper() .. element_name:sub(2)
    else
        element_name = "Element"
    end

    local handler_name = string.format("handle%s%s", element_name, event_name)
    return handler_name
end

-- Find return statement in component
local function find_return_statement(component_node)
    local body = nil

    for child in component_node:iter_children() do
        if child:type() == "statement_block" then
            body = child
            break
        end
    end

    if not body then
        return nil
    end

    -- Find last return statement
    local return_node = nil

    for child in body:iter_children() do
        if child:type() == "return_statement" then
            return_node = child
        end
    end

    return return_node
end

-- Collect useState setters in component scope
local function collect_use_state_setters(bufnr, component_node)
    local setters = {}

    -- Query for useState patterns
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "tsx",
        typescriptreact = "tsx",
    }

    local lang = lang_map[ft]

    if not lang then
        return setters
    end

    local query_str = [[
        (variable_declarator
          (array_pattern
            (identifier) @state
            (identifier) @setter)
          (call_expression
            (identifier) @fn (#eq? @fn "useState")))
    ]]

    local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)

    if not ok then
        return setters
    end

    -- Search in component scope
    for _, match, _ in query:iter_matches(component_node, bufnr) do
        for id, nodes in pairs(match) do
            local name = query.captures[id]

            if name == "setter" and nodes and #nodes > 0 then
                local setter_node = nodes[1]

                if setter_node and type(setter_node.range) == "function" then
                    local setter_name = vim.treesitter.get_node_text(setter_node, bufnr)
                    setters[setter_name] = true
                end
            end
        end
    end

    return setters
end

-- JS globals to exclude from deps
local JS_GLOBALS = {
    -- Standard JS
    console = true,
    Math = true,
    Object = true,
    Array = true,
    String = true,
    Number = true,
    Boolean = true,
    Date = true,
    RegExp = true,
    Error = true,
    JSON = true,
    Promise = true,
    Set = true,
    Map = true,
    WeakMap = true,
    WeakSet = true,
    Symbol = true,
    BigInt = true,
    -- DOM
    document = true,
    window = true,
    navigator = true,
    location = true,
    history = true,
    localStorage = true,
    sessionStorage = true,
    -- Common globals
    setTimeout = true,
    clearTimeout = true,
    setInterval = true,
    clearInterval = true,
    requestAnimationFrame = true,
    cancelAnimationFrame = true,
    fetch = true,
    alert = true,
    confirm = true,
    prompt = true,
}

-- Extract dependencies from function body
local function extract_dependencies(bufnr, function_node, component_node)
    -- Collect parameters from function
    local params = {}
    local params_node = nil

    for child in function_node:iter_children() do
        if child:type() == "formal_parameters" then
            params_node = child
            break
        end
    end

    if params_node then
        for param in params_node:iter_children() do
            if param:type() == "identifier" then
                local param_name = vim.treesitter.get_node_text(param, bufnr)
                params[param_name] = true
            elseif param:type() == "required_parameter" then
                local pattern_node = param:field("pattern")[1]

                if pattern_node and pattern_node:type() == "identifier" then
                    local param_name = vim.treesitter.get_node_text(pattern_node, bufnr)
                    params[param_name] = true
                end
            end
        end
    end

    -- Collect local declarations in function body
    local locals = {}
    local body_node = nil

    for child in function_node:iter_children() do
        if child:type() == "statement_block" then
            body_node = child
            break
        end
    end

    -- For arrow functions, body might be an expression
    if not body_node then
        -- Check if last child is not statement_block (expression body)
        local last_child = function_node:named_child(function_node:named_child_count() - 1)

        if last_child then
            body_node = last_child
        end
    end

    if body_node then
        -- Collect local var/let/const declarations
        local function collect_locals(node)
            for child in node:iter_children() do
                if
                    child:type() == "lexical_declaration"
                    or child:type() == "variable_declaration"
                then
                    for declarator in child:iter_children() do
                        if declarator:type() == "variable_declarator" then
                            local name_node = declarator:named_child(0)

                            if name_node and name_node:type() == "identifier" then
                                local name = vim.treesitter.get_node_text(name_node, bufnr)
                                locals[name] = true
                            end
                        end
                    end
                end

                -- Recursively collect from nested blocks
                if child:type() == "statement_block" then
                    collect_locals(child)
                end
            end
        end

        collect_locals(body_node)
    end

    -- Collect useState setters
    local setters = collect_use_state_setters(bufnr, component_node)

    -- Collect all identifiers in function body
    local identifiers = {}

    local function collect_identifiers(node)
        -- For member expressions, only include root and skip children
        if node:type() == "member_expression" then
            local object_node = node:named_child(0)

            if object_node and object_node:type() == "identifier" then
                local name = vim.treesitter.get_node_text(object_node, bufnr)

                if
                    not params[name]
                    and not locals[name]
                    and not JS_GLOBALS[name]
                    and not setters[name]
                then
                    identifiers[name] = true
                end
            end

            -- Don't traverse children of member_expression
            return
        end

        if node:type() == "identifier" then
            local name = vim.treesitter.get_node_text(node, bufnr)

            -- Skip params, locals, globals, and setters
            if
                not params[name]
                and not locals[name]
                and not JS_GLOBALS[name]
                and not setters[name]
            then
                identifiers[name] = true
            end
        end

        for child in node:iter_children() do
            collect_identifiers(child)
        end
    end

    if body_node then
        collect_identifiers(body_node)
    end

    -- Convert to sorted array
    local deps = {}

    for name, _ in pairs(identifiers) do
        table.insert(deps, name)
    end

    table.sort(deps)

    return deps
end

-- Check if useCallback is already imported
local function has_use_callback_import(bufnr)
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

    -- Manually search for useCallback import
    local function check_import(node)
        if node:type() == "import_statement" then
            -- Check source is 'react'
            local source_node = nil

            for child in node:iter_children() do
                if child:type() == "string" then
                    source_node = child
                end
            end

            if source_node then
                local source_text = vim.treesitter.get_node_text(source_node, bufnr)

                if source_text:match("react") then
                    -- Check for useCallback in named imports
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

                                                if name == "useCallback" then
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

-- Get React import info
local function get_react_import_info(bufnr)
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

    -- Manually search for React import
    local function find_react_import(node)
        if node:type() == "import_statement" then
            -- Check source is 'react'
            local source_node = nil

            for child in node:iter_children() do
                if child:type() == "string" then
                    source_node = child
                end
            end

            if source_node then
                local source_text = vim.treesitter.get_node_text(source_node, bufnr)

                if source_text:match("react") then
                    -- Found React import, get import_clause
                    for child in node:iter_children() do
                        if child:type() == "import_clause" then
                            -- Check for named imports
                            for ic_child in child:iter_children() do
                                if ic_child:type() == "named_imports" then
                                    return {
                                        type = "named",
                                        node = ic_child,
                                    }
                                end
                            end

                            -- Check for default import
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

-- Create import edit
local function create_import_edit(bufnr)
    -- Check if already imported
    if has_use_callback_import(bufnr) then
        return nil
    end

    local import_info = get_react_import_info(bufnr)

    if import_info then
        if import_info.type == "named" then
            -- Add to existing named imports alphabetically
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

            -- Add useCallback and sort
            table.insert(imports, { name = "useCallback", node = nil })

            table.sort(imports, function(a, b)
                return a.name < b.name
            end)

            -- Find position to insert
            local insert_pos = nil

            for i, imp in ipairs(imports) do
                if imp.name == "useCallback" then
                    if i == 1 then
                        -- Insert at beginning
                        local first_import = imports[2]

                        if first_import and first_import.node then
                            local sr, sc = first_import.node:range()
                            insert_pos = { row = sr, col = sc, is_beginning = true }
                        end
                    elseif i == #imports then
                        -- Insert at end
                        local last_import = imports[#imports - 1]

                        if last_import and last_import.node then
                            local _, _, er, ec = last_import.node:range()
                            insert_pos = { row = er, col = ec, is_beginning = false }
                        end
                    else
                        -- Insert in middle
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
                -- Determine if we're inserting at beginning, middle, or end
                local text
                if insert_pos.is_beginning then
                    text = "useCallback, "
                else
                    text = ", useCallback"
                end

                return {
                    row = insert_pos.row,
                    col = insert_pos.col,
                    text = text,
                }
            end
        elseif import_info.type == "default" then
            -- Add named imports after default import
            -- import React from 'react' -> import React, { useCallback } from 'react'
            local import_clause = import_info.node
            local _, _, er, ec = import_clause:range()

            return {
                row = er,
                col = ec,
                text = ", { useCallback }",
            }
        end
    else
        -- No React import, create new one at top
        -- Check for "use client" directive
        local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
        local insert_row = 0

        if first_line and first_line:match("^[\"']use client[\"']") then
            insert_row = 1
        end

        return {
            row = insert_row,
            col = 0,
            text = "import { useCallback } from 'react';\n",
        }
    end

    return nil
end

-- Extract function name from function_declaration
local function get_function_declaration_name(bufnr, function_node)
    for child in function_node:iter_children() do
        if child:type() == "identifier" then
            return vim.treesitter.get_node_text(child, bufnr)
        end
    end
    return nil
end

-- Extract function body for conversion
local function extract_function_body(bufnr, function_node)
    for child in function_node:iter_children() do
        if child:type() == "statement_block" then
            return vim.treesitter.get_node_text(child, bufnr)
        end
    end
    return nil
end

-- Extract formal_parameters text
local function extract_function_params(bufnr, function_node)
    for child in function_node:iter_children() do
        if child:type() == "formal_parameters" then
            return vim.treesitter.get_node_text(child, bufnr)
        end
    end
    return "()"
end

-- Create wrapper edit
local function create_wrapper_edit(bufnr, context, deps)
    local function_node = context.function_node
    local sr, sc, er, ec = function_node:range()

    -- Build deps array string
    local deps_str = "[" .. table.concat(deps, ", ") .. "]"

    local wrapper_text

    -- Special handling for function_declaration
    if function_node:type() == "function_declaration" then
        local func_name = get_function_declaration_name(bufnr, function_node)
        local params = extract_function_params(bufnr, function_node)
        local body = extract_function_body(bufnr, function_node)

        if func_name and body then
            -- Convert to: const funcName = useCallback((params) => body, [deps]);
            local arrow_fn = string.format("%s => %s", params, body)
            wrapper_text =
                string.format("const %s = useCallback(%s, %s);", func_name, arrow_fn, deps_str)
        else
            -- Fallback: keep as function declaration (shouldn't happen)
            local function_text = vim.treesitter.get_node_text(function_node, bufnr)
            wrapper_text = string.format("useCallback(%s, %s)", function_text, deps_str)
        end
    else
        -- For arrow_function and function_expression, wrap in place
        local function_text = vim.treesitter.get_node_text(function_node, bufnr)
        wrapper_text = string.format("useCallback(%s, %s)", function_text, deps_str)
    end

    return {
        row_start = sr,
        col_start = sc,
        row_end = er,
        col_end = ec,
        text = wrapper_text,
    }
end

-- Apply edits
local function apply_edits(bufnr, edits)
    -- Sort edits bottom-to-top, right-to-left
    table.sort(edits, function(a, b)
        local a_row = a.row_start or a.row
        local b_row = b.row_start or b.row

        if a_row == b_row then
            local a_col = a.col_start or a.col
            local b_col = b.col_start or b.col

            return a_col > b_col
        end

        return a_row > b_row
    end)

    for _, edit in ipairs(edits) do
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
end

function M.get_source(null_ls)
    return {
        name = "react-wrap-use-callback",
        filetypes = { "javascriptreact", "typescriptreact", "javascript", "typescript" },
        method = null_ls.methods.CODE_ACTION,
        generator = {
            fn = function(params)
                local bufnr = params.bufnr
                local row = params.row - 1
                local col = params.col

                -- Try inner function detection
                local context = find_function_context(bufnr, row, col)

                -- Try JSX handler detection if inner function not found
                if not context then
                    context = find_function_from_jsx_handler(bufnr, row, col)
                end

                -- Try inline JSX function detection
                if not context then
                    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

                    -- Find enclosing function
                    local current = node
                    local inline_function = nil

                    while current do
                        if is_function_node(current:type()) then
                            if is_inline_jsx_function(current) then
                                inline_function = current
                                break
                            end
                        end

                        current = current:parent()
                    end

                    if inline_function then
                        -- Find component context
                        local component_node = nil
                        local comp_current = inline_function:parent()

                        while comp_current do
                            if
                                is_function_node(comp_current:type())
                                and is_react_component_or_hook(bufnr, comp_current)
                            then
                                component_node = comp_current
                                break
                            end

                            comp_current = comp_current:parent()
                        end

                        if component_node then
                            -- Check if already wrapped
                            if not is_wrapped_in_use_callback(bufnr, inline_function) then
                                context = {
                                    function_node = inline_function,
                                    component_node = component_node,
                                    is_inline = true,
                                }
                            end
                        end
                    end
                end

                if not context then
                    return nil
                end

                -- Extract dependencies
                local deps =
                    extract_dependencies(bufnr, context.function_node, context.component_node)

                -- Create edits
                local edits = {}

                if context.is_inline then
                    -- INLINE CASE: Extract to variable
                    local jsx_expr = context.function_node:parent()
                    local jsx_attr = jsx_expr:parent()

                    -- Generate variable name
                    local var_name = generate_handler_name(bufnr, jsx_attr)

                    -- Find insertion point (before return)
                    local return_node = find_return_statement(context.component_node)

                    if not return_node then
                        return nil
                    end

                    local ret_row, ret_col = return_node:range()

                    -- Get function text
                    local func_text = vim.treesitter.get_node_text(context.function_node, bufnr)

                    -- Create variable declaration with useCallback
                    local deps_str = "[" .. table.concat(deps, ", ") .. "]"
                    local declaration = string.format(
                        "  const %s = useCallback(%s, %s);\n\n  ",
                        var_name,
                        func_text,
                        deps_str
                    )

                    -- Edit 1: Insert variable declaration before return
                    table.insert(edits, {
                        row = ret_row,
                        col = ret_col,
                        text = declaration,
                    })

                    -- Edit 2: Replace inline function with variable reference
                    local fsr, fsc, fer, fec = context.function_node:range()
                    table.insert(edits, {
                        row_start = fsr,
                        col_start = fsc,
                        row_end = fer,
                        col_end = fec,
                        text = var_name,
                    })

                    -- Import edit
                    local import_edit = create_import_edit(bufnr)
                    if import_edit then
                        table.insert(edits, import_edit)
                    end
                else
                    -- NORMAL CASE: Wrap in place
                    -- Import edit
                    local import_edit = create_import_edit(bufnr)

                    if import_edit then
                        table.insert(edits, import_edit)
                    end

                    -- Wrapper edit
                    local wrapper_edit = create_wrapper_edit(bufnr, context, deps)
                    table.insert(edits, wrapper_edit)
                end

                return {
                    {
                        title = context.is_inline and "Extract to useCallback handler"
                            or "Wrap with useCallback",
                        action = function()
                            apply_edits(bufnr, edits)
                        end,
                    },
                }
            end,
        },
    }
end

-- Export for testing
M.find_function_context = find_function_context
M.find_function_from_jsx_handler = find_function_from_jsx_handler
M.is_inline_jsx_function = is_inline_jsx_function
M.generate_handler_name = generate_handler_name
M.find_return_statement = find_return_statement
M.extract_dependencies = extract_dependencies
M.collect_use_state_setters = collect_use_state_setters
M.has_use_callback_import = has_use_callback_import
M.create_import_edit = create_import_edit
M.create_wrapper_edit = create_wrapper_edit
M.apply_edits = apply_edits

return M
