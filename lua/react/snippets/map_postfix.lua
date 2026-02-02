local M = {}

-- Extract text from LSP hover response
local function extract_text_from_hover(contents)
    if type(contents) == "string" then
        return contents
    elseif contents.value then
        return contents.value
    elseif type(contents) == "table" and contents[1] then
        return contents[1].value or contents[1]
    end
    return nil
end

-- Check if type string indicates array type
local function is_array_type_string(type_str)
    -- Array type patterns from TypeScript/JavaScript
    local array_patterns = {
        "%[%]", -- Type[] syntax
        "Array<", -- Array<Type> syntax
        "ReadonlyArray<", -- ReadonlyArray<Type>
        "%.map%(", -- Already has .map (chained)
        "%.filter%(", -- Array method result
        "%.slice%(", -- Array method result
    }

    for _, pattern in ipairs(array_patterns) do
        if type_str:match(pattern) then
            return true
        end
    end

    return false
end

-- Check if expression at position is array type via LSP
local function is_array_type(bufnr, line, col)
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = { line = line, character = col },
    }

    -- Synchronous request with 500ms timeout
    local result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", params, 500)

    if not result then
        return true -- Fallback: allow snippet if LSP unavailable
    end

    -- Parse hover response for type information
    for _, res in pairs(result) do
        if res.result and res.result.contents then
            local contents = res.result.contents
            local text = extract_text_from_hover(contents)

            if text then
                return is_array_type_string(text)
            end
        end
    end

    return true -- Fallback: allow if no type info
end

function M.get_snippets()
    local ls = require("luasnip")
    local ts_postfix = require("luasnip.extras.treesitter_postfix").treesitter_postfix
    local builtin = require("luasnip.extras.treesitter_postfix").builtin
    local d = ls.dynamic_node
    local sn = ls.snippet_node
    local i = ls.insert_node
    local t = ls.text_node

    -- Show condition: only show inside JSX braces {} and array type
    local function in_jsx_braces_and_array_type()
        local node = vim.treesitter.get_node()
        if not node then
            return false
        end

        -- 1. Check JSX context
        local in_jsx_expr = false
        local jsx_expr_node = nil
        local current = node

        while current do
            if current:type() == "jsx_expression" then
                in_jsx_expr = true
                jsx_expr_node = current
                break
            end
            current = current:parent()
        end

        if not in_jsx_expr or not jsx_expr_node then
            return false
        end

        -- Check if jsx_expression is inside JSX element/fragment
        local jsx_types = {
            "jsx_element",
            "jsx_self_closing_element",
            "jsx_fragment",
        }

        current = jsx_expr_node:parent()
        local in_jsx = false
        while current do
            local node_type = current:type()
            for _, jsx_type in ipairs(jsx_types) do
                if node_type == jsx_type then
                    in_jsx = true
                    break
                end
            end
            if in_jsx then
                break
            end
            current = current:parent()
        end

        if not in_jsx then
            return false
        end

        -- 2. Check if prefix is array type via LSP
        local bufnr = vim.api.nvim_get_current_buf()

        -- Find the expression node inside jsx_expression
        -- The expression we want to check is a child of jsx_expression
        local expr_node = nil
        local target_types = {
            "identifier",
            "member_expression",
            "call_expression",
            "subscript_expression",
            "number",
        }

        -- Helper to check if node type is target
        local function is_target_type(node_type)
            for _, target in ipairs(target_types) do
                if node_type == target then
                    return true
                end
            end
            return false
        end

        -- If we're at jsx_expression, look at its children
        if jsx_expr_node then
            for child in jsx_expr_node:iter_children() do
                local child_type = child:type()
                if is_target_type(child_type) then
                    expr_node = child
                    break
                end
            end
        end

        -- Also try walking up from current node
        if not expr_node then
            local walk_node = node
            local depth = 0
            while walk_node do
                local node_type = walk_node:type()

                if is_target_type(node_type) then
                    expr_node = walk_node
                    break
                end
                walk_node = walk_node:parent()
                depth = depth + 1

                if depth > 10 then
                    break
                end
            end
        end

        if not expr_node then
            return true -- Fallback
        end

        local expr_type = expr_node:type()

        -- For literal values that are clearly not arrays, return false immediately
        local non_array_types = {
            "number",
            "string",
            "template_string",
            "true",
            "false",
            "null",
            "undefined",
            "object",
        }

        for _, non_array in ipairs(non_array_types) do
            if expr_type == non_array then
                return false
            end
        end

        -- Get the start position of the expression node
        local start_row, start_col = expr_node:start()

        return is_array_type(bufnr, start_row, start_col)
    end

    return {
        ts_postfix({
            trig = ".map",
            dscr = "array.map((item) => ())",
            reparseBuffer = "live",
            matchTSNode = builtin.tsnode_matcher.find_topmost_types({
                "identifier",
                "member_expression",
                "call_expression",
                "subscript_expression",
            }),
            wordTrig = false,
            show_condition = in_jsx_braces_and_array_type,
        }, {
            d(1, function(_, parent)
                local matched = parent.snippet.env.LS_TSMATCH
                local array_expr
                if type(matched) == "table" then
                    array_expr = table.concat(matched, "\n")
                else
                    array_expr = matched or ""
                end

                return sn(nil, {
                    t(array_expr .. ".map(("),
                    i(1, "item"),
                    t({ ") => (", "  " }),
                    i(2),
                    t({ "", "))" }),
                })
            end, {}),
        }),
    }
end

return M
