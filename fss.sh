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
    if [[ ! -e "$FSS_CONF_FILE" ]]; then
        echo "${SCRIPT_DIR}/commands/*" > "$FSS_CONF_FILE"
        mkdir -p "${SCRIPT_DIR}/commands"
    fi

    local commandFiles=()
    while IFS= read -r line; do
        commandFiles+=("$line")
    done < "$FSS_CONF_FILE"

    printf '%s\n' "${commandFiles[@]}"
}

__pushAllCommandsToTmpFile() {
    local commandFiles=()
    local tmpFile=/tmp/fss_commands.json

    for file in "$@"; do
        # Expand globs (this works in both bash and zsh)
        for f in $(eval echo "$file"); do
            [[ -f "$f" ]] && commandFiles+=("$f")
        done
    done

    # If no valid files found, return error
    [[ ${#commandFiles[@]} -eq 0 ]] && return 1

    # Remove old tmp file
    rm -f "$tmpFile"

    # Merge JSON files
    jq -s 'reduce .[] as $item ({}; . * $item)' "${commandFiles[@]}" > "$tmpFile"

    echo "$tmpFile"
}

__getCommandFromJsonFile() {
    local cmdName=$1 jsonFile=$2
    [[ -z $cmdName || -z $jsonFile ]] && return 1
    jq -r ".commands.\"$cmdName\"" "$jsonFile"
}

__trim() {
    echo "$1" | xargs
}

# Safe replacement using printf
__replace() {
    local str="$1"
    local search="$2"
    local replace="$3"

    # Escape search for use in sed (safe even with special chars)
    local escaped_search
    escaped_search=$(printf '%s\n' "$search" | sed 's/[][\/.^$*]/\\&/g')

    # Use sed to do the replacement safely
    printf '%s\n' "$str" | sed "s|$escaped_search|$replace|g"
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
                  --preview-window=right:60%:wrap) || return

    # Fetch the command configuration
    cmdJson=$(__getCommandFromJsonFile "$cmdName" "$fileWithAllCommands")
    cmd=$(echo "$cmdJson" | jq -r .cmd)

    preChecks=$(echo "$cmdJson" | jq -r '.pre_checks[]?')
    for preCheckName in $preChecks; do
        preCheckJson=$(jq -r ".pre_checks.\"$preCheckName\"" "$fileWithAllCommands")
        preCheckCmd=$(echo "$preCheckJson" | jq -r .cmd)
        eval "$preCheckCmd" || return 1
    done

    parameters=$(echo "$cmdJson" | jq -r '.parameters? | keys? | .[]?')
    while IFS= read -r paramName; do
        echo "0 $paramName" >> /tmp/debug.log

        paramConf=$(echo "$cmdJson" | jq -r ".parameters.\"$paramName\"")

        type=$(echo "$paramConf" | jq -r '.type // "input"')
        echo "1 $type" >> /tmp/debug.log
        description=$(echo "$paramConf" | jq -r '.description // ""')
        echo "2 $description" >> /tmp/debug.log
        body=$(echo "$paramConf" | jq -r '.body // "<<VALUE>>"')
        echo "3 $body" >> /tmp/debug.log
        optional=$(echo "$paramConf" | jq -r '.optional // "false"')
        echo "4 $optional" >> /tmp/debug.log
        default=$(echo "$paramConf" | jq -r '.default // ""')
        echo "5 $default" >> /tmp/debug.log

        if [[ "$type" == "query" ]]; then
            queryCmd=$(echo "$paramConf" | jq -r .query_cmd)
            queryPreview=$(echo "$paramConf" | jq -r .element_preview)
            [[ "$optional" == "true" ]] && queryCmd="$queryCmd; echo 'NONE'"

            value=$(eval "$queryCmd" | fzf --height 50% --query "$default" \
                    --no-multi --preview "$queryPreview" \
                    --preview-window=right:60%:wrap) || return

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
            echo "6 $paramName" >> /tmp/debug.log
            value=$(fzf --print-query --header="Type '$paramName'." \
                        --prompt="> " --phony --query="$default" \
                        --preview="echo '$description'" \
                        --height=5% --no-info < /dev/null)
            echo "7 $paramName" >> /tmp/debug.log
            echo "8 $value" >> /tmp/debug.log
            echo "9 $body" >> /tmp/debug.log
            finalValue=$(__replace "$body" '<<VALUE>>' "$value")
            echo "10 $finalValue" >> /tmp/debug.log
        fi

        cmd=$(__replace "$cmd" "<<$paramName>>" "$finalValue")
        echo "11 $cmd" >> /tmp/debug.log
    done <<< "$parameters"

    echo "F $cmd" >> /tmp/debug.log
    local cmdBell cmdStatistics
    cmdBell=$(echo "$cmdJson" | jq -r .bell)
    cmdStatistics=$(echo "$cmdJson" | jq -r .statistics)

    [[ $cmdStatistics == "true" ]] && cmd="reportCmdTiming $cmd"
    [[ $cmdBell == "true" ]] && cmd="$cmd; ringBellAndSetExitCode \$?;"

    # Insert back into command line (bash + zsh)
    if [ -n "$ZSH_VERSION" ]; then
        # BUFFER="$cmd"
        # CURSOR=${#BUFFER}
        print -z -- "$cmd"
    else
        READLINE_LINE="$cmd"
        READLINE_POINT=${#READLINE_LINE}
    fi
}

# --- Keybindings -------------------------------------------------------
if [ -n "$ZSH_VERSION" ]; then
    bindkey -s '^E' 'fss\n'
else
    bind -x '"\C-e":fss'
fi
