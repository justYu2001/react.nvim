---@class TSNode
---@field range fun(self: TSNode): number, number, number, number
---@field start fun(self: TSNode): number, number
---@field type fun(self: TSNode): string
---@field field fun(self: TSNode, name: string): TSNode[]
---@field parent fun(self: TSNode): TSNode|nil
---@field named_child fun(self: TSNode, index: number): TSNode|nil
---@field named_child_count fun(self: TSNode): number
---@field iter_children fun(self: TSNode): fun(): TSNode, string

return {}
