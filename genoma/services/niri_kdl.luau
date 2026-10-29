--!strict
-- Reading niri's configuration as text (services/niri-config.js), the part
-- the services ported so far need: includes and `output` sections. Binds,
-- window rules, workspaces, startup lines and their rewriting come with the
-- services that read them (Keybinds, NiriSettings, Monitors' editing).
--
-- The configuration belongs to niri and to whoever wrote it, so it is never
-- parsed into a model and printed back: it is scanned for positions, and an
-- edit will replace exactly the span it changes. Offsets here are 1-based,
-- `start` inclusive and `end` exclusive, as string.sub(text, start, end - 1).

local M = {}

-- ---- Tokens ---------------------------------------------------------------
--
-- Enough of KDL (v1 and v2) to find nodes and their extents: identifiers,
-- quoted, raw and multi-line strings, braces, semicolons, `=`, line and
-- nested block comments, and the slashdash that comments out what follows.

local function is_space(c: string): boolean
    return c == " " or c == "\t" or c == "\r" or c == "\u{feff}"
end

local function ends(c: string): boolean
    return is_space(c) or c == "\n" or c == "{" or c == "}" or c == ";" or c == "=" or c == '"' or c == "(" or c == ")"
end

local function starts(text: string, at: number, what: string): boolean
    return string.sub(text, at, at + #what - 1) == what
end

function M.tokenize(text: string, comments: boolean?): { any }
    local tokens = {}
    local n = #text
    local i = 1
    while i <= n do
        local c = string.sub(text, i, i)
        if is_space(c) then
            i += 1
        elseif c == "\\" then
            -- A line continuation: the newline after it does not end the node.
            local j = i + 1
            while j <= n and is_space(string.sub(text, j, j)) do j += 1 end
            if starts(text, j, "//") then
                while j <= n and string.sub(text, j, j) ~= "\n" do j += 1 end
            end
            i = if string.sub(text, j, j) == "\n" then j + 1 else i + 1
        elseif c == "\n" then
            table.insert(tokens, { type = "newline", start = i, ["end"] = i + 1 })
            i += 1
        elseif starts(text, i, "//") then
            local from = i
            while i <= n and string.sub(text, i, i) ~= "\n" do i += 1 end
            -- Kept only when asked for: a line commented out is how a
            -- configuration switches something off and keeps it.
            if comments then table.insert(tokens, { type = "comment", start = from, ["end"] = i }) end
        elseif starts(text, i, "/*") then
            local depth = 1
            i += 2
            while i <= n and depth > 0 do
                if starts(text, i, "/*") then
                    depth += 1
                    i += 2
                elseif starts(text, i, "*/") then
                    depth -= 1
                    i += 2
                else
                    i += 1
                end
            end
        elseif starts(text, i, "/-") then
            table.insert(tokens, { type = "slashdash", start = i, ["end"] = i + 2 })
            i += 2
        elseif c == "{" or c == "}" or c == ";" or c == "=" then
            local kind = if c == "{" then "open" elseif c == "}" then "close" elseif c == ";" then "semi" else "equals"
            table.insert(tokens, { type = kind, start = i, ["end"] = i + 1 })
            i += 1
        elseif c == "(" then
            -- A type annotation, `(u8)10`. Carried as nothing.
            while i <= n and string.sub(text, i, i) ~= ")" do i += 1 end
            i += 1
        else
            -- Raw strings: r#"…"# in v1, #"…"# in v2, any number of hashes.
            local prefix, hashes = string.match(string.sub(text, i, i + 63), "^(r?)(#*)\"")
            local raw = prefix ~= nil and (prefix == "r" or #(hashes :: string) > 0)
            if raw then
                local close = '"' .. (hashes :: string)
                local from = i + #(prefix :: string) + #(hashes :: string) + 1
                local to = string.find(text, close, from, true)
                local stop = if to then to + #close else n + 1
                table.insert(tokens, { type = "string", start = i, ["end"] = stop,
                    value = string.sub(text, from, (to or n + 1) - 1) })
                i = stop
            elseif starts(text, i, '"""') then
                local to = string.find(text, '"""', i + 3, true)
                local stop = if to then to + 3 else n + 1
                table.insert(tokens, { type = "string", start = i, ["end"] = stop,
                    value = string.sub(text, i + 3, (to or n + 1) - 1) })
                i = stop
            elseif c == '"' then
                local j = i + 1
                local value = {}
                while j <= n and string.sub(text, j, j) ~= '"' do
                    local d = string.sub(text, j, j)
                    if d == "\\" and j + 1 <= n then
                        local e = string.sub(text, j + 1, j + 1)
                        table.insert(value, if e == "n" then "\n" elseif e == "t" then "\t" else e)
                        j += 2
                    else
                        table.insert(value, d)
                        j += 1
                    end
                end
                table.insert(tokens, { type = "string", start = i, ["end"] = j + 1, value = table.concat(value) })
                i = j + 1
            else
                local j = i
                while j <= n and not ends(string.sub(text, j, j)) and not starts(text, j, "//") and not starts(text, j, "/*") do
                    j += 1
                end
                if j == i then j += 1 end
                table.insert(tokens, { type = "ident", start = i, ["end"] = j, value = string.sub(text, i, j - 1) })
                i = j
            end
        end
    end
    return tokens
end

-- ---- Nodes ----------------------------------------------------------------
--
-- A node is a name, then arguments and `key=value` properties, then an
-- optional block of children, and it ends at a newline, a semicolon or the
-- brace that closes its parent. Each one keeps the text offsets it spans.

function M.parse_nodes(tokens: { any }, at: number, nested: boolean): ({ any }, number)
    local nodes = {}
    local i = at
    while i <= #tokens do
        local t = tokens[i]
        if t.type == "newline" or t.type == "semi" then
            i += 1
            continue
        end
        if t.type == "close" then
            if nested then return nodes, i end
            i += 1
            continue
        end

        local dropped = false
        local start = t.start
        if t.type == "slashdash" then
            dropped = true
            i += 1
            while i <= #tokens and tokens[i].type == "newline" do i += 1 end
            if i > #tokens then break end
        end

        local head = tokens[i]
        local node = {
            name = head.value or "",
            name_start = head.start,
            name_end = head["end"],
            start = start,
            ["end"] = head["end"],
            args = {},
            props = {},
            children = nil :: any,
            dropped = dropped,
        }
        i += 1

        local skip_next = false
        while i <= #tokens do
            local u = tokens[i]
            if u.type == "newline" or u.type == "semi" or u.type == "close" then break end
            if u.type == "slashdash" then
                skip_next = true
                i += 1
                continue
            end
            if u.type == "open" then
                local inner, after = M.parse_nodes(tokens, i + 1, true)
                local close_tok = tokens[after]
                local block = {
                    open = u.start,
                    close = if close_tok then close_tok.start else u["end"],
                    nodes = inner,
                }
                i = after + 1
                node["end"] = if close_tok then close_tok["end"] else u["end"]
                if not skip_next then node.children = block end
                skip_next = false
                continue
            end
            local following = tokens[i + 1]
            if (u.type == "ident" or u.type == "string") and following and following.type == "equals" then
                local v = tokens[i + 2]
                if not skip_next and v then node.props[u.value] = v.value end
                node["end"] = if v then v["end"] else following["end"]
                i += if v then 3 else 2
                skip_next = false
                continue
            end
            if not skip_next then
                table.insert(node.args, { value = u.value, quoted = u.type == "string", start = u.start, ["end"] = u["end"] })
            end
            node["end"] = u["end"]
            skip_next = false
            i += 1
        end

        -- A semicolon that ends the node belongs to it: removing the node
        -- takes its terminator with it.
        if i <= #tokens and tokens[i].type == "semi" then
            node["end"] = tokens[i]["end"]
            i += 1
        end
        table.insert(nodes, node)
    end
    return nodes, i
end

-- ---- What a file says -------------------------------------------------------

-- KDL's booleans, in either version's spelling.
local function truthy(value: any): boolean
    return value == true or value == "true" or value == "#true"
end

-- `variable-refresh-rate` is always on, `variable-refresh-rate
-- on-demand=true` only while a window rule asks for it; absent is off.
local function vrr_of(node: any): string
    if not node then return "off" end
    return if truthy(node.props["on-demand"]) then "demand" else "on"
end

local function output_of(node: any): any
    local children = {}
    for _, child in node.children.nodes do
        if not child.dropped then table.insert(children, child) end
    end
    local function named(name: string): any
        for _, child in children do
            if child.name == name then return child end
        end
        return nil
    end
    local position = named("position")
    return {
        kind = "output",
        name = node.args[1].value,
        start = node.start,
        ["end"] = node["end"],
        open = node.children.open,
        close = node.children.close,
        children = children,
        off = named("off") ~= nil,
        primary = named("focus-at-startup") ~= nil,
        vrr = vrr_of(named("variable-refresh-rate")),
        position = if position then {
            start = position.start,
            ["end"] = position["end"],
            x = tonumber(position.props.x),
            y = tonumber(position.props.y),
        } else nil,
    }
end

-- One file's items, in the order they appear: an include is expanded where
-- it stands, so the order between it and what is around it decides.
function M.scan(text: string): { items: { any } }
    local top = M.parse_nodes(M.tokenize(text), 1, false)
    local items = {}
    for _, node in top do
        if node.dropped then continue end
        if node.name == "include" and #node.args > 0 then
            table.insert(items, {
                kind = "include",
                path = node.args[#node.args].value,
                start = node.start,
                optional = truthy(node.props.optional),
            })
        elseif node.name == "output" and #node.args > 0 and node.children then
            table.insert(items, output_of(node))
        end
    end
    return { items = items }
end

-- Where an include points, from the directory of the file that names it.
function M.resolve(path: string, directory: string, home: string): string
    if string.sub(path, 1, 2) == "~/" then return home .. string.sub(path, 2) end
    if string.sub(path, 1, 1) == "/" then return path end
    local dir = string.gsub(directory, "/$", "")
    local rel = string.gsub(path, "^%./", "")
    return dir .. "/" .. rel
end

function M.directory_of(path: string): string
    local cut = string.match(path, "^(.*)/[^/]*$")
    return if cut == nil or cut == "" then "/" else cut
end

-- Whether a section names this output. niri accepts the connector or the
-- monitor's make, model and serial, and compares without case.
function M.names(section: any, connector: string, description: string): boolean
    local wanted = string.lower(tostring(section.name))
    return wanted == string.lower(connector) or (#description > 0 and wanted == string.lower(description))
end

return M
