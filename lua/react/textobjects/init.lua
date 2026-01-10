local M = {}
M._keymaps = {}

local function find_jsx_element_at_cursor(bufnr)
    local ft = vim.bo[bufnr].filetype

    local lang_map = {
        javascript = "javascript",
        typescript = "typescript",
        javascriptreact = "javascript",
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

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]

    local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })

    if not node then
        return nil
    end

    local current = node

    while current do
        local type = current:type()

        if
            type == "jsx_element"
            or type == "jsx_self_closing_element"
            or type == "jsx_fragment"
        then
            return current, type
        end

        current = current:parent()
    end

    return nil
end

local function get_inner_range(node, node_type, _)
    if node_type == "jsx_element" then
        local open_tag, close_tag

        for child in node:iter_children() do
            local t = child:type()

            if t == "jsx_opening_element" then
                open_tag = child
            elseif t == "jsx_closing_element" then
                close_tag = child
            end
        end

        if not open_tag or not close_tag then
            -- Fallback to full range
            return node:range()
        end

        local _, _, oer, oec = open_tag:range()
        local csr, csc, _, _ = close_tag:range()

        return oer, oec, csr, csc
    elseif node_type == "jsx_fragment" then
        local children = {}

        for child in node:iter_children() do
            table.insert(children, child)
        end

        if #children >= 2 then
            local _, _, oer, oec = children[1]:range()
            local csr, csc, _, _ = children[#children]:range()
            return oer, oec, csr, csc
        end
    end

    -- Fallback
    return node:range()
end

local function set_visual_selection(sr, sc, er, ec)
    vim.cmd("normal! \27") -- \27 = ESC

    vim.api.nvim_buf_set_mark(0, "<", sr + 1, sc, {})
    vim.api.nvim_buf_set_mark(0, ">", er + 1, math.max(0, ec - 1), {})

    vim.cmd("normal! gv")
end

function M.setup()
    local bufnr = vim.api.nvim_get_current_buf()
    local opts = { noremap = true, silent = true, buffer = bufnr }

    local mode_labels = {
        o = ":omap ",
        x = ":xmap ",
    }

    local conflicts = {}

    for _, mode in ipairs({ "o", "x" }) do
        for _, lhs in ipairs({ "it", "at" }) do
            local existing = vim.fn.maparg(lhs, mode, false, true)

            if existing and existing ~= "" and not existing.buffer then
                local label = mode_labels[mode] or (mode .. " ")

                table.insert(conflicts, "`" .. label .. lhs .. "`")
            end
        end
    end

    if #conflicts > 0 then
        vim.notify(
            string.format(
                "[react.nvim] Overriding existing mappings: %s",
                table.concat(conflicts, ", ")
            ),
            vim.log.levels.WARN
        )
    end

    if not M._keymaps[bufnr] then
        M._keymaps[bufnr] = {
            { mode = "o", lhs = "it" },
            { mode = "o", lhs = "at" },
            { mode = "x", lhs = "it" },
            { mode = "x", lhs = "at" },
        }
    end

    vim.keymap.set("o", "it", M.select_inner_tag, opts)
    vim.keymap.set("o", "at", M.select_around_tag, opts)
    vim.keymap.set("x", "it", M.select_inner_tag, opts)
    vim.keymap.set("x", "at", M.select_around_tag, opts)
end

function M.teardown()
    local bufnr = vim.api.nvim_get_current_buf()
    if M._keymaps[bufnr] then
        for _, km in ipairs(M._keymaps[bufnr]) do
            pcall(vim.keymap.del, km.mode, km.lhs, { buffer = bufnr })
        end
        M._keymaps[bufnr] = nil
    end
end

function M.select_around_tag()
    local bufnr = vim.api.nvim_get_current_buf()

    local node, _ = find_jsx_element_at_cursor(bufnr)

    if not node then
        vim.notify("[react.nvim] Not inside JSX element", vim.log.levels.WARN)

        return
    end

    local sr, sc, er, ec = node:range()

    set_visual_selection(sr, sc, er, ec)
end

function M.select_inner_tag()
    local bufnr = vim.api.nvim_get_current_buf()

    local node, node_type = find_jsx_element_at_cursor(bufnr)

    if not node then
        vim.notify("[react.nvim] Not inside JSX element", vim.log.levels.WARN)

        return
    end

    if node_type == "jsx_self_closing_element" then
        vim.notify("[react.nvim] Self-closing element has no inner content", vim.log.levels.INFO)

        return
    end

    local sr, sc, er, ec = get_inner_range(node, node_type, bufnr)

    set_visual_selection(sr, sc, er, ec)
end

return M
