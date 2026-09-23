#!/usr/bin/env bash
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

# Bioma's addition: unpoint qtXct's [Appearance] if it points at Bioma's scheme.
for tool in qt5ct qt6ct; do
    conf="$config_home/$tool/$tool.conf"
    [ -f "$conf" ] || continue
    if grep -q "^color_scheme_path=.*/colors/bioma\.conf$" "$conf"; then
        tmp="$(mktemp "$conf.tmp.XXXXXX")"
        grep -v -e '^color_scheme_path=.*/colors/bioma\.conf$' -e '^custom_palette=true$' "$conf" >"$tmp" || true
        cat "$tmp" >"$conf"
        rm -f "$tmp"
    fi
done

rm -f -- "$config_home/qt5ct/colors/bioma.conf" "$config_home/qt6ct/colors/bioma.conf"
