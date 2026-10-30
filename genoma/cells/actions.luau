--!strict
-- Quick actions: a ring of macros around the pointer
-- (cells/actions/ActionsCell.qml at 11bb81e). See docs/design/CELLS.md §20.
--
-- Asked for, never there by itself, and never placed: its key brings it to
-- the point the hand is at, on whichever monitor that is (structure/
-- focus.luau, `seek`), and a pointer too near an edge for the whole ring
-- moves it inward until it fits. The pill in the middle says QUICK
-- ACTIONS, then the name of the macro the pointer points at; up to eight
-- round capsules sit on a circle around it, each tied to the pill by a
-- thread, each the icon of one macro. The ring grows out of the pill and
-- goes back into it: every capsule leaves the pill's edge as a point and
-- travels out to its place on the circle, growing as it goes, its thread
-- drawn out behind it; closing, the icons go, then the capsules come back
-- in, and only then does the pill go.
--
-- Pointing chooses by direction: anywhere in the ring's field, the capsule
-- nearest the pointer's angle lights, and a press there runs it, on the
-- capsule itself or on the way to it. One to eight run the matching macro,
-- the arrows walk the capsules round the ring, Enter runs the one reached,
-- Escape closes. The ring goes first and the macro runs once it has gone,
-- so a step that switches this monitor off does not take the ring's
-- surface from under it.
--
-- With no macro written yet there is one capsule, which opens Settings on
-- the page where they are written.
--
-- Not yet: the sounds of a cell opening and closing (no Genoma cell plays
-- them yet).
local g = require("@genoma")
local colour = require("core/colour")
local config = require("core/config")
local metrics_mod = require("core/metrics")
local performance = require("core/performance")
local theme = require("core/theme")
local timing = require("core/timing")
local typography = require("core/typography")
local actions = require("services/actions")

return {
    new = function(cell: any)
        local function m(): any return cell.metrics() end
        local function f(): number return m().factor end
        local function glyph(): number return 20 * f() end
        -- The ring's capsules and their icons, twice a cell's: they are what
        -- is chosen from, and they are read at a glance (Akusen, 2026-10-18).
        local function capsule(): number return 80 * f() end
        local function capsule_glyph(): number return 40 * f() end
        -- The widest the pill may grow for a name: the ring is laid out for
        -- it, so a long name elides rather than reaching the capsules at its
        -- sides. Wide enough for QUICK ACTIONS, and no wider: the circle's
        -- radius follows it (Akusen, 2026-10-18: a circle, not an ellipse).
        local function pill_max(): number return 216 * f() end
        local function radius_ring(): number return pill_max() / 2 + m().gap + capsule() / 2 end
        local function reach(): number return radius_ring() + capsule() / 2 end

        local function leading(): number return (m().cell_height - glyph()) / 2 end
        local function trailing(): number return 16 * f() end
        local function spacing(): number return 12 * f() end

        -- ---- What it holds ----------------------------------------------------

        local function entries(): { any }
            local ring = actions.ring()
            if #ring == 0 then return { { name = "Write quick actions", icon = "edit", settings = true } } end
            local out = {}
            for _, macro in ring do
                table.insert(out, { name = macro.name, icon = actions.icon_of(macro), settings = false })
            end
            return out
        end

        -- The capsule the pointer points at, and the one the arrows have
        -- reached; 0 for none. The arrows win until the pointer moves to
        -- another capsule.
        local pointed = g.signal(0)
        local marked = g.signal(0)
        local function chosen(): number
            return if marked.value > 0 then marked.value else pointed.value
        end
        local function label(): string
            local i, list = chosen(), entries()
            return if i > 0 and i <= #list then list[i].name else ""
        end

        local function title_font(): { [string]: any }
            return { font = typography.technical(), size = m().font_label, weight = typography.weight_label,
                tracking = typography.label_tracking }
        end
        local function name_font(): { [string]: any }
            return { font = typography.expressive(), size = m().font_title, weight = typography.weight_title, tracking = 0 }
        end
        local function width_of(text: string, font: { [string]: any }): number
            return g.text_width { text = text, font = font.font, size = font.size, weight = font.weight, tracking = font.tracking }
        end
        local function text_room(): number
            return math.max(0, pill_max() - leading() - trailing() - glyph() - spacing())
        end
        local function content_width(): number
            local said = if label() ~= "" then width_of(label(), name_font()) else width_of("QUICK ACTIONS", title_font())
            return math.min(pill_max() - leading() - trailing(), glyph() + spacing() + math.ceil(said))
        end

        -- ---- The ring -----------------------------------------------------------

        -- Out while the cell is placed; drawn until it has gone home.
        local function out(): boolean return cell.placed.value end
        local drawn = g.signal(false)
        local function home(): number return timing.seconds.content_fade / 2 + timing.seconds.close end
        g.watch(function() return cell.placed.value end, function(placed: boolean)
            if placed then
                drawn.value = true
                return
            end
            g.after(home(), function()
                if not g.untracked(function() return cell.placed.value end) then drawn.value = false end
            end)
        end)

        -- Where capsule `i` of `n` sits, from the pill's centre: clockwise
        -- from the top, evenly round the circle.
        local function angle_of(i: number, n: number): number
            return -math.pi / 2 + (i - 1) * 2 * math.pi / math.max(1, n)
        end

        local function pill_width(): number return cell.contracted_width() end
        local function pill_height(): number return cell.contracted_height() end

        -- Where a ray from the pill's centre leaves it. The pill is a
        -- stadium: the straight sides, or one of the caps.
        local function pill_exit(ux: number, uy: number): number
            local r = math.min(cell.corner(), pill_height() / 2)
            local a = math.max(0, pill_width() / 2 - r)
            if math.abs(uy) > 1e-6 then
                local t = r / math.abs(uy)
                if math.abs(t * ux) <= a then return t end
            end
            local b = ux * (if ux >= 0 then a else -a)
            return b + math.sqrt(math.max(0, b * b - a * a + r * r))
        end

        -- The capsule whose direction is nearest the pointer's, the point
        -- from the pill's centre. Inside the pill nothing is pointed at:
        -- that is where the hand starts.
        local function point(dx: number, dy: number)
            local nearest, best = math.huge, 0
            if math.abs(dx) > pill_width() / 2 or math.abs(dy) > pill_height() / 2 then
                local angle = math.atan2(dy, dx)
                local n = #entries()
                for i = 1, n do
                    local apart = math.abs(angle - angle_of(i, n)) % (2 * math.pi)
                    if apart > math.pi then apart = 2 * math.pi - apart end
                    if apart < nearest then nearest, best = apart, i end
                end
            end
            if best ~= g.untracked(function() return pointed.value end) then
                pointed.value = best
                marked.value = 0
            end
        end

        -- Run once the ring has gone, and the host has let it go.
        local pending = false
        local function choose(i: number)
            local list = g.untracked(entries)
            if pending or i < 1 or i > #list then return end
            pending = true
            local entry = list[i]
            cell.visibility.set_invoked(false)
            g.after(cell.withdrawal() + math.max(timing.seconds.close, timing.seconds.reflow), function()
                pending = false
                if entry.settings then actions.write() else actions.run(entry.name) end
            end)
        end

        local function satellite(i: number): any
            local function n(): number return #entries() end
            local function here(): boolean return i <= n() end
            local function ux(): number return math.cos(angle_of(i, n())) end
            local function uy(): number return math.sin(angle_of(i, n())) end
            local function start(): number return pill_exit(ux(), uy()) end
            -- From that point on the pill's edge to its place on the circle.
            local function at(): number return if out() then radius_ring() else start() end
            local function size(): number return if out() then capsule() else 0 end
            local function lit(): boolean return chosen() == i end
            local function moving(): string return if out() then "open" else "retract" end
            local function entry(): any return entries()[i] or { icon = "edit" } end
            local s = reach

            local thread = g.thread {
                overlay = true,
                attach = "corner",
                present = here,
                width = function() return s() * 2 end,
                height = function() return s() * 2 end,
                stroke = metrics_mod.thread,
                crisp = true,
                node = metrics_mod.node_size * 2,
                fill = theme.line,
                color = theme.node,
                from_x = function() return s() + ux() * start() end,
                from_y = function() return s() + uy() * start() end,
                to_x = function() return s() + ux() * (radius_ring() - capsule() / 2) end,
                to_y = function() return s() + uy() * (radius_ring() - capsule() / 2) end,
                -- A thread is a quadratic curve: its bend halfway keeps it
                -- straight, a ray out of the pill.
                bend_x = function() return s() + ux() * (start() + radius_ring() - capsule() / 2) / 2 end,
                bend_y = function() return s() + uy() * (start() + radius_ring() - capsule() / 2) / 2 end,
                growth = function() return if out() then 1 else 0 end,
                transition = { growth = moving },
            }

            local glass = g.capsule {
                overlay = true,
                attach = "corner",
                present = here,
                width = size,
                height = size,
                radius = function() return size() / 2 end,
                offset_x = function() return s() + ux() * at() - size() / 2 end,
                offset_y = function() return s() + uy() * at() - size() / 2 end,
                align = "center",
                justify = "center",
                blur = performance.blurred,
                fill = function()
                    local base = if lit() then theme.lift(theme.cell(), 0.05) else theme.cell()
                    return colour.alpha(base, config.get("cell.opacity", 0.72))
                end,
                rim_top = function() return if lit() then theme.lift(theme.rim(), 0.10) else theme.rim() end,
                rim_bottom = function() return if lit() then theme.lift(theme.line(), 0.06) else theme.line() end,
                transition = {
                    width = moving,
                    height = moving,
                    radius = moving,
                    offset_x = moving,
                    offset_y = moving,
                    fill = "colour",
                    rim_top = "colour",
                    rim_bottom = "colour",
                },
                -- Content arrives once the shape is at size, and leaves
                -- before it shrinks.
                g.icon {
                    width = capsule_glyph,
                    height = capsule_glyph,
                    icon = function() return entry().icon end,
                    gradient_top = function() return if lit() then theme.gradient_top(theme.primary()) else theme.text() end,
                    gradient_bottom = function() return if lit() then theme.gradient_bottom(theme.primary()) else theme.text() end,
                    opacity = function() return if out() then 1 else 0 end,
                    transition = {
                        opacity = function() return if out() then "ring_content" else "content_leave" end,
                    },
                },
            }
            return thread, glass
        end

        -- In the cell's own frame, centred on the pill: the threads, the
        -- capsules, and the field the pointer is given between and around
        -- them, so it can point at one by direction and press on the way.
        local function around(): any
            local s = reach
            local frame: { [any]: any } = {
                overlay = true,
                attach = "corner",
                present = function() return drawn.value end,
                width = function() return s() * 2 end,
                height = function() return s() * 2 end,
                offset_x = function() return pill_width() / 2 - s() end,
                offset_y = function() return pill_height() / 2 - s() end,
            }
            local glasses = {}
            for i = 1, actions.ring_size do
                local thread, glass = satellite(i)
                table.insert(frame, thread)
                table.insert(glasses, glass)
            end
            for _, glass in glasses do table.insert(frame, glass) end
            table.insert(frame, g.box {
                overlay = true,
                attach = "corner",
                width = function() return s() * 2 end,
                height = function() return s() * 2 end,
                on_move = function(x: number, y: number) point(x - s(), y - s()) end,
                -- Leaving, the field goes before the pill: the name stays
                -- the one that was chosen.
                on_hover = function(on: boolean)
                    if not on and g.untracked(function() return cell.placed.value end) then pointed.value = 0 end
                end,
                -- The field is a circle: a press in its corners is a press
                -- outside the ring.
                on_click = function(button: number, x: number, y: number)
                    if button ~= 272 then return end
                    local dx, dy = x - s(), y - s()
                    if dx * dx + dy * dy > s() * s() then
                        require("structure/focus").dismiss()
                        return
                    end
                    local i = g.untracked(function() return pointed.value end)
                    if i > 0 then choose(i) end
                end,
            })
            return g.box(frame)
        end

        -- ---- The pill -------------------------------------------------------------

        local function contracted(): any
            return g.box {
                direction = "row",
                align = "center",
                gap = spacing,
                g.icon {
                    width = glyph,
                    height = glyph,
                    icon = "actions",
                    gradient_top = function() return theme.gradient_top(theme.primary()) end,
                    gradient_bottom = function() return theme.gradient_bottom(theme.primary()) end,
                },
                g.box {
                    width = function() return math.max(0, content_width() - glyph() - spacing()) end,
                    height = function() return m().cell_height end,
                    g.box {
                        overlay = true,
                        attach = "corner",
                        height = function() return m().cell_height end,
                        align = "center",
                        opacity = function() return if label() == "" then 1 else 0 end,
                        transition = { opacity = "content_fade" },
                        g.text {
                            text = "QUICK ACTIONS",
                            color = theme.text,
                            font = function() return title_font().font end,
                            size = function() return title_font().size end,
                            weight = function() return title_font().weight end,
                            tracking = function() return title_font().tracking end,
                            max_width = text_room,
                        },
                    },
                    -- A macro's name is somebody's word, so it is in the
                    -- human voice.
                    g.box {
                        overlay = true,
                        attach = "corner",
                        height = function() return m().cell_height end,
                        align = "center",
                        opacity = function() return if label() ~= "" then 1 else 0 end,
                        transition = { opacity = "content_fade" },
                        g.text {
                            text = label,
                            color = theme.text,
                            font = function() return name_font().font end,
                            size = function() return name_font().size end,
                            weight = function() return name_font().weight end,
                            max_width = text_room,
                        },
                    },
                },
            }
        end

        -- One to eight run the matching capsule; the arrows walk the ring and
        -- Enter runs the capsule reached. Everything else goes on: Escape
        -- closes.
        local function on_key(name: string, _text: string?, mods: { [string]: boolean }): boolean
            if mods.ctrl or mods.alt then return false end
            local n = #g.untracked(entries)
            local digit = tonumber(string.match(name, "^KP_(%d)$") or string.match(name, "^(%d)$") or "")
            if digit and digit >= 1 and digit <= 8 then
                choose(digit)
                return true
            end
            local now = g.untracked(chosen)
            if name == "Right" or name == "Down" or name == "Tab" then
                marked.value = if now >= n or now < 1 then 1 else now + 1
                return true
            end
            if name == "Left" or name == "Up" or name == "ISO_Left_Tab" then
                marked.value = if now <= 1 then n else now - 1
                return true
            end
            if (name == "Return" or name == "KP_Enter") and now > 0 then
                choose(now)
                return true
            end
            return false
        end

        return {
            interactive = false,
            wants_keyboard = true,
            padding_leading = leading,
            padding_trailing = trailing,
            content_width = content_width,
            contracted = contracted,
            around = around,
            surround = function() return { x = reach(), y = reach() } end,
            -- The pill waits for the ring to go home: the icons leave, then
            -- the capsules retract, and the pill goes halfway through that.
            withdrawal = function() return timing.seconds.content_fade / 2 + timing.seconds.close / 2 end,
            on_key = on_key,
        }
    end,
}
