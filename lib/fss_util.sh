#! /bin/bash

# Get all the files containing commands from the config file
# Parameters:
#     1. Config file path
function __getAllCommandFilesFromConfig()
{
    confFile=$1
    if [ -z "$confFile" ]; then
        return 1;
    fi

    if [ ! -f "$confFile" ]; then
        jsonFiles="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")/fss/*";
        echo "$jsonFiles" >> "$confFile";
    fi

    commandFiles=();
    while read -r line; do
        commandFiles+=("$line");
    done < "$confFile"

    echo "${commandFiles[@]}";
}

## Push all the commands to a tmp file in json format and return its file path
## Parameters:
##     1. Array of command files
function __pushAllCommandsToTmpFile()
{
    commandFiles=("$@");
    if [ "${#commandFiles[@]}" -eq 0 ]; then
        return 1;
    fi

    # combine all the files into one
    tmpFile=/tmp/fss_commands.json;
    rm -f $tmpFile;
    jq -s 'reduce .[] as $item ({}; . * $item)' ${commandFiles[@]} >> $tmpFile;

    echo $tmpFile;
}

# Get a command in json format
# Parameters:
#     1. Command name
#     2. Json file containing all the commands
function __getCommandFromJsonFile()
{
    cmdName=$1
    if [ -z "$cmdName" ]; then
        echo "Command name not given to $(getCommandJson) function";
        return 1;
    fi

    jsonFile=$2
    if [ -z "$jsonFile" ]; then
        echo "Json file not given to $(getCommandJson) function";
        return 1;
    fi

    jq -r .commands."$cmdName" "$jsonFile";
}

# Trim a given string
# Parameters:
#     1. String to trim
function __trim()
{
    res=$(echo "$1" | xargs);
    echo "$res";
}
