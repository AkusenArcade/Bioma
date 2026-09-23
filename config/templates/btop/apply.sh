#!/usr/bin/env bash
set -euo pipefail

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/btop/btop.conf"

# Bioma: btop reads a partial config and fills the rest with its defaults when
# it next saves, so a missing one is written with the theme alone.
if [ ! -f "$config_file" ]; then
    mkdir -p "$(dirname "$config_file")"
    printf 'color_theme = "bioma"\n' >"$config_file"
fi

write_if_changed() {
    local target="$1" tmp="$2"
    if ! cmp -s "$target" "$tmp"; then
        cat "$tmp" >"$target"
    fi
    rm -f "$tmp"
}

if grep -qE '^color_theme\s*=\s*"bioma"' "$config_file"; then
    :
elif grep -qE '^color_theme\s*=' "$config_file"; then
    tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    sed -E 's/^color_theme\s*=.*/color_theme = "bioma"/' "$config_file" >"$tmp_file"
    write_if_changed "$config_file" "$tmp_file"
else
    [ -s "$config_file" ] && [ -n "$(tail -c1 "$config_file")" ] && echo >>"$config_file"
    echo 'color_theme = "bioma"' >>"$config_file"
fi

if pgrep -x btop >/dev/null; then
    pkill -SIGUSR2 -x btop
fi
