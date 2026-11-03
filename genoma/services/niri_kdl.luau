--!strict
-- Reading and rewriting niri's configuration as text
-- (services/niri-config.js at 8ed8892): includes, binds and their block,
-- outputs, window rules, workspaces, startup lines, sections and the lines
-- commented out in them; and the edits the settings make.
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

-- A window rule, the part read so far: what it matches, and whether it
-- asks for variable refresh (what an output set to on-demand waits for).
local function rule_of(node: any): any
    local children = {}
    for _, child in node.children.nodes do
        if not child.dropped then table.insert(children, child) end
    end
    local vrr = nil
    local matches = {}
    for _, child in children do
        if child.name == "variable-refresh-rate" then vrr = child end
        if child.name == "match" then table.insert(matches, child.props) end
    end
    return {
        kind = "rule",
        start = node.start,
        ["end"] = node["end"],
        open = node.children.open,
        close = node.children.close,
        children = children,
        matches = matches,
        vrr = vrr ~= nil and (#vrr.args == 0 or truthy(vrr.args[1].value)),
    }
end

-- What the Niri settings page edits of a rule: its opacity, the width its
-- windows open at and the workspace they open on, the last of each, which
-- is the one niri goes by. Everything else in it is counted.
local RULE_EDITS = { "opacity", "default-column-width", "open-on-workspace" }
local function width_of(node: any): any
    if not node then return nil end
    local size = nil
    for _, child in (if node.children then node.children.nodes else {}) do
        if not child.dropped and (child.name == "proportion" or child.name == "fixed") then size = child end
    end
    if not size or #size.args == 0 then return { kind = "window" } end
    return { kind = size.name, value = tonumber(size.args[1].value) }
end
local function rule_details(rule: any): any
    local last = {}
    local excludes, others = 0, 0
    for _, child in rule.children do
        last[child.name] = child
        if child.name == "exclude" then excludes += 1
        elseif child.name ~= "match" and not table.find(RULE_EDITS, child.name) then others += 1 end
    end
    local opacity, workspace = last["opacity"], last["open-on-workspace"]
    rule.excludes = excludes
    rule.others = others
    rule.opacity = if opacity and #opacity.args > 0 then tonumber(opacity.args[1].value) else nil
    rule.width = width_of(last["default-column-width"])
    rule.workspace = if workspace and #workspace.args > 0 then workspace.args[1].value else nil
    return rule
end

local function workspace_of(node: any): any
    local children = {}
    local output = nil
    for _, child in (if node.children then node.children.nodes else {}) do
        if not child.dropped then
            table.insert(children, child)
            if child.name == "open-on-output" then output = child end
        end
    end
    return {
        kind = "workspace",
        name = node.args[1].value,
        name_start = node.args[1].start,
        name_end = node.args[1]["end"],
        start = node.start,
        ["end"] = node["end"],
        open = if node.children then node.children.open else -1,
        close = if node.children then node.children.close else -1,
        children = children,
        output = if output and #output.args > 0 then output.args[1].value else "",
        output_node = output,
    }
end

local function is_spawn(name: string): boolean
    return name == "spawn-at-startup" or name == "spawn-sh-at-startup"
end
-- `mark` is where the line is switched off, when it is: the comment or the
-- slashdash, and where the node itself begins after it.
local function spawn_of(node: any, mark: any?): any
    local args = {}
    for _, a in node.args do table.insert(args, a.value) end
    return {
        kind = "spawn",
        sh = node.name == "spawn-sh-at-startup",
        args = args,
        on = mark == nil,
        start = if mark then mark.start else node.start,
        ["end"] = if mark then mark["end"] else node["end"],
        body_start = if mark then mark.body_start else node.start,
    }
end

-- Lines commented out whole: a comment at the start of its line whose body
-- is one node, parsed with its offsets in the whole text.
local function commented_nodes(text: string): { any }
    local out = {}
    for _, token in M.tokenize(text, true) do
        if token.type == "comment" and string.sub(text, token.start, token.start + 1) == "//" then
            local s = token.start
            while s > 1 and (string.sub(text, s - 1, s - 1) == " " or string.sub(text, s - 1, s - 1) == "\t") do s -= 1 end
            if s == 1 or string.sub(text, s - 1, s - 1) == "\n" then
                local from = token.start + 2
                local body = string.sub(text, from, token["end"] - 1)
                local nodes = M.parse_nodes(M.tokenize(body), 1, false)
                if #nodes == 1 and not nodes[1].dropped and string.match(nodes[1].name, "^[a-z][a-z%-]*$") then
                    local n = table.clone(nodes[1])
                    local by = from - 1
                    n.start += by
                    n["end"] += by
                    if n.name_start then n.name_start += by end
                    if n.name_end then n.name_end += by end
                    local args = {}
                    for _, a in n.args do table.insert(args, { value = a.value, start = a.start + by, ["end"] = a["end"] + by }) end
                    n.args = args
                    table.insert(out, { start = token.start, ["end"] = token["end"], body_start = from + nodes[1].start - 1, node = n })
                end
            end
        end
    end
    return out
end

-- One file's items, in the order they appear: an include is expanded where
-- it stands, so the order between it and what is around it decides.
function M.scan(text: string): { items: { any }, block: any }
    local top = M.parse_nodes(M.tokenize(text), 1, false)
    local items = {}
    local block = nil
    local notes = commented_nodes(text)
    local function inside(at: number, node: any): boolean
        return node.children ~= nil and at > node.children.open and at < node.children.close
    end
    for _, note in notes do
        if is_spawn(note.node.name) then
            local nested = false
            for _, node in top do if inside(note.start, node) then nested = true end end
            if not nested then table.insert(items, spawn_of(note.node, note)) end
        end
    end
    for _, node in top do
        if is_spawn(node.name) then
            -- Switched off by slashdash: the node starts at the `/-`, its
            -- body at its name.
            table.insert(items, spawn_of(node, if node.dropped
                then { start = node.start, ["end"] = node["end"], body_start = node.name_start } else nil))
            continue
        end
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
        elseif node.name == "window-rule" and node.children then
            table.insert(items, rule_details(rule_of(node)))
        elseif node.name == "workspace" and #node.args > 0 then
            table.insert(items, workspace_of(node))
        elseif (node.name == "layout" or node.name == "input") and node.children then
            -- Lines commented out directly in the section, not in a block
            -- inside it.
            local commented = {}
            for _, note in notes do
                if inside(note.start, node) then
                    local deeper = false
                    for _, child in node.children.nodes do if inside(note.start, child) then deeper = true end end
                    if not deeper then table.insert(commented, note) end
                end
            end
            table.insert(items, { kind = "section", name = node.name, start = node.start, ["end"] = node["end"],
                open = node.children.open, close = node.children.close, children = node.children.nodes, commented = commented })
        elseif node.name == "binds" and node.children then
            block = { start = node.start, ["end"] = node["end"], open = node.children.open, close = node.children.close }
            for _, bind in node.children.nodes do
                if not bind.dropped then
                    local action = nil
                    for _, child in (if bind.children then bind.children.nodes else {}) do
                        if not child.dropped then
                            action = child
                            break
                        end
                    end
                    local args = {}
                    if action then for _, a in action.args do table.insert(args, a.value) end end
                    table.insert(items, {
                        kind = "bind",
                        key = bind.name,
                        key_start = bind.name_start,
                        key_end = bind.name_end,
                        start = bind.start,
                        ["end"] = bind["end"],
                        props = bind.props,
                        action = if action then { name = action.name, args = args, props = action.props } else nil,
                    })
                end
            end
        end
    end
    -- The commented lines were gathered first; the file's order is the
    -- position of each thing in it.
    table.sort(items, function(a, b) return a.start < b.start end)
    return { items = items, block = block }
end

-- ---- Keys ------------------------------------------------------------------

local MODIFIER_NAMES = {
    mod = "Mod", super = "Super", win = "Super", ctrl = "Ctrl", control = "Ctrl", shift = "Shift", alt = "Alt",
    iso_level3_shift = "ISO_Level3_Shift", mod5 = "ISO_Level3_Shift",
    iso_level5_shift = "ISO_Level5_Shift", mod3 = "ISO_Level5_Shift",
}
-- The order a combination is written in, whatever order it was pressed in.
local MODIFIER_ORDER = { "Mod", "Super", "Ctrl", "Alt", "Shift", "ISO_Level3_Shift", "ISO_Level5_Shift" }
local function by_order(a: string, b: string): boolean
    return (table.find(MODIFIER_ORDER, a) or 99) < (table.find(MODIFIER_ORDER, b) or 99)
end

function M.split(key: string): { mods: { string }, key: string }
    local parts = string.split(key, "+")
    local last = table.remove(parts) or ""
    local mods = {}
    for _, part in parts do
        local known = MODIFIER_NAMES[string.lower(part)]
        if known and not table.find(mods, known) then table.insert(mods, known) end
    end
    table.sort(mods, by_order)
    return { mods = mods, key = last }
end

-- Two spellings of one combination compare equal; `Mod` is compared as
-- `Super`, which is what it means when niri runs on a TTY.
function M.normalize(key: string): string
    local parts = M.split(key)
    local mods = {}
    for _, m in parts.mods do
        local n = if m == "Mod" then "Super" else m
        if not table.find(mods, n) then table.insert(mods, n) end
    end
    table.sort(mods)
    table.insert(mods, string.lower(parts.key))
    return table.concat(mods, "+")
end

function M.compose(mods: { string }, key: string): string
    local sorted = table.clone(mods)
    table.sort(sorted, by_order)
    table.insert(sorted, key)
    return table.concat(sorted, "+")
end

-- What a key is called on a keycap: names already short stay, keysym
-- jargon is translated.
local KEY_LABELS = {
    space = "Space", ["return"] = "Enter", kp_enter = "Enter", escape = "Esc", tab = "Tab",
    backspace = "⌫", delete = "Del", insert = "Ins", home = "Home", ["end"] = "End",
    page_up = "PgUp", page_down = "PgDn", prior = "PgUp", next = "PgDn",
    up = "↑", down = "↓", left = "←", right = "→",
    comma = ",", period = ".", slash = "/", backslash = "\\", semicolon = ";", apostrophe = "'",
    grave = "`", minus = "−", equal = "=", plus = "+", bracketleft = "[", bracketright = "]",
    print = "Print", pause = "Pause", menu = "Menu",
    wheelscrollup = "Wheel ↑", wheelscrolldown = "Wheel ↓", wheelscrollleft = "Wheel ←", wheelscrollright = "Wheel →",
    touchpadscrollup = "Swipe ↑", touchpadscrolldown = "Swipe ↓", touchpadscrollleft = "Swipe ←", touchpadscrollright = "Swipe →",
    mouseleft = "Left click", mouseright = "Right click", mousemiddle = "Middle click",
    mouseback = "Back button", mouseforward = "Forward button",
    xf86audioraisevolume = "Vol +", xf86audiolowervolume = "Vol −", xf86audiomute = "Mute", xf86audiomicmute = "Mic mute",
    xf86audioplay = "Play", xf86audiopause = "Pause", xf86audiostop = "Stop", xf86audionext = "Next", xf86audioprev = "Previous",
    xf86monbrightnessup = "Bright +", xf86monbrightnessdown = "Bright −",
}
local MODIFIER_LABELS = {
    Mod = "Super", Super = "Super", Ctrl = "Ctrl", Alt = "Alt", Shift = "Shift",
    ISO_Level3_Shift = "AltGr", ISO_Level5_Shift = "Level 5",
}

function M.keycaps(key: string): { string }
    local parts = M.split(key)
    local out = {}
    for _, m in parts.mods do table.insert(out, MODIFIER_LABELS[m] or m) end
    local label = KEY_LABELS[string.lower(parts.key)]
    if label == nil then
        label = if utf8.len(parts.key) == 1 then string.upper(parts.key) else (string.gsub(parts.key, "^XF86", ""))
    end
    table.insert(out, label)
    return out
end

-- ---- What a bind does, in words ---------------------------------------------

function M.humanize(name: string): string
    local words = string.gsub(name, "-", " ")
    return string.upper(string.sub(words, 1, 1)) .. string.sub(words, 2)
end

-- The name a row goes by: niri's own `hotkey-overlay-title` when somebody
-- chose one, otherwise what the action does.
function M.describe(bind: any): string
    local title = bind.props["hotkey-overlay-title"]
    if title and title ~= "null" and title ~= "#null" then return title end
    local action = bind.action
    if not action then return bind.key end
    if action.name == "spawn" or action.name == "spawn-sh" then
        local words = table.clone(action.args)
        if #words == 0 then return "Run a command" end
        local parts = string.split(words[1], "/")
        words[1] = parts[#parts]
        return "Run " .. table.concat(words, " ")
    end
    local out = { M.humanize(action.name) }
    for _, a in action.args do table.insert(out, tostring(a)) end
    return table.concat(out, " ")
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

-- ---- Writing ------------------------------------------------------------------
--
-- Every edit replaces exactly the span it changes; offsets as everywhere
-- here, 1-based, `end` exclusive. `at(text, p)` is the character at p.

local function at(text: string, p: number): string return string.sub(text, p, p) end
local function blank(c: string): boolean return c == " " or c == "\t" end

function M.quote(value: any): string
    return '"' .. string.gsub(string.gsub(tostring(value), "\\", "\\\\"), '"', '\\"') .. '"'
end

-- One bind as a line. Only what Bioma itself adds is written this way: an
-- edited bind keeps its own text and has only its key replaced.
function M.line(key: string, action: { name: string, args: { string } }, title: string?): string
    local words = { key }
    if title and title ~= "" then table.insert(words, "hotkey-overlay-title=" .. M.quote(title)) end
    local call = { action.name }
    for _, a in action.args do table.insert(call, M.quote(a)) end
    return table.concat(words, " ") .. " { " .. table.concat(call, " ") .. "; }"
end

function M.with_key(text: string, bind: any, key: string): string
    return string.sub(text, 1, bind.key_start - 1) .. key .. string.sub(text, bind.key_end)
end

-- A bind removed with the whole of its lines when it has them to itself,
-- so the block keeps no hole where it was; a comment on the line directly
-- above belongs to it and goes with it.
function M.without(text: string, bind: any): string
    local from, to = bind.start, bind["end"]
    local line_start = from
    while line_start > 1 and blank(at(text, line_start - 1)) do line_start -= 1 end
    local owns_start = line_start == 1 or at(text, line_start - 1) == "\n"
    local line_end = to
    while line_end <= #text and blank(at(text, line_end)) do line_end += 1 end
    local owns_end = line_end > #text or at(text, line_end) == "\n"
    if not owns_start or not owns_end then
        return string.sub(text, 1, from - 1) .. string.sub(text, to)
    end
    from = line_start
    to = math.min(#text + 1, line_end + 1)
    -- Comment lines immediately above, with no blank line between.
    while from > 1 do
        local prev_end = from - 1
        local prev_start = prev_end
        while prev_start > 1 and at(text, prev_start - 1) ~= "\n" do prev_start -= 1 end
        local previous = string.match(string.sub(text, prev_start, prev_end - 1), "^%s*(.-)%s*$") or ""
        if string.sub(previous, 1, 2) ~= "//" then break end
        from = prev_start
    end
    -- Set apart by blank lines on both sides, it leaves one of them.
    local blank_before = from >= 3 and at(text, from - 1) == "\n" and at(text, from - 2) == "\n"
    if blank_before and at(text, to) == "\n" then to += 1 end
    return string.sub(text, 1, from - 1) .. string.sub(text, to)
end

-- A child line at the end of a block, indented like the children already
-- in it.
function M.with_child(text: string, block: any, entry: string, last_child: any?): string
    local indent = "    "
    if last_child then
        local s = last_child.start
        while s > 1 and at(text, s - 1) ~= "\n" do s -= 1 end
        local lead = string.match(string.sub(text, s, last_child.start - 1), "^[ \t]*") or ""
        if #lead > 0 then indent = lead end
    end
    local back = block.close
    while back > 1 and blank(at(text, back - 1)) do back -= 1 end
    if back > 1 and at(text, back - 1) == "\n" then
        return string.sub(text, 1, back - 1) .. indent .. entry .. "\n" .. string.sub(text, back)
    end
    return string.sub(text, 1, block.close - 1) .. "\n" .. indent .. entry .. "\n" .. string.sub(text, block.close)
end

-- A new bind at the end of the block; a file with none gets one at its end.
function M.with_added(text: string, block: any?, entry: string, last_bind: any?): string
    if not block then
        local tail = if #text == 0 or string.sub(text, -1) == "\n" then "" else "\n"
        return text .. tail .. "\nbinds {\n    " .. entry .. "\n}\n"
    end
    return M.with_child(text, block, entry, last_bind)
end

-- The binds block alone, as niri would read it: what is validated before a
-- file is written, so a mistake is found in a scratch copy.
function M.block_of(text: string): string
    local found = M.scan(text).block
    return if found then string.sub(text, found.start, found["end"] - 1) .. "\n" else ""
end

-- ---- Outputs ---------------------------------------------------------------------

function M.position_line(x: number, y: number): string
    return "position x=" .. math.round(x) .. " y=" .. math.round(y)
end

local function last_of(list: { any }): any return list[#list] end

-- The position replaced where it is written, or added when it is not.
function M.with_position(text: string, output: any, x: number, y: number): string
    local entry = M.position_line(x, y)
    if output.position then
        return string.sub(text, 1, output.position.start - 1) .. entry .. string.sub(text, output.position["end"])
    end
    return M.with_child(text, output, entry, last_of(output.children))
end

-- A flag (a child with no value, like `focus-at-startup`), set or cleared.
function M.with_flag(text: string, output: any, flag: string, on: boolean): string
    local present = nil
    for _, child in output.children do if child.name == flag then present = child break end end
    if on and not present then return M.with_child(text, output, flag, last_of(output.children)) end
    if not on and present then return M.without(text, present) end
    return text
end

-- Variable refresh as off, on or demand: replaced where it is written,
-- added when it is not, removed for off.
function M.with_vrr(text: string, output: any, mode: string): string
    local present = nil
    for _, child in output.children do if child.name == "variable-refresh-rate" then present = child break end end
    local entry = if mode == "demand" then "variable-refresh-rate on-demand=true" else "variable-refresh-rate"
    if mode == "off" then return if present then M.without(text, present) else text end
    if present then return string.sub(text, 1, present.start - 1) .. entry .. string.sub(text, present["end"]) end
    return M.with_child(text, output, entry, last_of(output.children))
end

-- A section for an output the configuration does not mention yet.
function M.with_output(text: string, name: string, x: number, y: number): string
    local tail = if #text == 0 or string.sub(text, -1) == "\n" then "" else "\n"
    return text .. tail .. "\noutput " .. M.quote(name) .. " {\n    " .. M.position_line(x, y) .. "\n}\n"
end

-- Every output section of a file on its own: what is validated before the
-- file is written.
function M.outputs_text(text: string): string
    local out = {}
    for _, item in M.scan(text).items do
        if item.kind == "output" then table.insert(out, string.sub(text, item.start, item["end"] - 1)) end
    end
    return table.concat(out, "\n") .. "\n"
end

-- ---- Startup, rules -----------------------------------------------------------------

function M.spawn_line(command: any, sh: boolean): string
    if sh then return "spawn-sh-at-startup " .. M.quote(command) end
    local words = {}
    for _, w in command do table.insert(words, M.quote(w)) end
    return "spawn-at-startup " .. table.concat(words, " ")
end

function M.rule_block(app_id: string): string
    return "window-rule {\n    match app-id=" .. M.quote(app_id) .. "\n}"
end

-- A number as niri reads it back: no float noise, and always with a point
-- (niri takes `opacity 1.0` and refuses `opacity 1`).
function M.figure(value: number): string
    local rounded = math.round(value * 1000) / 1000
    local text = if rounded == math.floor(rounded) then string.format("%d", rounded) else tostring(rounded)
    return if string.find(text, ".", 1, true) then text else text .. ".0"
end

-- ---- Editing ----------------------------------------------------------------------

-- Several edits to one text, each { start, end, text } against the text as
-- it was read: applied from the last, so none moves another.
function M.spliced(text: string, edits: { any }): string
    local sorted = table.clone(edits)
    table.sort(sorted, function(a, b) return a.start > b.start end)
    local out = text
    for _, e in sorted do out = string.sub(out, 1, e.start - 1) .. e.text .. string.sub(out, e["end"]) end
    return out
end

-- A node replaced by a new line, keeping the semicolon that ended it.
function M.replacing(text: string, node: any, entry: string): any
    local semi = at(text, node["end"] - 1) == ";" and string.sub(entry, -1) ~= ";"
    return { start = node.start, ["end"] = node["end"], text = entry .. (if semi then ";" else "") }
end

-- Whether a node has its line to itself, a comment after it aside.
function M.owns_line(text: string, node: any): boolean
    local s = node.start
    while s > 1 and blank(at(text, s - 1)) do s -= 1 end
    if s > 1 and at(text, s - 1) ~= "\n" then return false end
    local newline = string.find(text, "\n", node["end"], true)
    local rest = string.match(string.sub(text, node["end"], (newline or #text + 1) - 1), "^%s*(.-)%s*$") or ""
    return rest == "" or string.sub(rest, 1, 2) == "//"
end

-- Switched off by commenting out the line when it is the node's own, by
-- slashdash otherwise: a comment would take its neighbours with it.
function M.switching_off(text: string, node: any): any
    local multiline = string.find(string.sub(text, node.start, node["end"] - 1), "\n", 1, true) ~= nil
    local mark = if M.owns_line(text, node) and not multiline then "//" else "/-"
    return { start = node.start, ["end"] = node.start, text = mark }
end

-- The mark taken away, and the space between it and the node with it.
function M.switching_on(item: any): any
    return { start = item.start, ["end"] = item.body_start, text = "" }
end

-- A node removed with its line, without the comment above it: around the
-- startup lines, that comment is often another line switched off.
function M.removing(text: string, node: any): any
    local from, to = node.start, node["end"]
    local line_start = from
    while line_start > 1 and blank(at(text, line_start - 1)) do line_start -= 1 end
    local line_end = to
    while line_end <= #text and blank(at(text, line_end)) do line_end += 1 end
    if (line_start == 1 or at(text, line_start - 1) == "\n") and (line_end > #text or at(text, line_end) == "\n") then
        from = line_start
        to = math.min(#text + 1, line_end + 1)
        -- Set apart by blank lines on both sides, it leaves one of them;
        -- last in the file, it takes the blank line before it.
        local blank_before = from >= 3 and at(text, from - 1) == "\n" and at(text, from - 2) == "\n"
        if blank_before and at(text, to) == "\n" then
            to += 1
        elseif blank_before and to > #text then
            from -= 1
        end
    end
    return { start = from, ["end"] = to, text = "" }
end

-- A new top-level entry on the line after a node like it, indented as that
-- node is; after a blank line when it is a block, as blocks are written.
function M.after(text: string, node: any, entry: string, apart: boolean): any
    local s = node.start
    while s > 1 and at(text, s - 1) ~= "\n" do s -= 1 end
    local indent = string.match(string.sub(text, s, node.start - 1), "^[ \t]*") or ""
    local spot = string.find(text, "\n", node["end"], true) or (#text + 1)
    local lines = {}
    for i, l in string.split(entry, "\n") do table.insert(lines, if i == 1 then l else indent .. l) end
    local below = if apart and spot < #text and at(text, spot + 1) ~= "\n" then "\n" else ""
    return { start = spot, ["end"] = spot, text = "\n" .. (if apart then "\n" else "") .. indent .. table.concat(lines, "\n") .. below }
end

-- A new top-level entry at the end of a file.
function M.appending(text: string, entry: string): any
    local tail = if #text == 0 or string.sub(text, -1) == "\n" then "" else "\n"
    return { start = #text + 1, ["end"] = #text + 1, text = tail .. "\n" .. entry .. "\n" }
end

-- A file as niri would read it on its own, its includes left out: what is
-- validated before it is written (an include names a path relative to the
-- file, and the copy handed to `niri validate` is not where the file is).
function M.standalone(text: string): string
    local edits = {}
    for _, node in M.parse_nodes(M.tokenize(text), 1, false) do
        if node.name == "include" and not node.dropped then
            table.insert(edits, { start = node.start, ["end"] = node["end"], text = "" })
        end
    end
    return M.spliced(text, edits)
end

-- The quoted strings in a span that say `value`: a workspace's name where a
-- bind or a rule names it.
function M.naming(text: string, from: number, to: number, value: string): { any }
    local out = {}
    for _, token in M.tokenize(string.sub(text, from, to - 1)) do
        if token.type == "string" and token.value == value then
            table.insert(out, { start = from + token.start - 1, ["end"] = from + token["end"] - 1 })
        end
    end
    return out
end

return M
