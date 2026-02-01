local helpers = require("tests.helpers")
local create_ref = require("react.code_actions.create_ref")

local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

-- Helper to create TSX buffer
local function create_tsx_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "typescriptreact"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
end

-- Helper to get component node from a buffer with a function component
local function get_component_node(bufnr, row, col)
    local gen = require("react.code_actions.generate_event_handler")
    return gen.find_component_scope(bufnr, row or 0, col or 0)
end

-- ============================================================
-- generate_ref_name
-- ============================================================
T["generate_ref_name"] = new_set()

T["generate_ref_name"]["HTML element → <name>Ref"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local comp = get_component_node(bufnr, 1, 10)
    assert(comp)

    local name = create_ref.generate_ref_name("div", bufnr, comp)
    eq(name, "divRef")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_ref_name"]["custom component → camelCase + Ref"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <MyButton />;",
        "}",
    })

    local comp = get_component_node(bufnr, 1, 10)
    assert(comp)

    local name = create_ref.generate_ref_name("MyButton", bufnr, comp)
    eq(name, "myButtonRef")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_ref_name"]["conflict resolution appends suffix starting at 2"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const divRef = useRef(null);",
        "  return <div />;",
        "}",
    })

    local comp = get_component_node(bufnr, 1, 10)
    assert(comp)

    local name = create_ref.generate_ref_name("div", bufnr, comp)
    eq(name, "divRef2")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_ref_name"]["conflict resolution skips to next available suffix"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const divRef = useRef(null);",
        "  const divRef2 = useRef(null);",
        "  const divRef3 = useRef(null);",
        "  return <div />;",
        "}",
    })

    local comp = get_component_node(bufnr, 1, 10)
    assert(comp)

    local name = create_ref.generate_ref_name("div", bufnr, comp)
    eq(name, "divRef4")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["generate_ref_name"]["custom component conflict resolution"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  const myButtonRef = useRef(null);",
        "  return <MyButton />;",
        "}",
    })

    local comp = get_component_node(bufnr, 1, 10)
    assert(comp)

    local name = create_ref.generate_ref_name("MyButton", bufnr, comp)
    eq(name, "myButtonRef2")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- ============================================================
-- get_ref_type
-- ============================================================
T["get_ref_type"] = new_set()

T["get_ref_type"]["HTML element React < 19 → ElementRef"] = function()
    local type_str, extra = create_ref.get_ref_type("div", true, nil, 18)
    eq(type_str, 'ElementRef<"div">')
    eq(extra, "ElementRef")
end

T["get_ref_type"]["HTML element React >= 19 → ComponentRef"] = function()
    local type_str, extra = create_ref.get_ref_type("div", true, nil, 19)
    eq(type_str, 'ComponentRef<"div">')
    eq(extra, "ComponentRef")
end

T["get_ref_type"]["HTML button React >= 19"] = function()
    local type_str, extra = create_ref.get_ref_type("button", true, nil, 19)
    eq(type_str, 'ComponentRef<"button">')
    eq(extra, "ComponentRef")
end

T["get_ref_type"]["HTML input React < 19"] = function()
    local type_str, extra = create_ref.get_ref_type("input", true, nil, 18)
    eq(type_str, 'ElementRef<"input">')
    eq(extra, "ElementRef")
end

T["get_ref_type"]["unknown tag React < 19 → ElementRef"] = function()
    local type_str, extra = create_ref.get_ref_type("mywidget", true, nil, 18)
    eq(type_str, 'ElementRef<"mywidget">')
    eq(extra, "ElementRef")
end

T["get_ref_type"]["unknown tag React >= 19 → ComponentRef"] = function()
    local type_str, extra = create_ref.get_ref_type("mywidget", true, nil, 19)
    eq(type_str, 'ComponentRef<"mywidget">')
    eq(extra, "ComponentRef")
end

T["get_ref_type"]["custom component React < 19 → ElementRef"] = function()
    local type_str, extra = create_ref.get_ref_type("MyComp", true, nil, 18)
    eq(type_str, "ElementRef<typeof MyComp>")
    eq(extra, "ElementRef")
end

T["get_ref_type"]["custom component React >= 19 → ComponentRef"] = function()
    local type_str, extra = create_ref.get_ref_type("MyComp", true, nil, 19)
    eq(type_str, "ComponentRef<typeof MyComp>")
    eq(extra, "ComponentRef")
end

T["get_ref_type"]["custom component React 20 → ComponentRef"] = function()
    local type_str, extra = create_ref.get_ref_type("MyComp", true, nil, 20)
    eq(type_str, "ComponentRef<typeof MyComp>")
    eq(extra, "ComponentRef")
end

T["get_ref_type"]["custom component version nil (unknown) → ElementRef fallback"] = function()
    local type_str, extra = create_ref.get_ref_type("MyComp", true, nil, nil)
    eq(type_str, "ElementRef<typeof MyComp>")
    eq(extra, "ElementRef")
end

T["get_ref_type"]["JS any element → no type, no import"] = function()
    local type_str, extra = create_ref.get_ref_type("div", false, nil)
    eq(type_str, nil)
    eq(extra, nil)
end

T["get_ref_type"]["JS custom component → no type, no import"] = function()
    local type_str, extra = create_ref.get_ref_type("MyComp", false, nil)
    eq(type_str, nil)
    eq(extra, nil)
end

-- ============================================================
-- get_react_version
-- ============================================================
T["get_react_version"] = new_set()

T["get_react_version"]["parses ^18.2.0"] = function()
    local orig_buf_get_name = vim.api.nvim_buf_get_name
    local orig_filereadable = vim.fn.filereadable
    local orig_readfile = vim.fn.readfile

    vim.api.nvim_buf_get_name = function(_)
        return "/project/src/App.tsx"
    end
    vim.fn.filereadable = function(path)
        if path == "/project/package.json" then
            return 1
        end
        return 0
    end
    vim.fn.readfile = function(path)
        if path == "/project/package.json" then
            return {
                "{",
                '  "dependencies": {',
                '    "react": "^18.2.0"',
                "  }",
                "}",
            }
        end
        return nil
    end

    local version = create_ref.get_react_version(1)
    eq(version, 18)

    vim.api.nvim_buf_get_name = orig_buf_get_name
    vim.fn.filereadable = orig_filereadable
    vim.fn.readfile = orig_readfile
end

T["get_react_version"]["parses ~19.0.0"] = function()
    local orig_buf_get_name = vim.api.nvim_buf_get_name
    local orig_filereadable = vim.fn.filereadable
    local orig_readfile = vim.fn.readfile

    vim.api.nvim_buf_get_name = function(_)
        return "/project/src/App.tsx"
    end
    vim.fn.filereadable = function(path)
        if path == "/project/package.json" then
            return 1
        end
        return 0
    end
    vim.fn.readfile = function(path)
        if path == "/project/package.json" then
            return {
                "{",
                '  "dependencies": {',
                '    "react": "~19.0.0"',
                "  }",
                "}",
            }
        end
        return nil
    end

    local version = create_ref.get_react_version(1)
    eq(version, 19)

    vim.api.nvim_buf_get_name = orig_buf_get_name
    vim.fn.filereadable = orig_filereadable
    vim.fn.readfile = orig_readfile
end

T["get_react_version"]["parses bare version 18.3.1"] = function()
    local orig_buf_get_name = vim.api.nvim_buf_get_name
    local orig_filereadable = vim.fn.filereadable
    local orig_readfile = vim.fn.readfile

    vim.api.nvim_buf_get_name = function(_)
        return "/project/src/App.tsx"
    end
    vim.fn.filereadable = function(path)
        if path == "/project/package.json" then
            return 1
        end
        return 0
    end
    vim.fn.readfile = function(path)
        if path == "/project/package.json" then
            return {
                "{",
                '  "dependencies": {',
                '    "react": "18.3.1"',
                "  }",
                "}",
            }
        end
        return nil
    end

    local version = create_ref.get_react_version(1)
    eq(version, 18)

    vim.api.nvim_buf_get_name = orig_buf_get_name
    vim.fn.filereadable = orig_filereadable
    vim.fn.readfile = orig_readfile
end

T["get_react_version"]["finds react in devDependencies"] = function()
    local orig_buf_get_name = vim.api.nvim_buf_get_name
    local orig_filereadable = vim.fn.filereadable
    local orig_readfile = vim.fn.readfile

    vim.api.nvim_buf_get_name = function(_)
        return "/project/src/App.tsx"
    end
    vim.fn.filereadable = function(path)
        if path == "/project/package.json" then
            return 1
        end
        return 0
    end
    vim.fn.readfile = function(path)
        if path == "/project/package.json" then
            return {
                "{",
                '  "devDependencies": {',
                '    "react": "^19.1.0"',
                "  }",
                "}",
            }
        end
        return nil
    end

    local version = create_ref.get_react_version(1)
    eq(version, 19)

    vim.api.nvim_buf_get_name = orig_buf_get_name
    vim.fn.filereadable = orig_filereadable
    vim.fn.readfile = orig_readfile
end

T["get_react_version"]["returns nil for empty buf name"] = function()
    local orig_buf_get_name = vim.api.nvim_buf_get_name
    vim.api.nvim_buf_get_name = function(_)
        return ""
    end

    local version = create_ref.get_react_version(1)
    eq(version, nil)

    vim.api.nvim_buf_get_name = orig_buf_get_name
end

T["get_react_version"]["returns nil when package.json has no react key"] = function()
    local orig_buf_get_name = vim.api.nvim_buf_get_name
    local orig_filereadable = vim.fn.filereadable
    local orig_readfile = vim.fn.readfile

    vim.api.nvim_buf_get_name = function(_)
        return "/project/src/App.tsx"
    end
    vim.fn.filereadable = function(path)
        if path == "/project/package.json" then
            return 1
        end
        return 0
    end
    vim.fn.readfile = function(path)
        if path == "/project/package.json" then
            return {
                "{",
                '  "dependencies": {',
                '    "lodash": "^4.17.21"',
                "  }",
                "}",
            }
        end
        return nil
    end

    local version = create_ref.get_react_version(1)
    eq(version, nil)

    vim.api.nvim_buf_get_name = orig_buf_get_name
    vim.fn.filereadable = orig_filereadable
    vim.fn.readfile = orig_readfile
end

-- ============================================================
-- create_use_ref_import_edit
-- ============================================================
T["create_use_ref_import_edit"] = new_set()

T["create_use_ref_import_edit"]["returns nil when useRef already imported"] = function()
    local bufnr = create_tsx_buffer({
        "import { useRef, useState } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = create_ref.create_use_ref_import_edit(bufnr)
    eq(edit, nil)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_use_ref_import_edit"]["adds useRef to named imports — alphabetically first"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    -- useRef < useState alphabetically? No: "useRef" < "useState" → true (R < S)
    local edit = create_ref.create_use_ref_import_edit(bufnr)
    assert(edit)
    eq(edit.text, "useRef, ")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_use_ref_import_edit"]["adds useRef to named imports — alphabetically last"] = function()
    local bufnr = create_tsx_buffer({
        "import { useState, useEffect } from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    -- Sorted: useEffect, useRef, useState → useRef is in the middle
    local edit = create_ref.create_use_ref_import_edit(bufnr)
    assert(edit)
    eq(edit.text, ", useRef")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_use_ref_import_edit"]["creates new import when no react import exists"] = function()
    local bufnr = create_tsx_buffer({
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = create_ref.create_use_ref_import_edit(bufnr)
    assert(edit)
    eq(edit.row, 0)
    eq(edit.col, 0)
    eq(edit.text, "import { useRef } from 'react';\n")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_use_ref_import_edit"]["respects 'use client' directive"] = function()
    local bufnr = create_tsx_buffer({
        "'use client'",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = create_ref.create_use_ref_import_edit(bufnr)
    assert(edit)
    eq(edit.row, 1)
    eq(edit.col, 0)
    eq(edit.text, "import { useRef } from 'react';\n")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["create_use_ref_import_edit"]["appends to default import"] = function()
    local bufnr = create_tsx_buffer({
        "import React from 'react';",
        "function App() {",
        "  return <div />;",
        "}",
    })

    local edit = create_ref.create_use_ref_import_edit(bufnr)
    assert(edit)
    eq(edit.text, ", { useRef }")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
