local M = {}

local gen = require("react.code_actions.generate_event_handler")
local imports = require("react.util.imports")

local function is_pascal_case(name)
    return name ~= nil and name:match("^[A-Z]") ~= nil
end

local function extract_handler_type(detail, component_name)
    if not detail then
        return nil
    end

    -- Bare function type (custom component completion returns just the type)
    local type_match = detail:match("^(%b()%s*=>%s*.+)")

    if not type_match then
        type_match = detail:match("%w+%??: (.+)")
    end

    if not type_match then
        type_match = detail:match("%(property%)%s+%w+:? (.+)")
    end

    if not type_match then
        return nil
    end

    type_match = type_match:gsub("^%s+", ""):gsub("%s+$", "")
    type_match = type_match:gsub("%s*|%s*undefined", "")

    -- Expand React.MouseEventHandler<T> → (event: MouseEvent<T>) => void
    type_match = type_match:gsub("React%.(%w+)EventHandler(<[^>]+>)", function(event_type, generic)
        return string.format("(event: %sEvent%s) => void", event_type, generic)
    end)

    -- Strip any remaining React. prefix (e.g. React.MouseEvent<T> in direct signatures)
    type_match = type_match:gsub("React%.", "")

    -- Normalize param name to "event" for HTML elements only
    if not is_pascal_case(component_name) then
        type_match = type_match:gsub("%((%w+):", "(event:")
    end

    return type_match
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

-- Detect component name at cursor (must be on the identifier in jsx_opening_element or jsx_self_closing_element)
local function detect_component_at_cursor(params)
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

        if t == "jsx_opening_element" or t == "jsx_self_closing_element" then
            -- Find the component identifier (first identifier/jsx_identifier child)
            local name_node = nil

            for child in current:iter_children() do
                if child:type() == "identifier" or child:type() == "jsx_identifier" then
                    name_node = child
                    break
                end
            end

            if not name_node then
                return nil
            end

            local sr, sc, er, ec = name_node:range()

            -- Cursor must be within the name node
            if row >= sr and row <= er and (row > sr or col >= sc) and (row < er or col <= ec) then
                return {
                    jsx_element_node = current,
                    component_name = vim.treesitter.get_node_text(name_node, bufnr),
                }
            end

            return nil -- cursor not on name
        end

        current = current:parent()
    end

    return nil
end

-- Get available event props via LSP completion
local function get_available_event_props(bufnr, jsx_element_node, component_name)
    local _, _, er, ec = jsx_element_node:range()

    local line_text = vim.api.nvim_buf_get_lines(bufnr, er, er + 1, false)[1]
    local comp_col = ec - 1 -- default: before ">"

    -- For self-closing elements, pyright returns JSX attributes when positioned
    -- at "/" only if there is a space before it. For <button/> (no space),
    -- temporarily insert one so pyright sees attribute context.
    local needs_temp_space = false
    local space_col = nil
    if line_text and line_text:sub(ec - 1, ec) == "/>" then
        comp_col = ec - 2 -- at "/"
        -- sub uses 1-based index; comp_col is 0-based, so sub(comp_col, comp_col)
        -- reads the character at 0-based position comp_col - 1 (before "/")
        if line_text:sub(comp_col, comp_col) ~= " " then
            needs_temp_space = true
            space_col = comp_col
            vim.api.nvim_buf_set_text(bufnr, er, comp_col, er, comp_col, { " " })
            comp_col = comp_col + 1 -- "/" shifted right; request at new "/" position
        end
    end

    local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = { line = er, character = comp_col },
    }

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", params, 1000)

    if needs_temp_space then
        vim.api.nvim_buf_set_text(bufnr, er, space_col, er, space_col + 1, { "" })
    end

    if not result then
        return nil
    end

    local items = {}

    for client_id, client_result in pairs(result) do
        local completion = client_result.result

        if completion then
            local list = completion.items or completion

            for _, item in ipairs(list) do
                local label = item.label or (type(item) == "string" and item)

                if label and label:match("^on[A-Z]") then
                    -- strip trailing "?" if present
                    label = label:gsub("%?$", "")

                    -- Resolve item if detail is missing (lazy completion)
                    local detail = item.detail
                    if not detail and item.data then
                        local client = vim.lsp.get_client_by_id(client_id)
                        if client then
                            local response =
                                client:request_sync("completionItem/resolve", item, 1000)
                            if response and response.result then
                                detail = response.result.detail
                            end
                        end
                    end

                    table.insert(items, {
                        name = label,
                        handler_type = extract_handler_type(detail, component_name),
                    })
                end
            end
        end
    end

    table.sort(items, function(a, b)
        return a.name < b.name
    end)
    return #items > 0 and items or nil
end

-- Get already-assigned props (only explicit jsx_attribute, not spread)
local function get_assigned_props(jsx_element_node, bufnr)
    local assigned = {}

    for child in jsx_element_node:iter_children() do
        if child:type() == "jsx_attribute" then
            for attr_child in child:iter_children() do
                if attr_child:type() == "property_identifier" then
                    assigned[vim.treesitter.get_node_text(attr_child, bufnr)] = true
                    break
                end
            end
        end
        -- jsx_spread_attribute intentionally ignored
    end

    return assigned
end

local function html_element_interface(name)
    return "HTML" .. name:sub(1, 1):upper() .. name:sub(2) .. "Element"
end

-- Insert attribute and run handler generation
local function generate_handler_for_prop(
    params,
    jsx_element_node,
    component_name,
    prop_name,
    handler_type
)
    local bufnr = params.bufnr
    local filetype = vim.bo[bufnr].filetype
    local is_typescript = filetype == "typescriptreact" or filetype == "typescript"

    -- Fallback if completion detail didn't have type info
    if not handler_type then
        if is_typescript then
            local generic = ""
            if not is_pascal_case(component_name) then
                generic = string.format("<%s>", html_element_interface(component_name))
            end
            handler_type = string.format("(event: MouseEvent%s) => void", generic)
        else
            handler_type = "(event) => void"
        end
    end

    -- Find component scope (no buffer mutation)
    local sr = jsx_element_node:range()
    local component_node = gen.find_component_scope(bufnr, sr, 0)

    if not component_node then
        return
    end

    if component_node:type() == "class_declaration" then
        return
    end

    -- Generate handler name
    local event_name = prop_name:gsub("^on", "")
    local handler_name =
        gen.generate_handler_name(component_name, event_name, bufnr, component_node)

    -- Find function insertion point (before return)
    local return_node = gen.find_return_statement(component_node)
    local insert_row, insert_col_fn

    if return_node then
        insert_row, insert_col_fn = return_node:range()
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
        insert_row = body_er - 1
        insert_col_fn = 0
    end

    -- Show param menu BEFORE any buffer mutation
    vim.ui.select({
        { label = "No parameters", value = "no_params" },
        { label = "Add all parameters", value = "with_params" },
    }, {
        prompt = "Select handler signature:",
        format_item = function(item)
            return item.label
        end,
    }, function(choice)
        if not choice then
            return -- user cancelled — buffer untouched
        end

        local with_params = choice.value == "with_params"

        -- Extract event type for import
        local event_type = nil

        if with_params and handler_type and is_typescript then
            local param_type = handler_type:match("%(event:%s*(.-)%s*%)%s*=>")
                or handler_type:match("%(event:%s*(.-)%s*%)")

            if param_type then
                event_type = param_type:match("^(%w+Event)")
            end
        end

        local import_edit = event_type and imports.create_type_import_edit(bufnr, event_type)

        -- NOW mutate buffer: insert prop={handlerName} directly (final form)
        local _, _, er, ec = jsx_element_node:range()
        local line_text = vim.api.nvim_buf_get_lines(bufnr, er, er + 1, false)[1]
        local attr_insert_col = ec - 1

        if line_text and line_text:sub(ec - 1, ec) == "/>" then
            attr_insert_col = ec - 2
        end

        -- Only prepend a space if there isn't one already before the insert point
        local prefix = line_text and line_text:sub(attr_insert_col, attr_insert_col) == " " and ""
            or " "
        local attr_text = prefix .. prop_name .. "={" .. handler_name .. "}"
        vim.api.nvim_buf_set_text(bufnr, er, attr_insert_col, er, attr_insert_col, { attr_text })

        -- Insert function and trigger rename
        local indent = get_line_indent(bufnr, insert_row)
        local function_code = gen.generate_function_code(
            handler_name,
            handler_type,
            with_params,
            indent,
            is_typescript
        )

        gen.apply_handler_and_rename(params, handler_name, function_code, {
            row = insert_row,
            col = insert_col_fn,
        }, import_edit)
    end)
end

function M.get_source(null_ls)
    return {
        name = "react-generate-handler",
        filetypes = { "typescriptreact", "javascriptreact", "typescript", "javascript" },
        method = null_ls.methods.CODE_ACTION,
        generator = {
            fn = function(params)
                local context = detect_component_at_cursor(params)

                if not context then
                    return nil
                end

                local available = get_available_event_props(
                    params.bufnr,
                    context.jsx_element_node,
                    context.component_name
                )

                if not available then
                    return nil
                end

                local assigned = get_assigned_props(context.jsx_element_node, params.bufnr)
                local unassigned = {}
                local handler_types = {}

                for _, item in ipairs(available) do
                    if not assigned[item.name] then
                        table.insert(unassigned, item.name)
                        handler_types[item.name] = item.handler_type
                    end
                end

                if #unassigned == 0 then
                    return nil
                end

                return {
                    {
                        title = "Generate handler",
                        action = function()
                            vim.ui.select(unassigned, {
                                prompt = "Select event prop:",
                                format_item = function(item)
                                    return item
                                end,
                            }, function(selected)
                                if not selected then
                                    return
                                end

                                generate_handler_for_prop(
                                    params,
                                    context.jsx_element_node,
                                    context.component_name,
                                    selected,
                                    handler_types[selected]
                                )
                            end)
                        end,
                    },
                }
            end,
        },
    }
end

-- Exported for testing
M.detect_component_at_cursor = detect_component_at_cursor
M.get_assigned_props = get_assigned_props
M.get_available_event_props = get_available_event_props
M.extract_handler_type = extract_handler_type

return M
