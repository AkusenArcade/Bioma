#!/usr/bin/env bash
# Bioma's addition: qt5ct and qt6ct use the colour scheme their own config
# names, so rendering the scheme is not enough — [Appearance] is pointed at it.
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

point() {
    local tool="$1"
    local conf="$config_home/$tool/$tool.conf"
    local scheme="$config_home/$tool/colors/bioma.conf"
    [ -f "$scheme" ] || return 0
    mkdir -p "$(dirname "$conf")"
    [ -f "$conf" ] || printf '[Appearance]\n' >"$conf"
    grep -q '^\[Appearance\]' "$conf" || printf '\n[Appearance]\n' >>"$conf"

    local tmp
    tmp="$(mktemp "$conf.tmp.XXXXXX")"
    awk -v scheme="$scheme" '
        /^\[/ {
            if (inside && !done) { print "color_scheme_path=" scheme; print "custom_palette=true"; done = 1 }
            inside = ($0 == "[Appearance]")
            print; next
        }
        inside && /^(color_scheme_path|custom_palette)=/ { next }
        { print }
        END { if (inside && !done) { print "color_scheme_path=" scheme; print "custom_palette=true" } }
    ' "$conf" >"$tmp"
    if cmp -s "$conf" "$tmp"; then rm -f "$tmp"; else cat "$tmp" >"$conf"; rm -f "$tmp"; fi
}

point qt5ct
point qt6ct
