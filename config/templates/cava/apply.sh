#!/usr/bin/env bash
set -euo pipefail

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/cava/config"

# Bioma: no config is cava's defaults, and a file holding only the theme is
# still its defaults — so a missing one is written rather than reported.
if [ ! -f "$config_file" ]; then
    mkdir -p "$(dirname "$config_file")"
    printf '[color]\ntheme = "bioma"\n' >"$config_file"
fi

write_if_changed() {
    local target="$1" tmp="$2"
    if ! cmp -s "$target" "$tmp"; then
        cat "$tmp" >"$target"
    fi
    rm -f "$tmp"
}

if grep -q '^\[color\]' "$config_file"; then
    if sed -n '/^\[color\]/,/^\[/p' "$config_file" | grep -qE '^theme\s*=\s*"bioma"'; then
        :
    elif sed -n '/^\[color\]/,/^\[/p' "$config_file" | grep -qE '^theme\s*='; then
        tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
        sed -E '/^\[color\]/,/^\[/{s/^theme\s*=.*/theme = "bioma"/}' "$config_file" >"$tmp_file"
        write_if_changed "$config_file" "$tmp_file"
    else
        tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
        sed '/^\[color\]/a theme = "bioma"' "$config_file" >"$tmp_file"
        write_if_changed "$config_file" "$tmp_file"
    fi
else
    printf '\n[color]\ntheme = "bioma"\n' >>"$config_file"
fi

if pgrep -x cava >/dev/null; then
    if ! pgrep -ax cava | grep -q -- '-p.*stdin'; then
        pkill -USR1 -x cava || true
    fi
fi
