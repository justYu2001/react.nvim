local M = {}

--- Convert PascalCase to kebab-case: MyComponent → my-component
---@param str string
---@return string
function M.to_kebab_case(str)
	return str
		:gsub("([A-Z]+)([A-Z][a-z])", "%1-%2")
		:gsub("([a-z%d])([A-Z])", "%1-%2")
		:lower()
end

--- Convert PascalCase to snake_case: MyComponent → my_component
---@param str string
---@return string
function M.to_snake_case(str)
	return str
		:gsub("([A-Z]+)([A-Z][a-z])", "%1_%2")
		:gsub("([a-z%d])([A-Z])", "%1_%2")
		:lower()
end

--- Check if component name matches filename
---@param bufnr number
---@param component_name string
---@return boolean match_found
---@return string|nil old_filename Filename with extension if match found
---@return string|nil case_style "exact"|"kebab"|"snake" if match found
function M.component_matches_filename(bufnr, component_name)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return false, nil, nil
	end

	-- Only support specific extensions
	local ext = vim.fn.fnamemodify(filepath, ":e")
	if not vim.tbl_contains({ "tsx", "ts", "jsx", "js" }, ext) then
		return false, nil, nil
	end

	local basename = vim.fn.fnamemodify(filepath, ":t:r") -- filename without extension

	-- Generate possible patterns
	local patterns = {
		{ name = component_name, style = "exact" },
		{ name = M.to_kebab_case(component_name), style = "kebab" },
		{ name = M.to_snake_case(component_name), style = "snake" },
	}

	-- Case-insensitive comparison
	local basename_lower = basename:lower()
	for _, pattern in ipairs(patterns) do
		if pattern.name:lower() == basename_lower then
			local old_filename = vim.fn.fnamemodify(filepath, ":t")
			return true, old_filename, pattern.style
		end
	end

	return false, nil, nil
end

--- Calculate new filename using same case style as old
---@param new_component_name string New component name in PascalCase
---@param old_filename string Old filename with extension
---@param case_style string "exact"|"kebab"|"snake"
---@return string new_filename New filename with extension
function M.calculate_new_filename(new_component_name, old_filename, case_style)
	local ext = vim.fn.fnamemodify(old_filename, ":e")

	local new_basename
	if case_style == "exact" then
		new_basename = new_component_name
	elseif case_style == "kebab" then
		new_basename = M.to_kebab_case(new_component_name)
	elseif case_style == "snake" then
		new_basename = M.to_snake_case(new_component_name)
	else
		new_basename = new_component_name
	end

	return new_basename .. "." .. ext
end

return M
