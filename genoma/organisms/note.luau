--!strict
-- A Markdown file, on the desktop (organisms/note/NoteOrganism.qml at
-- 2cafc17). See docs/design/ORGANISMS.md.
--
-- The file's first heading is its title, beside when it was last edited;
-- under it the file as it reads: paragraphs, headings, lists with their
-- open and done boxes, quotes, code, rules. As much as the panel holds,
-- and how many lines are left when it does not. It follows the file as it
-- is edited. Absent when the file cannot be read.
--
-- Not yet: bold, italic, code and struck words inside a line (Genoma sets a
-- text in one face, so they read as plain); the fade at the foot of a page
-- that runs over; the page's crossfade when the file changes.
local g = require("@genoma")
local colour = require("core/colour")
local theme = require("core/theme")
local typography = require("core/typography")

local READ_AT_MOST = 400

-- The marks of a line, taken out: links to their words, the rest to their
-- text.
local function plain(text: string): string
    text = string.gsub(text, "%[%[([^%]|]+)|([^%]]+)%]%]", "%2")
    text = string.gsub(text, "%[%[([^%]]+)%]%]", "%1")
    text = string.gsub(text, "!?%[([^%]]*)%]%([^)]*%)", "%1")
    text = string.gsub(text, "`([^`]+)`", "%1")
    text = string.gsub(text, "%*%*([^*]+)%*%*", "%1")
    text = string.gsub(text, "__([^_]+)__", "%1")
    text = string.gsub(text, "%*([^*%s][^*]*)%*", "%1")
    text = string.gsub(text, "~~([^~]+)~~", "%1")
    return text
end

local function parse(source: string): any
    local lines = string.split(source, "\n")
    local total = #lines
    local n = math.min(#lines, READ_AT_MOST)
    local blocks, title = {}, ""
    local i = 1
    if lines[1] and string.match(lines[1], "^%s*%-%-%-%s*$") then
        for j = 2, n do
            if string.match(lines[j], "^%s*%-%-%-%s*$") then
                i = j + 1
                break
            end
        end
    end
    local paragraph = {}
    local function flush()
        if #paragraph > 0 then table.insert(blocks, { kind = "text", text = plain(table.concat(paragraph, " ")), lines = #paragraph }) end
        paragraph = {}
    end
    while i <= n do
        local line = string.gsub(lines[i], "%s+$", "")
        local trimmed = string.match(line, "^%s*(.-)$") or ""
        if trimmed == "" then
            flush()
        elseif string.sub(trimmed, 1, 3) == "```" then
            flush()
            local code = {}
            i += 1
            while i <= n and string.sub(string.match(lines[i], "^%s*(.-)$") or "", 1, 3) ~= "```" do
                table.insert(code, lines[i])
                i += 1
            end
            table.insert(blocks, { kind = "code", text = table.concat(code, "\n"), lines = #code + 2 })
        elseif string.match(trimmed, "^#+%s") then
            flush()
            local hashes, rest = string.match(trimmed, "^(#+)%s+(.*)$")
            if #hashes == 1 and title == "" and #blocks == 0 then
                title = plain(rest)
            else
                table.insert(blocks, { kind = "heading", text = plain(rest), depth = #hashes, lines = 1 })
            end
        elseif string.match(trimmed, "^%-%-%-+$") or string.match(trimmed, "^%*%*%*+$") or string.match(trimmed, "^___+$") then
            flush()
            table.insert(blocks, { kind = "rule", lines = 1 })
        elseif string.match(line, "^%s*[-*+]%s+") or string.match(line, "^%s*%d+[.)]%s+") then
            flush()
            local lead = string.match(line, "^(%s*)") or ""
            lead = string.gsub(lead, "\t", "    ")
            local body = string.match(line, "^%s*[-*+]%s+(.*)$") or string.match(line, "^%s*%d+[.)]%s+(.*)$") or ""
            local mark = "node"
            local box, rest = string.match(body, "^%[([ xX])%]%s+(.*)$")
            if box then
                mark = if box == " " then "open" else "done"
                body = rest
            end
            table.insert(blocks, { kind = "item", text = plain(body), mark = mark, depth = math.min(#lead // 2, 4), lines = 1 })
        elseif string.sub(trimmed, 1, 1) == ">" then
            flush()
            table.insert(blocks, { kind = "quote", text = plain((string.gsub(trimmed, "^>%s?", ""))), lines = 1 })
        else
            table.insert(paragraph, trimmed)
        end
        i += 1
    end
    flush()
    return { title = title, blocks = blocks, unread = math.max(0, total - n) }
end

return {
    new = function(o: any)
        local function f(): number return o.metrics().factor end
        local function m(): any return o.metrics() end
        local home = g.env("HOME") or ""
        local function path(): string
            local file = string.match(o.entry().file or "", "^%s*(.-)%s*$") or ""
            return if string.sub(file, 1, 1) == "~" then home .. string.sub(file, 2) else file
        end
        -- The file, read again when it changes; a new path is a new reader.
        local source = g.signal(nil :: string?)
        local edited = g.signal(0)
        g.effect(function()
            local p = path()
            if p == "" then
                g.untracked(function() source.value = nil end)
                return
            end
            local reader = g.file { path = p }
            g.effect(function()
                local text = reader.text
                g.untracked(function()
                    source.value = text
                    if text then
                        g.process { command = { "stat", "-c", "%Y", p },
                            on_line = function(line: string) edited.value = tonumber(line) or 0 end }
                    end
                end)
            end)
        end)
        local function readable(): boolean return source.value ~= nil end
        local now = g.signal(os.time())
        g.effect(function()
            if not readable() then return end
            g.timer { every = 60, on_tick = function() now.value = os.time() end }
        end)
        local function when(): string
            if edited.value <= 0 then return "" end
            local minutes = math.max(0, now.value - edited.value) // 60
            if minutes < 1 then return "EDITED JUST NOW" end
            if minutes < 60 then return "EDITED " .. minutes .. " MIN AGO" end
            local hours = minutes // 60
            if hours < 24 then return "EDITED " .. hours .. " H AGO" end
            return "EDITED " .. hours // 24 .. " D AGO"
        end
        local parsed = g.computed(function(): any return parse(source.value or "") end)
        local function title(): string
            local t = parsed.value.title
            if readable() and t ~= "" then return t end
            local p = path()
            if p == "" then return "Note" end
            local base = string.match(p, "([^/]+)$") or p
            return (string.gsub(base, "%.[mM][dD]$", ""))
        end
        local function reason(): string
            if string.match(o.entry().file or "", "^%s*$") then return "No file chosen. Choose one under Settings → Organisms → Note → File." end
            return "This file cannot be read."
        end
        local function header_height(): number return 22 * f() end
        local function page_top(): number return header_height() + 12 * f() end
        local function page_height(): number return o.height() - page_top() end
        local function size(): number return math.round(14 * f()) end
        local function spacing(): number return 6 * f() end

        -- What the page holds, a whole block or none, and what is left over.
        local function indent(b: any): number return (b.depth or 0) * 14 * f() end
        local function text_x(b: any): number
            if b.kind == "item" then return indent(b) + 22 * f() end
            if b.kind == "quote" then return 12 * f() end
            return 0
        end
        local function height_of(b: any, first: boolean): number
            local lead = if b.kind == "heading" and not first then 4 * f() else 0
            if b.kind == "rule" then return lead + 9 * f() end
            if b.kind == "code" then
                local lines = #string.split(b.text, "\n")
                return lead + lines * m().font_meta * 1.3 + 16 * f()
            end
            return lead + g.text_height { text = b.text, font = typography.expressive(), size = size(), width = o.width() - text_x(b) }
        end
        local fitted = g.computed(function(): any
            local list = parsed.value.blocks
            local room = page_height()
            local shown, used, hidden = {}, 0, parsed.value.unread
            for i, b in list do
                local h = height_of(b, i == 1)
                local next = used + (if #shown > 0 then spacing() else 0) + h
                if next <= room and hidden == parsed.value.unread then
                    table.insert(shown, { i = i, b = b, y = used + (if #shown > 0 then spacing() else 0), h = h })
                    used = next
                else
                    hidden += b.lines or 1
                end
            end
            return { shown = shown, hidden = hidden }
        end)

        local function block(item: () -> any): any
            local function b(): any return item().b end
            local function kind(): string return b().kind end
            local function lead(): number return if kind() == "heading" and item().i > 1 then 4 * f() else 0 end
            local function muted(): boolean
                local x = b()
                return x.kind == "quote" or (x.kind == "heading" and (x.depth or 0) > 2) or x.mark == "done"
            end
            return g.box {
                overlay = true,
                attach = "corner",
                offset_y = function() return item().y end,
                width = o.width,
                height = function() return item().h end,
                -- A rule.
                g.capsule {
                    overlay = true, attach = "corner", present = function() return kind() == "rule" end,
                    offset_y = function() return 4 * f() end, width = o.width, height = 1, crisp = true,
                    fill = theme.line, rim_top = "#00000000", rim_bottom = "#00000000",
                },
                -- Code, in a well.
                g.capsule {
                    overlay = true, attach = "corner", present = function() return kind() == "code" end,
                    width = o.width, height = function() return item().h end,
                    radius = function() return m().radius_well end,
                    fill = function() return colour.alpha(theme.lift(theme.background(), -0.01), 0.8) end,
                    rim_top = "#00000000", rim_bottom = "#00000000",
                    padding_x = function() return 10 * f() end, padding_y = function() return 8 * f() end,
                    direction = "column", align = "start", justify = "start",
                    g.text { text = function() return if kind() == "code" then b().text else "" end, color = theme.text_muted,
                        font = typography.technical, size = function() return m().font_meta end,
                        max_width = function() return o.width() - 20 * f() end },
                },
                -- A list's mark: a node, an open box, a done one.
                g.box {
                    overlay = true, attach = "corner", present = function() return kind() == "item" end,
                    offset_x = function() return indent(b()) end,
                    width = function() return 12 * f() end, height = function() return 18 * f() end,
                    align = "center", justify = "center",
                    g.capsule { present = function() return b().mark == "node" end,
                        width = function() return 4 * f() end, height = function() return 4 * f() end,
                        fill = theme.node, rim_top = "#00000000", rim_bottom = "#00000000" },
                    g.capsule { present = function() return b().mark == "open" end,
                        width = function() return 11 * f() end, height = function() return 11 * f() end,
                        fill = "#00000000", rim_top = theme.line, rim_bottom = theme.line },
                    g.capsule { present = function() return b().mark == "done" end,
                        width = function() return 12 * f() end, height = function() return 12 * f() end,
                        fill = function() return theme.gradient_top(theme.primary()) end,
                        fill_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                        rim_top = "#00000000", rim_bottom = "#00000000" },
                },
                -- A quote's bar.
                g.capsule {
                    overlay = true, attach = "corner", present = function() return kind() == "quote" end,
                    width = function() return 2 * f() end, height = function() return item().h end,
                    radius = 0, fill = theme.line, rim_top = "#00000000", rim_bottom = "#00000000",
                },
                g.text {
                    overlay = true, attach = "corner",
                    present = function() return kind() ~= "rule" and kind() ~= "code" end,
                    offset_x = function() return text_x(b()) end,
                    offset_y = lead,
                    text = function() return b().text or "" end,
                    color = function() return if muted() then theme.text_muted() else theme.text() end,
                    font = typography.expressive, size = size,
                    weight = function() return if kind() == "heading" then 700 else 400 end,
                    italic = function() return kind() == "quote" end,
                    wrap = true,
                    max_width = function() return o.width() - text_x(b()) end,
                },
            }
        end

        local function meta(text: () -> string, color: any): any
            return g.text { text = text, color = color, font = typography.technical, size = function() return m().font_meta end,
                tracking = typography.label_tracking }
        end

        return {
            present = readable,
            node = function()
                return g.box {
                    width = o.width,
                    height = o.height,
                    g.box {
                        overlay = true, attach = "corner",
                        width = o.width, height = header_height,
                        direction = "row", align = "center", justify = "between",
                        g.text { text = title, color = theme.text, font = typography.expressive,
                            size = function() return math.round(15 * f()) end, weight = 700,
                            max_width = function() return o.width() * 0.6 end },
                        meta(function() return if readable() then when() else "" end, theme.text_faint),
                    },
                    g.box {
                        overlay = true, attach = "corner", present = function() return not readable() end,
                        offset_y = page_top,
                        g.text { text = reason, color = theme.text_faint, font = typography.expressive, size = size,
                            italic = true, wrap = true, max_width = o.width },
                    },
                    g.box {
                        overlay = true, attach = "corner", present = readable,
                        offset_y = page_top,
                        width = o.width, height = page_height,
                        g.text {
                            overlay = true, attach = "corner",
                            present = function() return #parsed.value.blocks == 0 end,
                            text = "Nothing written yet.", color = theme.text_faint, font = typography.expressive,
                            size = size, italic = true,
                        },
                        g.each {
                            overlay = true, attach = "corner",
                            items = function() return fitted.value.shown end,
                            key = function(it: any) return tostring(it.i) end,
                            row = block,
                        },
                        g.box {
                            overlay = true, attach = "corner",
                            present = function() return fitted.value.hidden > 0 end,
                            width = o.width, height = page_height,
                            direction = "row", align = "end", justify = "end",
                            meta(function()
                                local h = fitted.value.hidden
                                return h .. " MORE " .. (if h == 1 then "LINE" else "LINES")
                            end, theme.text_faint),
                        },
                    },
                }
            end,
        }
    end,
}
