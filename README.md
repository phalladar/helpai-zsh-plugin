# HelpAI Oh My Zsh Plugin

Provides a `helpai` command for your Zsh terminal (optimized for Oh My Zsh) that analyzes the last executed command. It sends the **command string**, its **exit status**, and your **OS type** to the Anthropic Claude API for troubleshooting assistance and suggestions.

This version uses a Zsh `precmd` hook to more reliably capture the exit status of the last command, even if it failed before execution (e.g., "command not found").

**Note:** This plugin does **not** capture or send the *output* of the command, only the command text and exit status.

## Prerequisites

1.  **Oh My Zsh:** Must be installed.
2.  **`jq`:** Command-line JSON processor. Install via Homebrew: `brew install jq` (or your system's package manager).
3.  **`curl`:** Command-line tool for transferring data. Usually pre-installed on macOS and Linux distributions.
4.  **Claude API Key:** You need an API key from Anthropic.

## Installation

1.  **Create Plugin Directory:**
    ```bash
    mkdir -p ~/.oh-my-zsh/custom/plugins/helpai
    ```
2.  **Download Files:** Place the `helpai.plugin.zsh` file (and optionally the `_helpai` completion file and this `README.md`) into the created directory: `~/.oh-my-zsh/custom/plugins/helpai/`
3.  **Set API Key:** Add your Claude API key as an environment variable in your shell configuration file (`~/.zshrc` or `~/.zshenv`). **Do not put the key directly in the plugin code.**
    ```bash
    # In ~/.zshrc or ~/.zshenv
    export CLAUDE_API_KEY="YOUR_ANTHROPIC_API_KEY_HERE"
    ```
    *Security Note:* Ensure your `.zshrc`/`.zshenv` has appropriate permissions (e.g., `chmod 600 ~/.zshrc`).
4.  **Enable Plugin:** Add `helpai` to the `plugins=(...)` list in your `~/.zshrc` file. Make sure it's inside the parentheses, separated by spaces or newlines from other plugins. Example:
    ```zsh
    plugins=(
        git
        docker
        # other plugins...
        helpai
    )
    ```
5.  **Reload Zsh:** Apply the changes by running `source ~/.zshrc` or opening a new terminal window/tab.

## Usage

1.  Run any command in your terminal.
2.  If you encounter an error or want analysis, immediately run the `helpai` command on the next line:
    ```bash
    $ command --that-produces --error
    # (Command finishes, potentially printing errors)
    $ helpai
    Analyzing command: command --that-produces --error
    Exit status: 1 # Or other non-zero status (should now be accurate)
    Asking Claude for help (Model: claude-3-7-sonnet-20250219)...

    --- Claude's Suggestion ---
    (Claude's analysis based on the command, exit status, and OS type)
    ---------------------------
    ```

## How it Works (Briefly)

* The plugin registers a `precmd` hook (`_helpai_capture_status`) that runs just before each prompt is displayed, saving the `$?` (exit status) of the command that just finished into a global variable (`_HELP_AI_LAST_STATUS`).
* When `helpai` is run:
    * It reads the command string from Zsh history (`fc -ln -1`).
    * It reads the reliably captured exit status from `_HELP_AI_LAST_STATUS`.
    * It detects the OS type (`$OSTYPE` or `uname`).
    * It constructs a prompt containing this information.
    * It sends the prompt to the configured Claude API endpoint using `curl`.
    * It parses the JSON response using `jq` and prints the suggestion.

## Configuration

You can adjust the following variables directly within the `helpai()` function definition at the top of the `helpai.plugin.zsh` file if needed:

* `CLAUDE_API_ENDPOINT`: The URL for the Claude Messages API.
* `CLAUDE_MODEL`: The specific Claude model to use (Default: `"claude-3-7-sonnet-20250219"` - *ensure this model name is valid and accessible via your API key*).
* `MAX_TOKENS`: The maximum number of tokens for the response.

## Limitations

* **Does not capture command output:** As mentioned, the actual text output (stdout/stderr) of the command is not sent to Claude due to the complexity of capturing it reliably after the fact in a standard shell environment. The analysis is based only on the command text, its exit status, and your OS type.
* **Exit Status Accuracy:** While significantly improved with the `precmd` hook, there might be extremely rare edge cases in complex Zsh configurations where the status capture could be affected by other hooks.