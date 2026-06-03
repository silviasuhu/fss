# FSS: Command manager tool

## Definition

The FSS tool is used to:

- Store and set an alias to parametrized and predefined commands.
- Access and execute these commands in a fzf-fashion.

Works with both bash and zsh.

## Installation

1. Clone this repository.

   ```
   git clone git@github.com:silviasuhu/fss.git
   ```

2. Run the installer. It checks for required dependencies and adds the
   source line to both `~/.bash_profile` (or `~/.bashrc` on Linux) and
   `~/.zshrc`. Safe to re-run. To remove later: `./fss/install.sh --uninstall`.

   ```
   ./fss/install.sh
   ```

3. Open a new shell (or `source` the rc file the installer modified).

4. Add your commands to the `fss/commands` directory.

## Usage

Press `Ctrl+E` to open the fzf picker, select a command, and fill in any
parameters. The resulting command is placed on the prompt for you to run
(or, in zsh, pushed onto the buffer with `print -z`). You can also call
the `fss` function directly — when not invoked through the keybinding,
the resolved command is printed to stdout.

> ⚠ The default `Ctrl+E` shadows Readline's `end-of-line` binding.
> To use a different chord, export `FSS_KEYBIND_BASH` (bash syntax,
> e.g. `\C-x\C-e`) and/or `FSS_KEYBIND_ZSH` (zsh syntax, e.g. `^X^E`)
> before sourcing `fss.sh`.

## Dependencies

- Fzf command (https://github.com/junegunn/fzf)
- Bat command (https://github.com/sharkdp/bat)
- Jq command (https://github.com/jqlang/jq)

## Configuration

All the commands should be stored in JSON files.
On first source, fss creates `~/.fss.conf` with one entry pointing at the
bundled `commands/` directory inside the repo. To pull in commands from
elsewhere, append additional file or glob paths (one per line) to that
config file.

### Format of a fss JSON file

```
{
    "commands": {
        "<command_name1>": {
            "description": "<cmd description>",
            "cmd": "<command to execute with parameters surrounded by '<<' and '>>'>",
            "bell": "<true|false — ring the terminal bell when the command finishes (optional)>",
            "statistics": "<true|false — wrap the command in a timing report (optional)>",
            "parameters": {
                "<query1>": {
                    "description": "<query description>",
                    "type": "query",
                    "query_cmd": "<command to execute to get the query value>",
                    "element_preview": "<command to execute to get the element preview>",
                    "default": "<default value>",
                    "optional": "<true|false — adds a 'NONE' choice that resolves to empty (optional)>",
                    "body": "<template substituted in for this parameter; '<<VALUE>>' is replaced with the user's selection. Defaults to '<<VALUE>>' (optional)>"
                },
                "<query2>": {
                     ...
                },
                "<input1>": {
                    "description": "<input description>",
                    "type": "input",
                    "default": "<default value>",
                    "body": "<see above (optional)>"
                },
                "<input2>": {
                    ...
                },
                "<fix1>": {
                    "type": "fix",
                    "body": "<text inserted verbatim in place of <<fix1>>>"
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

  | Type    | How the value is determined                                           | Required fields |
  | ------- | --------------------------------------------------------------------- | --------------- |
  | `query` | User picks from an `fzf` list whose options are `query_cmd`'s output. | `query_cmd`     |
  | `input` | User types the value (`default` pre-fills the prompt).                | —               |
  | `fix`   | `body` is inserted verbatim. If `optional` is `true`, the user is first asked (via `fzf`) to include `body` or pick `NONE` to skip it. | `body`          |
- For each parameter, the chosen/typed value is wrapped in `body` (with `<<VALUE>>`
  replaced by the value), and the result is substituted into `cmd` in place of
  `<<parameter_name>>`. If `body` is omitted it defaults to `<<VALUE>>`, i.e. the
  raw value.
- A 'pre_check' will be executed before running the command; if it fails the command will
  not be executed.
- The "pre_checks" section is optional.
