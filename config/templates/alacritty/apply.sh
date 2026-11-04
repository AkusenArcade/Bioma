#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
config_file="$config_dir/alacritty/alacritty.toml"

# alacritty expands ~ in import paths; keep it tilde'd so the path stays portable.
if [[ "$config_dir" == "$HOME"/* ]]; then
    theme_path="~/${config_dir#"$HOME"/}/alacritty/themes/bioma.toml"
else
    theme_path="$config_dir/alacritty/themes/bioma.toml"
fi

mkdir -p "$(dirname "$config_file")"

write_if_changed() {
    local target="$1" tmp="$2"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        mv "$tmp" "$target"
        return
    fi
    if ! cmp -s "$target" "$tmp"; then
        cat "$tmp" >"$target"
    fi
    rm -f "$tmp"
}

if [ ! -f "$config_file" ]; then
    cat >"$config_file" <<EOF
[general]
import = [
    "$theme_path"
]
EOF
    exit 0
fi

tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

if grep -q 'bioma\.toml' "$config_file"; then
    sed -E 's|"themes/bioma.toml"|"'"$theme_path"'"|g' "$config_file" >"$tmp_file"
elif grep -q '^\[general\]' "$config_file"; then
    if grep -q '^import\s*=\s*\[.*\]' "$config_file"; then
        # Single-line array: a sed range would never close on its opening line
        # and would run on to the next "]" (e.g. a [table] header).
        sed -E '/^import\s*=\s*\[/{s|\[\s*\]|["'"$theme_path"'"]|;t;s|\s*\]\s*$|, "'"$theme_path"'"]|}' "$config_file" >"$tmp_file"
    elif grep -q '^import\s*=' "$config_file"; then
        sed '/^import\s*=\s*\[/,/\]/{/\]/s|]|    "'"$theme_path"'",\n]|}' "$config_file" >"$tmp_file"
    else
        sed '/^\[general\]/a import = ["'"$theme_path"'"]' "$config_file" >"$tmp_file"
    fi
else
    sed '1i [general]\nimport = ["'"$theme_path"'"]\n' "$config_file" >"$tmp_file"
fi

# alacritty reads its imports first and the file itself over them, so a
# table the person wrote that the theme also writes ([colors.primary], a
# whole palette of their own) hides the theme: the import was there and the
# terminal stayed Nord (Akusen's laptop, 2026-11-04). Those tables are
# commented out, each line marked so undo.sh puts them back as they were;
# anything else, [colors] itself included, is left alone.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
shadowed="$(grep -E '^\[[^]]+\]' "$here/alacritty.toml" | tr -d ' ' | sort -u | paste -sd'|')"
if [ -n "$shadowed" ]; then
    marked_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    trap 'rm -f "$tmp_file" "$marked_file"' EXIT
    awk -v shadowed="$shadowed" '
        BEGIN { n = split(shadowed, list, "|"); for (i = 1; i <= n; i++) theme[list[i]] = 1 }
        /^[ \t]*\[/ { header = $0; gsub(/[ \t]/, "", header); sub(/#.*/, "", header); hiding = (header in theme) }
        { print (hiding ? "#bioma# " $0 : $0) }
    ' "$tmp_file" >"$marked_file"
    mv "$marked_file" "$tmp_file"
fi

trap - EXIT
write_if_changed "$config_file" "$tmp_file"
