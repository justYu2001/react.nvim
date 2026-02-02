local M = {}

function M.get_snippets()
    local ls = require("luasnip")
    local ts_postfix = require("luasnip.extras.treesitter_postfix").treesitter_postfix
    local builtin = require("luasnip.extras.treesitter_postfix").builtin
    local d = ls.dynamic_node
    local sn = ls.snippet_node
    local i = ls.insert_node
    local t = ls.text_node

    -- JSX types to match
    local jsx_types = {
        "jsx_element",
        "jsx_self_closing_element",
        "jsx_fragment",
    }

    -- Show condition: only show in JSX context
    local function in_jsx_context()
        local node = vim.treesitter.get_node()
        if not node then
            return false
        end

        local current = node
        while current do
            local node_type = current:type()
            for _, jsx_type in ipairs(jsx_types) do
                if node_type == jsx_type then
                    return true
                end
            end
            current = current:parent()
        end

        return false
    end

    return {
        ts_postfix({
            trig = ".cond",
            dscr = "{ && jsx}",
            reparseBuffer = "live",
            matchTSNode = builtin.tsnode_matcher.find_topmost_types(jsx_types),
            wordTrig = false,
            show_condition = in_jsx_context,
        }, {
            d(1, function(_, parent)
                local matched = parent.snippet.env.LS_TSMATCH

                if not matched or type(matched) ~= "table" or #matched == 0 then
                    matched = { "" }
                end

                local jsx_text = table.concat(matched, "\n")
                local has_newline = jsx_text:find("\n") ~= nil

                if has_newline then
                    -- The closing tag (last line) has the base indent
                    local base_indent = matched[#matched]:match("^(%s*)") or ""

                    -- Transform: Remove base_indent (vim will add it back), add +2 relative
                    local result_lines = {}
                    for idx, line in ipairs(matched) do
                        if line:match("^%s*$") then
                            table.insert(result_lines, "")
                        elseif idx == 1 then
                            -- First line: add 2 spaces (no base, vim adds it)
                            table.insert(result_lines, "  " .. line)
                        else
                            -- Other lines: strip base, add 2
                            local current_indent = line:match("^(%s*)") or ""
                            local content = line:match("^%s*(.*)$")
                            local relative_indent = #current_indent - #base_indent
                            local new_line = string.rep(" ", relative_indent + 2) .. content
                            table.insert(result_lines, new_line)
                        end
                    end

                    local indented_jsx = table.concat(result_lines, "\n")
                    local jsx_lines = vim.split(indented_jsx, "\n")
                    return sn(nil, {
                        t("{"),
                        i(1),
                        t(" && ("),
                        t({ "", unpack(jsx_lines) }),
                        t({ "", ")}" }),
                    })
                else
                    return sn(nil, {
                        t("{"),
                        i(1),
                        t(" && " .. jsx_text .. "}"),
                    })
                end
            end, {}),
        }),
    }
end

return M
