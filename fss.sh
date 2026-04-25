#!/usr/bin/env bash
# Compatible with: bash, zsh

# --- Resolve script directory ---------------------------------------

# Resolve script directory in bash + zsh (readlink -f not portable on macOS)
resolve_path() {
    local target="$1"
    while [ -L "$target" ]; do
        target=$(readlink "$target")
    done
    cd "$(dirname "$target")" >/dev/null 2>&1 && pwd
}

# Detect shell & fix BASH_SOURCE for zsh
if [ -n "$ZSH_VERSION" ]; then
    # zsh does not populate BASH_SOURCE
    setopt function_argzero
    BASH_SOURCE=${(%):-%x}
fi

SCRIPT_DIR=$(resolve_path "$BASH_SOURCE")

# ----------------------------------------------------------------------

FSS_CONF_FILE="$HOME/.fss.conf"

if [[ ! -e "$FSS_CONF_FILE" ]]; then
    echo "${SCRIPT_DIR}/commands/*" > "$FSS_CONF_FILE"
    mkdir -p "${SCRIPT_DIR}/commands"
fi

# --- Functions ---------------------------------------------------------

__getAllCommandFilesFromConfig() {
    local confFile="${1:-$FSS_CONF_FILE}"
    if [[ ! -e "$confFile" ]]; then
        echo "${SCRIPT_DIR}/commands/*" > "$confFile"
        mkdir -p "${SCRIPT_DIR}/commands"
    fi

    local commandFiles=()
    while IFS= read -r line; do
        commandFiles+=("$line")
    done < "$confFile"

    printf '%s\n' "${commandFiles[@]}"
}

__expandGlob() {
    # Expand a glob pattern into matching file paths (one per line) without eval.
    # Works in bash and zsh; nullglob equivalent — no match means no output.
    local pattern="$1"
    if [ -n "$ZSH_VERSION" ]; then
        setopt local_options null_glob
        local matches=(${~pattern})
        (( ${#matches} > 0 )) && printf '%s\n' "${matches[@]}"
    else
        local _restoreNullglob=0
        shopt -q nullglob || _restoreNullglob=1
        shopt -s nullglob
        local matches=($pattern)
        (( _restoreNullglob )) && shopt -u nullglob
        (( ${#matches[@]} > 0 )) && printf '%s\n' "${matches[@]}"
    fi
}

__warnDuplicateCommandNames() {
    # Read (file<TAB>name) pairs from stdin, sort by name, warn on duplicates.
    sort -t $'\t' -k2,2 -k1,1 | awk -F'\t' '
        $2 == prev_name {
            printf "fss: warning: command %s defined in both %s and %s; last wins\n", $2, prev_file, $1 > "/dev/stderr"
        }
        { prev_name = $2; prev_file = $1 }
    '
}

__pushAllCommandsToTmpFile() {
    local commandFiles=()
    local tmpFile

    for pattern in "$@"; do
        while IFS= read -r f; do
            [[ -f "$f" ]] && commandFiles+=("$f")
        done < <(__expandGlob "$pattern")
    done

    [[ ${#commandFiles[@]} -eq 0 ]] && return 1

    # Warn on duplicate command names across files
    {
        for f in "${commandFiles[@]}"; do
            jq -r --arg f "$f" '.commands? | keys[]? | "\($f)\t\(.)"' "$f" 2>/dev/null
        done
    } | __warnDuplicateCommandNames

    tmpFile=$(mktemp -t fss_commands.XXXXXX) || return 1
    jq -s 'reduce .[] as $item ({}; . * $item)' "${commandFiles[@]}" > "$tmpFile"

    echo "$tmpFile"
}

__getCommandFromJsonFile() {
    local cmdName=$1 jsonFile=$2
    [[ -z $cmdName || -z $jsonFile ]] && return 1
    jq -r ".commands.\"$cmdName\"" "$jsonFile"
}

__trim() {
    # Strip leading and trailing whitespace; preserve internal whitespace.
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Literal substring replacement. Walks the string with prefix/suffix
# stripping so neither regex metachars on the search side nor sed-style
# specials (&, \) — including bash 5.2's `patsub_replacement` — get
# interpreted in the replacement.
__replace() {
    local str="$1" search="$2" replace="$3"
    [[ -z "$search" ]] && { printf '%s' "$str"; return; }
    local out=""
    while [[ "$str" == *"$search"* ]]; do
        out+="${str%%"$search"*}$replace"
        str="${str#*"$search"}"
    done
    printf '%s' "$out$str"
}

reportCmdTiming() {
    local timestampInit=$(date +%s)
    local dateInit=$(date)
    echo "Started '$dateInit'"

    eval "$@"
    local res=$?

    echo "reportCmdTiming REPORT:"
    echo "    Started '$dateInit'"
    echo "    Finished '$(date)'"
    local timestampEnd=$(date +%s)
    echo "    Elapsed $((timestampEnd - timestampInit)) seconds."
    echo "    Result: $res"

    return $res
}

ringBellAndSetExitCode() {
    tput bel
    return "${1:-1}"
}

fss() {
    local fssPath listOfFilesWithCommands fileWithAllCommands cmdPreview cmdName
    local cmdJson cmd preChecks parameters

    fssPath=$(resolve_path "$BASH_SOURCE")

    listOfFilesWithCommands=($(__getAllCommandFilesFromConfig "$FSS_CONF_FILE"))
    fileWithAllCommands=$(__pushAllCommandsToTmpFile "${listOfFilesWithCommands[@]}")

    # Ask the command to the user
    cmdPreview="jq -C --tab '.commands.\"{}\"' $fileWithAllCommands"
    cmdName=$(jq -r '.commands | keys[]' "$fileWithAllCommands" | \
              fzf --height=50% --no-multi --preview="$cmdPreview" \
                  --preview-window=right:60%:wrap) || { rm -f "$fileWithAllCommands"; return; }

    # Fetch the command configuration
    cmdJson=$(__getCommandFromJsonFile "$cmdName" "$fileWithAllCommands")
    cmd=$(jq -r .cmd <<<"$cmdJson")

    preChecks=$(jq -r '.pre_checks[]?' <<<"$cmdJson")
    while IFS= read -r preCheckName; do
        [[ -z "$preCheckName" ]] && break
        local preCheckCmd preCheckDesc
        preCheckCmd=$(jq -r --arg key "$preCheckName" '.pre_checks[$key].cmd // empty' "$fileWithAllCommands")
        preCheckDesc=$(jq -r --arg key "$preCheckName" '.pre_checks[$key].description // empty' "$fileWithAllCommands")
        if ! eval "$preCheckCmd"; then
            echo "fss: pre-check '$preCheckName' failed${preCheckDesc:+ — $preCheckDesc}" >&2
            rm -f "$fileWithAllCommands"
            return 1
        fi
    done <<< "$preChecks"

    parameters=$(jq -r '.parameters? | keys? | .[]?' <<<"$cmdJson")
    while IFS= read -r paramName; do
        [[ -z "$paramName" ]] && break

        paramConf=$(jq -r --arg key "$paramName" '.parameters[$key]' <<<"$cmdJson")

        type=$(jq -r '.type // "input"' <<< "$paramConf")
        description=$(jq -r '.description // ""' <<< "$paramConf")
        body=$(jq -r '.body // "<<VALUE>>"' <<< "$paramConf")
        optional=$(jq -r '.optional // "false"' <<< "$paramConf")
        default=$(jq -r '.default // ""' <<< "$paramConf")

        if [[ "$type" == "query" ]]; then
            queryCmd=$(jq -r '.query_cmd' <<<"$paramConf")
            queryPreview=$(jq -r .element_preview <<<"$paramConf")
            [[ "$optional" == "true" ]] && queryCmd="$queryCmd; echo 'NONE'"

            value=$(eval "$queryCmd" | fzf --height 50% --query "$default" \
                    --no-multi --preview "$queryPreview" \
                    --preview-window=right:60%:wrap) || { rm -f "$fileWithAllCommands"; return; }

            value=$(__trim "$value")

            if [[ "$value" == "NONE" ]]; then
                finalValue=""
            else
                # finalValue="${body//<<VALUE>>/$value}"
                finalValue=$(__replace "$body" '<<VALUE>>' "$value")
            fi

        elif [[ "$type" == "fix" ]]; then
            finalValue="$body"

        elif [[ "$type" == "input" ]]; then
            value=$(fzf --print-query --header="Type '$paramName'." \
                        --prompt="> " --disabled --query="$default" \
                        --preview="echo '$description'" \
                        --height=5% --no-info < /dev/null)
            finalValue=$(__replace "$body" '<<VALUE>>' "$value")
        fi

        cmd=$(__replace "$cmd" "<<$paramName>>" "$finalValue")
    done <<< "$parameters"

    local cmdBell cmdStatistics
    cmdBell=$(jq -r .bell <<<"$cmdJson")
    cmdStatistics=$(jq -r .statistics <<<"$cmdJson")

    [[ $cmdStatistics == "true" ]] && cmd="reportCmdTiming $cmd"
    [[ $cmdBell == "true" ]] && cmd="$cmd; ringBellAndSetExitCode \$?;"

    # Insert back into command line (bash + zsh)
    if [ -n "$ZSH_VERSION" ]; then
        print -z -- "$cmd"
    else
        # Inside a `bind -x` keybinding, bash sets READLINE_LINE before
        # invoking the function, so we can rewrite the prompt in place.
        # Outside that context (called as a plain function), READLINE_LINE
        # has no effect — fall back to printing the command.
        if [[ -v READLINE_LINE ]]; then
            READLINE_LINE="$cmd"
            READLINE_POINT=${#READLINE_LINE}
        else
            printf '%s\n' "$cmd"
        fi
    fi

    rm -f "$fileWithAllCommands"
}

# --- Keybindings -------------------------------------------------------
# Override defaults by exporting FSS_KEYBIND_BASH and/or FSS_KEYBIND_ZSH
# before sourcing this file. Note that the default Ctrl+E shadows
# Readline's `end-of-line` binding in bash and `end-of-line` in zsh.
if [ -n "$ZSH_VERSION" ]; then
    bindkey -s "${FSS_KEYBIND_ZSH:-^E}" 'fss\n'
else
    bind -x "\"${FSS_KEYBIND_BASH:-\\C-e}\":fss"
fi
