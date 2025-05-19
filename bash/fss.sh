# Binds Ctrl+j to get a command from AI and Ctrl+k to select a command from the precustomized list

FSS_CONF_FILE="$HOME/.fss.conf"

if [[ ! -e "$FSS_CONF_FILE" ]]; then
    FSS_ROOT_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
    echo "${FSS_ROOT_DIR}/commands/*" > $FSS_CONF_FILE
    mkdir "${FSS_ROOT_DIR}/commands"
fi

fss() {

    local fssPath listOfFilesWithCommands fileWithAllCommands cmdPreview cmdName cmdJson cmd preChecks parameters

    # Load all the .sh files from the ../lib directory
    fssPath=$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" >/dev/null 2>&1 && pwd )
    while IFS= read -r -d '' lib; do
        [[ -e "${lib}" && ! -d "${lib}" ]] || continue
        source "${lib}"
    done < <( {
        find "${fssPath}/../lib/" -type f \( -name '*.sh' -o	-name '*.bash' \) -print0 2>/dev/null
    } )

    # Merge all commands into a temporal file
    listOfFilesWithCommands=$(__getAllCommandFilesFromConfig "$FSS_CONF_FILE")
    fileWithAllCommands=$(__pushAllCommandsToTmpFile "${listOfFilesWithCommands[@]}")

    # Ask for the command to run unless we already know it
    cmdPreview="jq -C --tab '.commands.\"{}\"' $fileWithAllCommands"
    cmdName=$(jq -r '.commands | keys[]' "$fileWithAllCommands" | fzf --height=50% --no-multi --preview="$cmdPreview" --preview-window=right:60%:wrap ) || return

    cmdJson=$(__getCommandFromJsonFile "$cmdName" "$fileWithAllCommands")
    cmd=$(echo "$cmdJson" | jq -r .cmd)

    # Execute preChecks
    preChecks=$(echo "$cmdJson" | jq -r '.pre_checks[]?')
    for preCheckName in $preChecks
    do
        preCheckJson=$(jq -r .pre_checks."$preCheckName" "$fileWithAllCommands")
        preCheckCmd=$(echo "$preCheckJson" | jq -r .cmd)
        description=$(echo "$preCheckJson" | jq -r .description)

        eval "$preCheckCmd"
        res=$?
        if [[ ! $res -eq 0 ]]; then
            return 1;
        fi
    done

    echo -n "$cmd"

    # Ask for the parameters of the command
    parameters=$(echo "$cmdJson" | jq -r '.parameters? | keys? | .[]?')
    for paramName in $parameters
    do
        cmdToPrint="${cmd/"<<${paramName}>>"/"\e[4m<<${paramName}>>\e[0m"}"
        echo -en "\033[1K" #<Clear the output printed by the last `echo -n` command.
        echo -en "\r$cmdToPrint"

        paramConf=$(echo "$cmdJson" | jq -r .parameters."$paramName")

        type=$(echo "$paramConf" | jq -r '.type // "input"')
        description=$(echo "$paramConf" | jq -r '.description // ""')
        body=$(echo "$paramConf" | jq -r '.body // "<<VALUE>>"')
        optional=$(echo "$paramConf" | jq -r '.optional // "false"')
        default=$(echo "$paramConf" | jq -r '.default // ""')

        if [[ "$type" == "query" ]]; then
            queryCmd=$(echo "$paramConf" | jq -r .query_cmd)
            queryPreview=$(echo "$paramConf" | jq -r .element_preview)

            # append the default value to the output of the queryCmd
            if [[ "$optional" == "true" ]]; then
                queryCmd="$queryCmd; echo 'NONE'"
            fi
            value=$(eval "$queryCmd" | fzf --height=50% --query="$default" --no-multi --preview="${queryPreview}" --preview-window=right:60%:wrap ) || return
            value=$(__trim "$value")

            if [[ "$value" == "NONE" ]]; then
                finalValue=""
            else
                finalValue="${body//"<<VALUE>>"/"$value"}"
            fi
        elif [[ "$type" == "input" || "$type" == "fix" ]]; then
            addParameter="yes"
            if [[ "$optional" == "true" ]]; then
                addParameter=$(echo -e "yes\nno" | fzf --height=50% --query="" --no-multi  --header="Add '${body}'?") || return
            fi
            if [[ "$addParameter" == "no" ]]; then
                finalValue=""
            elif [[ "$type" == "fix" ]]; then
                finalValue="$body"
            elif [[ "$type" == "input" ]]; then
                value=$(fzf --print-query --header="Type the '$paramName' above." --prompt="> " --phony --query="$default" --preview="echo '$description'" --height=5% --no-info < /dev/null)
                # read -p "Type the '$paramName' ($description) [$default]: " value
                value=${value:-$default}
                finalValue="${body//"<<VALUE>>"/"$value"}"
            fi
        fi

        # Replace the param with its value
        cmd="${cmd//"<<$paramName>>"/"$finalValue"}"
    done

    # Add wrappers to the command
    local cmdBell cmdStatistics
    cmdBell=$(echo "$cmdJson" | jq -r .bell)
    cmdStatistics=$(echo "$cmdJson" | jq -r .statistics)

    if [ "$cmdStatistics" == "true" ]; then
        cmd="reportCmdTiming $cmd"
    fi

    if [ "$cmdBell" == "true" ]; then
        cmd="$cmd; ringBellAndSetExitCode \$?;"
    fi

    echo -en "\033[1K" #<Clear the output printed by the last `echo -n` command.

    READLINE_LINE="$cmd"
    READLINE_POINT=${#READLINE_LINE}
    # eval "$cmd" || return 1
}


bind -x '"\C-e":fss'
