--!strict
-- The cell registry (cells/Registry.qml), the part the configuration needs
-- now: old names and retired cells. The rest comes with the cells.
local M = {}

-- `session` became `system` on 2026-09-23; `sinestesia` became `media` on
-- 2026-10-07. A block with the old name still works.
M.aliases = { session = "system", sinestesia = "media" }

-- Folded into another cell: `recording` joined `utility` on 2026-09-27.
M.retired = { recording = true }

function M.canonical(kind: string): string
    return M.aliases[kind] or kind
end

-- A membrane or floating list with old names replaced and retired cells
-- dropped, in place.
function M.renamed(list: { any }?): { any }
    local function walk(cells: { any }?): { any }
        local kept = {}
        for _, entry in cells or {} do
            if type(entry) == "table" and entry.type then
                entry.type = M.canonical(entry.type)
            end
            if not (type(entry) == "table" and M.retired[entry.type]) then
                table.insert(kept, entry)
            end
        end
        return kept
    end
    for _, block in list or {} do
        if block.cells then block.cells = walk(block.cells) end
        for _, tissue in block.tissues or {} do
            if tissue.cells then tissue.cells = walk(tissue.cells) end
        end
    end
    return list or {}
end

return M
