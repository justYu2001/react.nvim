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

-- Helper to check PascalCase
local function is_pascal_case(name)
    return name ~= nil and name:match("^[A-Z]") ~= nil
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
    local current = function_node:parent()

    while current do
        local node_type = current:type()

        if node_type == "lexical_declaration" or node_type == "variable_declaration" then
            for child in current:iter_children() do
                if child:type() == "variable_declarator" then
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

-- Check if function returns JSX
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

-- Check if function is a React component
local function is_react_component(bufnr, function_node)
    -- Check JSX return (primary signal)
    if has_jsx_return(function_node) then
        return true
    end

    -- Check PascalCase naming convention
    local name = get_function_name(bufnr, function_node)

    return is_pascal_case(name)
end

-- Detect event handler context (empty or undefined)
local function detect_event_handler_context(params)
    local bufnr = params.bufnr
    local row = params.row - 1
    local col = params.col

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    -- Case A: Empty handler onClick={}
    local current = node

    while current do
        if current:type() == "jsx_attribute" then
            -- Get attribute name
            local attr_name_node = nil
            for child in current:iter_children() do
                if child:type() == "property_identifier" then
                    attr_name_node = child
                    break
                end
            end

            if attr_name_node then
                local attr_name = vim.treesitter.get_node_text(attr_name_node, bufnr)

                if is_event_handler_prop(attr_name) then
                    -- Check if jsx_expression is empty
                    local jsx_expr = nil
                    for child in current:iter_children() do
                        if child:type() == "jsx_expression" then
                            jsx_expr = child
                            break
                        end
                    end

                    if jsx_expr then
                        local has_identifier = false
                        for child in jsx_expr:iter_children() do
                            if child:type() == "identifier" then
                                has_identifier = true
                                break
                            end
                        end

                        if not has_identifier then
                            -- Empty handler
                            local jsx_element = current:parent()
                            return {
                                type = "empty",
                                attr_node = current,
                                attr_name_node = attr_name_node,
                                jsx_element_node = jsx_element,
                            }
                        end
                    end
                end
            end
        end

        current = current:parent()
    end

    -- Case B: Undefined handler onClick={handleClick}
    if node:type() == "identifier" then
        -- Check if inside jsx_expression → jsx_attribute
        local jsx_expr = node:parent()

        if jsx_expr and jsx_expr:type() == "jsx_expression" then
            local jsx_attr = jsx_expr:parent()

            if jsx_attr and jsx_attr:type() == "jsx_attribute" then
                local attr_name_node = nil
                for child in jsx_attr:iter_children() do
                    if child:type() == "property_identifier" then
                        attr_name_node = child
                        break
                    end
                end

                if attr_name_node then
                    local attr_name = vim.treesitter.get_node_text(attr_name_node, bufnr)

                    if is_event_handler_prop(attr_name) then
                        -- Check if there's a diagnostic for undefined var
                        local diagnostics = vim.diagnostic.get(bufnr, { lnum = row })

                        for _, diag in ipairs(diagnostics) do
                            local msg = diag.message

                            local var_name = msg:match("Cannot find name '([%w_]+)'")
                                or msg:match("'([%w_]+)' is not defined")

                            local is_matched_error = msg
                                == "I can't find the variable you're trying to access."

                            if var_name or is_matched_error then
                                local handler_name = vim.treesitter.get_node_text(node, bufnr)

                                if is_matched_error or handler_name == var_name then
                                    local jsx_element = jsx_attr:parent()
                                    return {
                                        type = "undefined",
                                        attr_node = jsx_attr,
                                        attr_name_node = attr_name_node,
                                        jsx_element_node = jsx_element,
                                        handler_name = handler_name,
                                    }
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

-- Find component scope
local function find_component_scope(bufnr, row, col)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    local current = node

    while current do
        local type = current:type()

        if
            type == "function_declaration"
            or type == "arrow_function"
            or type == "function"
            or type == "function_expression"
        then
            if is_react_component(bufnr, current) then
                return current
            end
        end

        current = current:parent()
    end

    return nil
end

-- Infer handler type from LSP hover
local function infer_handler_type_from_lsp(bufnr, attr_name_node, element_name)
    if not attr_name_node then
        return nil
    end

    local sr, sc = attr_name_node:range()

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = sr, character = sc },
    }

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", params, 1000)

    if not result or vim.tbl_isempty(result) then
        return nil
    end

    for _, res in pairs(result) do
        if res.result and res.result.contents then
            local contents = res.result.contents
            local hover_text = ""

            if type(contents) == "string" then
                hover_text = contents
            elseif type(contents) == "table" then
                if contents.value then
                    hover_text = contents.value
                elseif contents[1] and contents[1].value then
                    hover_text = contents[1].value
                end
            end

            -- Remove markdown code fences if present
            hover_text = hover_text:gsub("```[%w]*\n?", "")

            -- Try multiple patterns to extract the function type
            -- Pattern 1: "onClick?: (event: Type) => void"
            local type_match = hover_text:match("%w+%??: ([^=\n]+)")

            if not type_match then
                -- Pattern 2: "(property) onClick: (event: Type) => void"
                type_match = hover_text:match("%(property%)%s+%w+: ([^=\n]+)")
            end

            if not type_match then
                -- Pattern 3: Simple ": (event: Type) => void"
                type_match = hover_text:match(": ([^=\n]+)")
            end

            if type_match then
                -- Clean up the match
                type_match = type_match:gsub("^%s+", ""):gsub("%s+$", "")

                -- Remove " | undefined" if present
                type_match = type_match:gsub("%s*|%s*undefined", "")

                -- Expand React event handler type aliases
                -- React.MouseEventHandler<T> -> (event: MouseEvent<T>) => void
                local expanded = type_match:gsub(
                    "React%.(%w+)EventHandler(<[^>]+>)",
                    function(event_type, generic)
                        return string.format("(event: %sEvent%s) => void", event_type, generic)
                    end
                )

                -- Normalize parameter name to "event" only for HTML elements
                -- For custom components (PascalCase), preserve original parameter name
                local normalized = expanded
                if not is_pascal_case(element_name) then
                    -- HTML element: normalize to "event"
                    normalized = expanded:gsub("%((%w+):", "(event:")
                end

                return normalized
            end
        end
    end

    return nil
end

-- Generate unique handler name
local function generate_handler_name(element_name, event_name, bufnr, component_node)
    -- Format: handle${ElementName}${Event}
    local capitalized_element = element_name:sub(1, 1):upper() .. element_name:sub(2)
    local base_name = string.format("handle%s%s", capitalized_element, event_name)

    -- Check for conflicts
    local existing_names = {}

    local function collect_names(node)
        for child in node:iter_children() do
            if child:type() == "lexical_declaration" or child:type() == "variable_declaration" then
                for declarator in child:iter_children() do
                    if declarator:type() == "variable_declarator" then
                        local name_node = declarator:named_child(0)

                        if name_node and name_node:type() == "identifier" then
                            local name = vim.treesitter.get_node_text(name_node, bufnr)
                            existing_names[name] = true
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

    -- Find unique name with suffix
    local handler_name = base_name
    local counter = 2

    while existing_names[handler_name] do
        handler_name = base_name .. counter
        counter = counter + 1
    end

    return handler_name
end

-- Generate function code
local function generate_function_code(
    handler_name,
    handler_type,
    with_params,
    indent,
    is_typescript
)
    local params = ""

    if with_params then
        if handler_type then
            -- Extract parameter name and type from handler_type
            -- handler_type is like "(event: MouseEvent<HTMLButtonElement>) => void"
            -- or "(click: CustomEvent) => void" for custom components
            -- or "(click) => void" for JavaScript
            local param_name, param_type = handler_type:match("%((%w+):%s*(.-)%s*%)%s*=>")

            if not param_name or not param_type then
                -- Try simpler pattern without fat arrow
                param_name, param_type = handler_type:match("%((%w+):%s*(.-)%s*%)")
            end

            if not param_name then
                -- Try JavaScript pattern without type annotation: (paramName) => void
                param_name = handler_type:match("%((%w+)%)%s*=>")
                if not param_name then
                    -- Try even simpler pattern without fat arrow
                    param_name = handler_type:match("%((%w+)%)")
                end
            end

            if param_name and param_type and is_typescript then
                params = string.format("%s: %s", param_name, param_type)
            elseif param_name then
                -- Just use parameter name without type
                params = param_name
            else
                -- Fallback to "event" if parsing fails
                params = "event"
            end
        else
            -- No type info, fallback to event parameter
            params = "event"
        end
    end

    -- Generate function with proper indentation for each line
    local body_indent = indent .. "  "
    local function_code = string.format(
        "%sconst %s = (%s) => {\n%s\n%s};",
        indent,
        handler_name,
        params,
        body_indent,
        indent
    )

    return function_code
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
local function has_type_import(bufnr, event_type)
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
local function create_type_import_edit(bufnr, event_type)
    if not event_type then
        return nil
    end

    if has_type_import(bufnr, event_type) then
        return nil
    end

    local import_info = get_react_import_info(bufnr)

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

-- Apply handler and trigger rename
local function apply_handler_and_rename(
    params,
    handler_name,
    function_code,
    insert_pos,
    import_edit
)
    local bufnr = params.bufnr

    -- Calculate row adjustment from import edit
    local row_offset = 0

    -- Apply import edit first if needed
    if import_edit then
        local import_lines = vim.split(import_edit.text, "\n")
        vim.api.nvim_buf_set_text(
            bufnr,
            import_edit.row,
            import_edit.col,
            import_edit.row,
            import_edit.col,
            import_lines
        )

        -- Adjust insert position if import was added before it
        if import_edit.row <= insert_pos.row then
            row_offset = #import_lines - 1
        end
    end

    local lines_to_insert = vim.split(function_code .. "\n\n", "\n")

    -- Insert function at beginning of line (col 0) to preserve indent of following content
    -- Adjust row by offset from import edit
    local adjusted_row = insert_pos.row + row_offset
    vim.api.nvim_buf_set_text(bufnr, adjusted_row, 0, adjusted_row, 0, lines_to_insert)

    vim.schedule(function()
        -- Get the actual line content after insertion
        local inserted_line =
            vim.api.nvim_buf_get_lines(bufnr, adjusted_row, adjusted_row + 1, false)[1]

        -- Find the position of handler_name in the line
        local name_start = inserted_line:find(handler_name, 1, true)

        -- Position cursor on function name for rename
        -- Row is 1-indexed for nvim_win_set_cursor, col is 0-indexed
        local name_row = adjusted_row + 1 -- Convert to 1-indexed
        local name_col = (name_start or 9) - 1 -- Convert to 0-indexed

        vim.api.nvim_win_set_cursor(0, { name_row, name_col })

        -- Set up autocmd to move cursor after rename completes
        local function position_cursor_in_body()
            -- Check if buffer is still valid
            if not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end

            -- Find the statement_block of the newly created function
            local indent = get_line_indent(bufnr, adjusted_row)
            local body_indent = indent .. "  "
            -- adjusted_row is 0-indexed, body is at adjusted_row + 1 (0-indexed)
            -- nvim_win_set_cursor needs 1-indexed row
            local body_row_1indexed = adjusted_row + 1 + 1 -- Convert to 1-indexed
            local body_col = #body_indent

            -- Check if row is within buffer bounds
            local line_count = vim.api.nvim_buf_line_count(bufnr)

            if body_row_1indexed > line_count then
                return
            end

            -- Check if column is valid for that line
            local line = vim.api.nvim_buf_get_lines(
                bufnr,
                body_row_1indexed - 1,
                body_row_1indexed,
                false
            )[1]
            if not line or body_col > #line then
                body_col = line and #line or 0
            end

            pcall(vim.api.nvim_win_set_cursor, 0, { body_row_1indexed, body_col })
            vim.cmd("startinsert!")
        end

        -- Create autocmd to detect when rename completes (user exits insert/command mode)
        local augroup = vim.api.nvim_create_augroup("ReactGenerateHandlerRename", { clear = true })
        vim.api.nvim_create_autocmd("ModeChanged", {
            group = augroup,
            pattern = "*:n",
            once = true,
            callback = function()
                vim.schedule(function()
                    position_cursor_in_body()
                    -- Clean up autocmd group
                    vim.api.nvim_del_augroup_by_id(augroup)
                end)
            end,
        })

        -- Check for inc-rename
        local has_inc_rename, _ = pcall(require, "inc_rename")

        if has_inc_rename then
            pcall(function()
                local keys =
                    vim.api.nvim_replace_termcodes(":IncRename " .. handler_name, true, false, true)
                vim.api.nvim_feedkeys(keys, "n", false)
            end)
        else
            vim.lsp.buf.rename()
        end
    end)
end

function M.get_source(null_ls)
    return {
        name = "react-generate-event-handler",
        filetypes = { "typescriptreact", "javascriptreact", "typescript", "javascript" },
        method = null_ls.methods.CODE_ACTION,
        generator = {
            fn = function(params)
                local context = detect_event_handler_context(params)

                if not context then
                    return nil
                end

                local component_node =
                    find_component_scope(params.bufnr, params.row - 1, params.col)

                if not component_node then
                    return nil
                end

                -- Skip class components
                if component_node:type() == "class_declaration" then
                    return nil
                end

                local handler_name
                local attr_name = vim.treesitter.get_node_text(context.attr_name_node, params.bufnr)
                local event_name = attr_name:gsub("^on", "")

                -- Extract element name
                local element_name = nil
                for child in context.jsx_element_node:iter_children() do
                    if child:type() == "identifier" or child:type() == "jsx_identifier" then
                        element_name = vim.treesitter.get_node_text(child, params.bufnr)
                        break
                    end
                end

                if not element_name then
                    element_name = "Element"
                end

                if context.type == "empty" then
                    -- Generate handler name from element
                    handler_name = generate_handler_name(
                        element_name,
                        event_name,
                        params.bufnr,
                        component_node
                    )
                else
                    -- Use typed name
                    handler_name = context.handler_name
                end

                -- Check if TypeScript
                local filetype = vim.bo[params.bufnr].filetype
                local is_typescript = filetype == "typescriptreact" or filetype == "typescript"

                -- Infer type from LSP
                local handler_type =
                    infer_handler_type_from_lsp(params.bufnr, context.attr_name_node, element_name)

                -- Fallback to generic event type if LSP unavailable
                if not handler_type and is_typescript then
                    -- Use generic event type for TypeScript
                    handler_type = "(event: React.MouseEvent) => void"
                elseif not handler_type then
                    -- JavaScript fallback
                    handler_type = "(event) => void"
                end

                -- Find insertion point
                local return_node = find_return_statement(component_node)
                local insert_row, insert_col

                if return_node then
                    insert_row, insert_col = return_node:range()
                else
                    -- Insert at end of component body
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

                    local _, _, er, _ = body:range()
                    insert_row = er - 1
                    insert_col = 0
                end

                local indent = get_line_indent(params.bufnr, insert_row)

                -- Return single code action that shows parameter menu
                return {
                    {
                        title = "Generate event handler",
                        action = function()
                            -- Show menu for parameter selection
                            vim.ui.select({
                                {
                                    label = "No parameters",
                                    value = "no_params",
                                },
                                {
                                    label = "Add all parameters",
                                    value = "with_params",
                                },
                            }, {
                                prompt = "Select handler signature:",
                                format_item = function(item)
                                    return item.label
                                end,
                            }, function(choice)
                                if not choice then
                                    return
                                end

                                local with_params = choice.value == "with_params"

                                -- Extract event type for import if needed
                                local event_type = nil
                                if with_params and handler_type and is_typescript then
                                    -- Extract parameter type from handler_type
                                    -- e.g., "(event: MouseEvent<HTMLButtonElement>) => void"
                                    local param_type =
                                        handler_type:match("%(event:%s*(.-)%s*%)%s*=>")

                                    if not param_type then
                                        param_type = handler_type:match("%(event:%s*(.-)%s*%)")
                                    end

                                    if param_type then
                                        -- Extract base event type (MouseEvent, ChangeEvent, etc.)
                                        event_type = param_type:match("^(%w+Event)")
                                    end
                                end

                                local import_edit = event_type
                                    and create_type_import_edit(params.bufnr, event_type)

                                -- Update JSX attribute FIRST if empty (before buffer changes)
                                if context.type == "empty" then
                                    local jsx_expr = nil
                                    for child in context.attr_node:iter_children() do
                                        if child:type() == "jsx_expression" then
                                            jsx_expr = child
                                            break
                                        end
                                    end

                                    if jsx_expr then
                                        local sr, sc, er, ec = jsx_expr:range()
                                        vim.api.nvim_buf_set_text(
                                            params.bufnr,
                                            sr,
                                            sc,
                                            er,
                                            ec,
                                            { "{" .. handler_name .. "}" }
                                        )
                                    end
                                end

                                local function_code = generate_function_code(
                                    handler_name,
                                    handler_type,
                                    with_params,
                                    indent,
                                    is_typescript
                                )

                                apply_handler_and_rename(params, handler_name, function_code, {
                                    row = insert_row,
                                    col = insert_col,
                                }, import_edit)
                            end)
                        end,
                    },
                }
            end,
        },
    }
end

-- Exported for testing
M.detect_event_handler_context = detect_event_handler_context
M.infer_handler_type_from_lsp = infer_handler_type_from_lsp
M.find_component_scope = find_component_scope
M.generate_handler_name = generate_handler_name
M.find_return_statement = find_return_statement
M.generate_function_code = generate_function_code
M.get_react_import_info = get_react_import_info
M.has_type_import = has_type_import
M.create_type_import_edit = create_type_import_edit

return M
