#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel"
config_file="$config_dir/config.toml"
theme_file="$config_dir/bioma.toml"

if [ -f "$config_file" ]; then
    tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    trap 'rm -f "$tmp_file"' EXIT
    awk '
        {
            original = $0
            gsub(/"bioma\.toml"[[:space:]]*,[[:space:]]*/, "")
            gsub(/,[[:space:]]*"bioma\.toml"/, "")
            gsub(/"bioma\.toml"/, "")
            # Drop a line that held only the bioma entry (multi-line arrays).
            if ($0 != original && $0 ~ /^[[:space:]]*$/)
                next
            print
        }
    ' "$config_file" >"$tmp_file"
    if ! cmp -s "$config_file" "$tmp_file"; then
        cat "$tmp_file" >"$config_file"
    fi
fi

rm -f -- "$theme_file"
