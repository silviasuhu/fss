#!/usr/bin/env bash
# Installer for fss. Safe to re-run.
#   ./install.sh             install
#   ./install.sh --uninstall remove the source line added by install
set -euo pipefail

MODE=install
case "${1:-}" in
    --uninstall|-u) MODE=uninstall ;;
    --help|-h)
        echo "usage: $0 [--uninstall]"
        exit 0
        ;;
    "") ;;
    *)
        echo "unknown argument: $1" >&2
        exit 2
        ;;
esac

resolve_path() {
    local target="$1"
    while [ -L "$target" ]; do
        target=$(readlink "$target")
    done
    cd "$(dirname "$target")" >/dev/null 2>&1 && pwd
}

REPO_DIR=$(resolve_path "${BASH_SOURCE[0]}")
FSS_SCRIPT="$REPO_DIR/fss.sh"

if [[ ! -f "$FSS_SCRIPT" ]]; then
    echo "error: cannot find fss.sh next to install.sh (looked in $REPO_DIR)" >&2
    exit 1
fi

# --- Dependency check (skip on uninstall) ---------------------------

missing=()
if [[ "$MODE" == "install" ]]; then
    for dep in fzf bat jq; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done
fi

if (( ${#missing[@]} > 0 )); then
    echo "error: missing required commands: ${missing[*]}" >&2
    case "$(uname -s)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                echo "install with: brew install ${missing[*]}" >&2
            else
                echo "install Homebrew (https://brew.sh) then: brew install ${missing[*]}" >&2
            fi
            ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                echo "install with: sudo apt-get install ${missing[*]}" >&2
            else
                echo "see: https://github.com/junegunn/fzf https://github.com/sharkdp/bat https://github.com/jqlang/jq" >&2
            fi
            ;;
        *)
            echo "see: https://github.com/junegunn/fzf https://github.com/sharkdp/bat https://github.com/jqlang/jq" >&2
            ;;
    esac
    exit 1
fi

# --- Configure shell rc files ----------------------------------------

case "$(uname -s)" in
    Darwin) BASH_RC="$HOME/.bash_profile" ;;
    *)      BASH_RC="$HOME/.bashrc" ;;
esac
ZSH_RC="$HOME/.zshrc"

SOURCE_LINE="source \"$FSS_SCRIPT\""

install_into() {
    local rc="$1"
    touch "$rc"
    if grep -Fq "fss.sh" "$rc"; then
        echo "already installed: $rc"
        return
    fi
    {
        printf '\n# fss\n%s\n' "$SOURCE_LINE"
    } >> "$rc"
    echo "added source line to: $rc"
}

uninstall_from() {
    local rc="$1"
    if [[ ! -f "$rc" ]] || ! grep -Fq "fss.sh" "$rc"; then
        echo "not present: $rc"
        return
    fi
    local tmp
    tmp=$(mktemp)
    # Drop the `# fss` marker line and the `source ".../fss.sh"` line
    # immediately after it (the two-line block written by install_into).
    awk '
        /^# fss$/ { skip=1; next }
        skip == 1 { skip=0; next }
        { print }
    ' "$rc" > "$tmp"
    mv "$tmp" "$rc"
    echo "removed source line from: $rc"
}

if [[ "$MODE" == "uninstall" ]]; then
    uninstall_from "$BASH_RC"
    uninstall_from "$ZSH_RC"
    echo
    echo "Uninstalled. Open a new shell to drop the keybinding."
else
    install_into "$BASH_RC"
    install_into "$ZSH_RC"
    echo
    echo "Done. Open a new shell or run: source <your-rc-file>"
    echo "Press Ctrl+E to launch fss (override with FSS_KEYBIND_BASH/_ZSH)."
fi
