#! /bin/bash

## Date:        1st of Sept 2022
## Summary:     Tool to select predefined commands within its parameters through fzf
## Command:     fss
##
## * How it works:
## When fss is called, a list of all the predefined commands is shown through the fzf tool and the
## user only has to select which command wants to run.
## There is the option to add arguments to the command, which will be asked through fzf as well.
##
## * How to add a new command:
## 1. Create a json file with the following structure:
## {
##     "commands": {
##         "<command_name1>": {
##             "cmd": "<command to execute>",
##             "description": "<command description with parameters surrounded by '<<' and '>>'>",
##             "parameters": {
##                 "<query1>": {
##                     "description": "<query description>",
##                     "type": "query",
##                     "query_cmd": "<command to execute to get the query value>", 
##                     "element_preview": "<command to execute to get the element preview>",
##                     "default": "<default value>"
##                 },
##                 "<query2>": {
##                      ...
##                 },
##                 "<input1>": {
##                     "description": "<input description>",
##                     "type": "input",
##                     "default": "<default value>"
##                 },
##                 "<input2>": {
##                     ...
##                 }
##             },
##             "pre_checks": [
##                 "<pre_check1>",
##                 "<pre_check2>"
##             ]
##         },
##         "<command_name2>": {
##             ...
##         }
##     },
##     "pre_checks": {
##         "<pre_check1>": {
##             "cmd": "<command to execute>",
##             "description": "<pre check description>"
##         },
##         "<pre_check2>": {
##             "cmd": "<command to execute>",
##             "description": "<pre check description>"
##         }
##     }
## }
## Notes:
##     - A 'query' parameter will be asked to the user through fzf, the options to choose from 
##       will be the output of the "query_cmd" command
##     - An 'input' parameter will be typed by the user.
##     - A 'pre_check' will be executed before running the command, if it fails the command will
##       not be executed
##     - The "pre_checks" section is optional
##
## 2. Add the json file to the fss configuration file, which is located in $HOME/.fss.conf
## 3. Run fss and the new command should be available

FSS_CONF_FILE="$HOME/.fss.conf"

if [[ ! -e "$FSS_CONF_FILE" ]]; then
    fss_dir="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
    echo "${fss_dir}/commands/*" > $FSS_CONF_FILE
    mkdir "${fss_dir}/commands"
fi

fss() {

    usage() {
        echo -e "USAGE:"
        echo -e "  fss [-ph][-c <command>]"
        echo -e ""
        echo -e "OPTIONS:"
        echo -e "  -h\t\tshow this usage message"
        echo -e "  -p\t\tprint execution line without running it"
        echo -e "  -c <command>\texecute the given command"
        echo -e ""
    }

    cmdName=""
    printOnly="false"
    while getopts ":phc:" arg; do
        case $arg in
            p)
                printOnly="true"
                ;;
            h)
                usage
                return 0
                ;;
            c)
                cmdName=$OPTARG
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                usage
                return 1
                ;;
            :)
                echo "Option -$OPTARG requires an argument." >&2
                usage
                return 1
                ;;
        esac
    done
    shift "$((OPTIND-1))"

    # Load .sh files from ../lib
	local fss_path
	fss_path=$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" >/dev/null 2>&1 && pwd )

	local lib
	while IFS= read -r -d '' lib; do
		[[ -e "${lib}" && ! -d "${lib}" ]] || continue
		# shellcheck source=/dev/null
		source "${lib}"
	done < <( {
		find "${fss_path}/../lib/" -type f \( -name '*.sh' -o	-name '*.bash' \) -print0 2>/dev/null
	} )

    # Merge all commands into a temporal file
    listOfFilesWithCommands=$(__getAllCommandFilesFromConfig "$FSS_CONF_FILE")
    fileWithAllCommands=$(__pushAllCommandsToTmpFile "${listOfFilesWithCommands[@]}")

    # Ask for the command to run unless we already know it
    if [ -z "$cmdName" ]; then
        cmdPreview="jq -C --tab '.commands.\"{}\"' $fileWithAllCommands"
        cmdName=$(jq -r '.commands | keys[]' "$fileWithAllCommands" | fzf --height=50% --no-multi --preview="$cmdPreview" --preview-window=right:60%:wrap ) || return

    else
        cmdExists=$(jq -r .commands."$cmdName?" "$fileWithAllCommands")
        if [ -z "$cmdExists" ] || [ "$cmdExists" == "null" ]; then
            echo "Command '$cmdName' not found in any commands json file"
            return 1
        fi
    fi

    cmdJson=$(__getCommandFromJsonFile "$cmdName" "$fileWithAllCommands")
    cmdExec=$(echo "$cmdJson" | jq -r .cmd)

    # Execute pre_checks
    pre_checks=$(echo "$cmdJson" | jq -r '.pre_checks[]?')
    for preCheckName in $pre_checks
    do
        preCheckJson=$(jq -r .pre_checks."$preCheckName" "$fileWithAllCommands")
        cmd=$(echo "$preCheckJson" | jq -r .cmd)
        description=$(echo "$preCheckJson" | jq -r .description)

        eval "$cmd"
        res=$?
        if [[ ! $res -eq 0 ]]; then
            return 1;
        fi
    done

    echo -n "$cmdExec"

    # Ask for the parameters of the command
    parameters=$(echo "$cmdJson" | jq -r '.parameters? | keys? | .[]?')
    for paramName in $parameters
    do
        cmdToPrint="${cmdExec/"<<${paramName}>>"/"\e[4m<<${paramName}>>\e[0m"}"
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
                read -p "Type the '$paramName' ($description) [$default]: " value
                value=${value:-$default}
                finalValue="${body//"<<VALUE>>"/"$value"}"
            fi
        fi

        # Replace the param with its value
        cmdExec="${cmdExec//"<<$paramName>>"/"$finalValue"}"
    done

    # Add wrappers to the command
    cmdBell=$(echo "$cmdJson" | jq -r .bell)
    cmdStatistics=$(echo "$cmdJson" | jq -r .statistics)

    if [ "$cmdStatistics" == "true" ]; then
        cmdExec="reportCmdTiming $cmdExec"
    fi

    if [ "$cmdBell" == "true" ]; then
        cmdExec="$cmdExec; ringBellAndSetExitCode \$?;"
    fi

    if [ "$printOnly" == "true" ]; then
        history -s "$cmdExec"
        return 0;
    fi

    # Execute the command
    echo -en "\033[1K" #<Clear the output printed by the last `echo -n` command.
    echo -e "\r$cmdExec"
    echo ""

    history -s "$cmdExec"
    eval "$cmdExec" || return 1
}
