# FSS: Command manager tool

## Definition
The FSS tool is used to:
- Store and set an alias to parametrized and predefined commands.
- Access and execute these commands in a fzf-fashion.

## Installation

1. Clone this repository.
   ```
   git clone git@github.com:silviasuhu/fss.git
   ```

2. Make `fss/bin/fss.sh` executable.
   ```
   chmod +x fss/bin/fss.sh
   ```

3. Add the following line to your `~/.bash_profile` file.
   ```
   source $HOME/fss/bin/fss.sh
   ```

4. Reset the current bash instance.
   ```
   reset
   ```

5. Add your commands to the `fss/commands` directory.
   

## Dependencies

- Fzf command (https://github.com/junegunn/fzf)
- Bat command (https://github.com/sharkdp/bat)
- Jq command (https://github.com/jqlang/jq)

## Configuration

All the commands should be stored in JSON files.
The directory/ies of these json files must be appended to the `~/.fss.conf` file.

### Format of a fss JSON file

```
{
    "commands": {
        "<command_name1>": {
            "description": "<cmd description>",
            "cmd": "<command to execute with parameters surrounded by '<<' and '>>'>",
            "parameters": {
                "<query1>": {
                    "description": "<query description>",
                    "type": "query",
                    "query_cmd": "<command to execute to get the query value>", 
                    "element_preview": "<command to execute to get the element preview>",
                    "default": "<default value>"
                },
                "<query2>": {
                     ...
                },
                "<input1>": {
                    "description": "<input description>",
                    "type": "input",
                    "default": "<default value>"
                },
                "<input2>": {
                    ...
                }
            },
            "pre_checks": [
                "<pre_check1>",
                "<pre_check2>"
            ]
        },
        "<command_name2>": {
            ...
        }
    },
    "pre_checks": {
        "<pre_check1>": {
            "cmd": "<command to execute>",
            "description": "<pre check description>"
        },
        "<pre_check2>": {
            "cmd": "<command to execute>",
            "description": "<pre check description>"
        }
    }
}
```

Notes:

- There are 3 different types of parameters:
    
   - A 'query' parameter will be asked to the user through fzf, the options to choose from 
      will be the output of the "query_cmd" command.
      
   - The user is going to type an 'input' parameter.
       
   - A 'fix' parameter will either be printed or not.
       
- A 'pre_check' will be executed before running the command, if it fails the command will
      not be executed.
  
- The "pre_checks" section is optional.
