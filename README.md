# FSS: Command manager tool

## Definition
The FSS tool is used to:
- Store and set an alias to parametrized commands.
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
