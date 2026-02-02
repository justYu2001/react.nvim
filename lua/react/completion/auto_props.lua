local M = {}

-- Detect JSX component at cursor position
local function detect_jsx_component(bufnr, row, col)
    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    local current = node
    local jsx_element_node = nil

    -- First, find the jsx_opening_element, jsx_self_closing_element, or jsx_element (for incomplete tags)
    while current do
        local t = current:type()

        if t == "jsx_opening_element" or t == "jsx_self_closing_element" or t == "jsx_element" then
            jsx_element_node = current
            break
        end

        current = current:parent()
    end

    -- Try to extract component name from the current line using regex first
    -- This handles incomplete JSX where treesitter has ERROR nodes
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

    local component_name = line:match("<([A-Z][%w_]*)")

    if not component_name then
        return nil
    end

    -- If we found a component name but no valid JSX node, return context with nil node
    if not jsx_element_node then
        return {
            jsx_element_node = nil,
            component_name = component_name,
            component_row = row,
        }
    end

    -- Verify node starts on the same row we're searching
    local node_start_row, _, node_end_row = jsx_element_node:range()

    -- For incomplete tags, node should not span multiple rows or start on different row
    -- (otherwise it might be incorrectly including next line's component)
    local valid_node = jsx_element_node

    if node_start_row ~= row then
        valid_node = nil
    elseif node_end_row > row then
        -- If line doesn't end with > or />, it's incomplete and shouldn't span multiple rows
        if not line:match("[/>]%s*$") then
            valid_node = nil
        end
    end

    return {
        jsx_element_node = valid_node,
        component_name = component_name,
        component_row = row,
    }
end

-- Get already-assigned props (only explicit jsx_attribute, not spread)
local function get_assigned_props(jsx_element_node, bufnr)
    local assigned = {}

    -- If no valid node (incomplete tag), return empty
    if not jsx_element_node then
        return assigned
    end

    -- If we have a jsx_element (incomplete tag), find the opening element child
    local target_node = jsx_element_node
    if jsx_element_node:type() == "jsx_element" then
        for child in jsx_element_node:iter_children() do
            if
                child:type() == "jsx_opening_element"
                or child:type() == "jsx_self_closing_element"
            then
                target_node = child
                break
            end
        end
    end

    for child in target_node:iter_children() do
        if child:type() == "jsx_attribute" then
            for attr_child in child:iter_children() do
                if attr_child:type() == "property_identifier" then
                    assigned[vim.treesitter.get_node_text(attr_child, bufnr)] = true
                    break
                end
            end
        end
    end

    return assigned
end

-- Query LSP for required props
local function query_required_props(bufnr, component_row)
    local line_text = vim.api.nvim_buf_get_lines(bufnr, component_row, component_row + 1, false)[1]

    -- Insert temporary closing to make JSX valid for LSP
    local needs_temp_close = not line_text:match("[/>]$")
    local insert_col = #line_text
    local comp_col = insert_col

    if needs_temp_close then
        vim.api.nvim_buf_set_text(
            bufnr,
            component_row,
            insert_col,
            component_row,
            insert_col,
            { " >" }
        )
        comp_col = insert_col + 1
    end

    local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = { line = component_row, character = comp_col },
    }

    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/completion", params, 1000)

    -- Remove temporary closing
    if needs_temp_close then
        vim.api.nvim_buf_set_text(
            bufnr,
            component_row,
            insert_col,
            component_row,
            insert_col + 2,
            { "" }
        )
    end

    if not result then
        return nil
    end

    local required_props = {}
    local seen = {}

    for client_id, client_result in pairs(result) do
        local completion = client_result.result

        if completion then
            local list = completion.items or completion
            local client = vim.lsp.get_client_by_id(client_id)

            for _, item in ipairs(list) do
                local label = item.label or ""

                -- Skip components (PascalCase), only check lowercase props
                if label:match("^[A-Z]") then
                    goto continue
                end

                -- Resolve item if detail is missing (lazy completion)
                local detail = item.detail
                if not detail and item.data and client then
                    local response =
                        client.request_sync("completionItem/resolve", item, 1000, bufnr)
                    if response and response.result then
                        detail = response.result.detail
                    end
                end

                local prop_name, optional
                if detail then
                    -- Parse: "(property) ButtonProps.propName?: Type" or "(property) propName: Type"
                    prop_name, optional = detail:match("%.(%w+)(%??):")

                    -- Fallback to simple format
                    if not prop_name then
                        prop_name, optional = detail:match("%(property%)%s+(%w+)(%??):")
                    end
                else
                    -- Fallback: parse label for "?" suffix
                    -- "a" = required, "b?" = optional
                    if label:match("%?$") then
                        prop_name = label:match("^(%w+)%?$")
                        optional = "?"
                    else
                        prop_name = label:match("^(%w+)$")
                        optional = ""
                    end
                end

                if prop_name and optional == "" and not seen[prop_name] then
                    seen[prop_name] = true
                    table.insert(required_props, prop_name)
                end

                ::continue::
            end
        end
    end

    return #required_props > 0 and required_props or nil
end

-- Generate LuaSnip snippet for props
local function generate_props_snippet(required_props)
    local ok, luasnip = pcall(require, "luasnip")
    if not ok then
        return nil
    end

    local ls = luasnip
    local s = ls.snippet
    local i = ls.insert_node
    local t = ls.text_node

    local nodes = {}

    for idx, prop in ipairs(required_props) do
        table.insert(nodes, t(" " .. prop .. "={"))
        table.insert(nodes, i(idx))
        table.insert(nodes, t("}"))
    end

    return s("", nodes)
end

-- Insert props snippet at correct position
local function insert_props_snippet(bufnr, component_row, snippet)
    local line_text = vim.api.nvim_buf_get_lines(bufnr, component_row, component_row + 1, false)[1]
    local insert_col = #line_text

    -- Detect self-closing vs opening tag
    if line_text and line_text:sub(-2) == "/>" then
        insert_col = insert_col - 2
    elseif line_text and line_text:sub(-1) == ">" then
        insert_col = insert_col - 1
    end

    vim.schedule(function()
        local ok, luasnip = pcall(require, "luasnip")
        if ok then
            luasnip.snip_expand(snippet, { pos = { component_row, insert_col } })
        end
    end)
end

-- Main entry point called by CompleteDone autocmd
function M.handle_completion()
    local completed_item = vim.v.completed_item

    -- Check if valid completion
    if not completed_item or not completed_item.word or completed_item.word == "" then
        return
    end

    -- Defer to allow treesitter to re-parse after completion
    vim.schedule(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row = cursor[1] - 1
        local col = cursor[2]

        -- After completion, cursor is after component name, search backward
        local search_col = math.max(0, col - 1)

        -- Detect JSX component at cursor
        local context = detect_jsx_component(bufnr, row, search_col)
        if not context then
            return
        end

        -- Get assigned props
        local assigned = get_assigned_props(context.jsx_element_node, bufnr)

        -- Query required props
        local required_props = query_required_props(bufnr, context.component_row)
        if not required_props then
            return
        end

        -- Filter out already assigned props
        local missing_props = {}
        for _, prop in ipairs(required_props) do
            if not assigned[prop] then
                table.insert(missing_props, prop)
            end
        end

        if #missing_props == 0 then
            return
        end

        -- Generate and insert snippet
        local snippet = generate_props_snippet(missing_props)
        if snippet then
            insert_props_snippet(bufnr, context.component_row, snippet)
        end
    end)
end

-- Export for testing
M.detect_jsx_component = detect_jsx_component

return M
