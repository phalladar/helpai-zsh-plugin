# HelpAI Oh My Zsh Plugin

Provides a `helpai` command for your Zsh terminal (optimized for Oh My Zsh) that analyzes the last executed command. It sends the **command string**, its **exit status**, and your **OS type** to the Anthropic Claude API for troubleshooting assistance and suggestions.

**Additionally, if you are running within iTerm2 and have prerequisites met, it will attempt to capture and send the last command's output (stdout/stderr) for more accurate analysis.** If output capture fails (e.g., not using iTerm2, prerequisites not met, or shell integration issues), it will print a warning and proceed without the output.

**New Feature:** The plugin now asks the AI to identify the single most likely command to fix the issue and place it in `<userfix>` tags at the end of its response. If these tags are found:
* The command *within* the tags is automatically copied to your clipboard.
* The tags and the command *are removed* from the suggestion displayed in the terminal.
* A message confirms the copy (or warns if it failed).

This version uses a Zsh `precmd` hook for reliable exit status capture and includes checks for common API errors (like invalid keys).

## Prerequisites

To use the basic functionality (analyzing command, status, OS):

1.  **Oh My Zsh:** Must be installed. See [OMZ Installation](https://ohmyz.sh/#install).
2.  **`jq`:** Command-line JSON processor.
3.  **`curl`:** Command-line tool for transferring data (usually pre-installed).
4.  **Claude API Key:** An active API key from Anthropic (set as `CLAUDE_API_KEY` environment variable).

For the **optional automatic output capture** feature:

5.  **iTerm2:** Must be using the iTerm2 terminal emulator on macOS.
6.  **Python 3:** A working Python 3 installation (`python3`).
7.  **`iterm2` Python Library:** The official iTerm2 Python library (`pip3 install iterm2`).
8.  **iTerm2 Python API Enabled:** Must be enabled in iTerm2 Preferences -> API.
9.  **iTerm2 Shell Integration:** Must be installed and working correctly (injecting markers).

For the **optional automatic clipboard copy** feature:

10. **Clipboard Utility:** One of the following command-line clipboard tools must be installed and accessible in your `PATH`:
    * `pbcopy` (Standard on macOS)
    * `wl-copy` (Common on Wayland Linux distributions)
    * `xclip` (Common on X11 Linux distributions - requires `$DISPLAY` set)
    * `xsel` (Alternative on X11 Linux distributions - requires `$DISPLAY` set)
    * *(If none are found, the plugin will still work but will display the suggested fix command in the terminal instead of copying it).*

## Installation

1.  **Install Terminal/Python/Clipboard Prerequisites (if needed):**
    * Ensure Python 3, pip, `jq`, and `curl` are installed.
    * Install the `iterm2` Python library (for output capture):
        ```bash
        pip3 install iterm2
        ```
    * Install `jq` and `curl` (examples):
        ```bash
        # macOS (using Homebrew)
        brew install jq curl

        # Debian/Ubuntu
        # sudo apt update && sudo apt install jq curl python3-pip

        # Fedora
        # sudo dnf install jq curl python3-pip
        ```
    * Install a clipboard utility (for auto-copy, examples):
        ```bash
        # macOS: pbcopy is usually pre-installed
        # Debian/Ubuntu (Wayland): sudo apt install wl-clipboard
        # Debian/Ubuntu (X11): sudo apt install xclip
        # Fedora (Wayland): sudo dnf install wl-clipboard
        # Fedora (X11): sudo dnf install xclip
        ```

2.  **Enable iTerm2 Python API (for output capture):**
    * Open iTerm2 Preferences (`Cmd + ,`). Go to **API** tab. Ensure **"Enable Python API"** is checked. Restart iTerm2 if changed.

3.  **Install/Verify iTerm2 Shell Integration (for output capture):** Crucial for output capture. Re-running the installer often helps fix issues.
    ```bash
    # Run this command in iTerm2:
    curl -L [https://iterm2.com/shell_integration/install_shell_integration.sh](https://iterm2.com/shell_integration/install_shell_integration.sh) | bash
    ```
    * **Important:** **Quit and restart iTerm2 completely** (Cmd+Q, then reopen) after running.

4.  **Clone the Plugin Repository:**
    ```bash
    # Replace with YOUR repo URL if hosted elsewhere
    git clone [https://github.com/YOUR_USERNAME/helpai-zsh-plugin.git](https://github.com/YOUR_USERNAME/helpai-zsh-plugin.git) ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/helpai
    ```

5.  **Set Claude API Key:** Add your key as an environment variable, typically in `~/.zshrc` or `~/.zshenv`:
    ```bash
    # In ~/.zshrc or ~/.zshenv
    export CLAUDE_API_KEY="YOUR_ANTHROPIC_API_KEY_HERE"
    ```
    * *(Secure the file (`chmod 600 ~/.zshrc`) and reload your shell: `source ~/.zshrc`)*

6.  **Enable Plugin in `.zshrc`:** Add `helpai` to the `plugins=(...)` list:
    ```zsh
    plugins=(
        # other plugins...
        helpai
    )
    ```

7.  **Reload Zsh:** Run `source ~/.zshrc` or open a new terminal tab/window.

## Usage

1.  Run any command in your terminal.
2.  If it fails or you need analysis, immediately run `helpai` on the next line:
    ```bash
    $ some-command --with --typo
    # (Command finishes, potentially printing errors, exit status != 0)
    $ helpai
    Analyzing command: some-command --with --typo
    Exit status: 1 # Or other non-zero status
    Attempting to retrieve last command output via iTerm2 API...
    # [Optional: Output captured message OR Warning if capture fails]
    Asking Claude for help (Model: ...)...
    [Suggested fix command copied to clipboard via pbcopy (macOS).] # Or similar message

    --- Claude's Suggestion ---
    (Claude's analysis and explanation appears here. The <userfix> tag and command are NOT shown.)

    It looks like there might be a typo in your command. The `--typo` flag isn't recognized.
    Perhaps you meant `--type`?

    Try running:
    `some-command --with --type`
    ---------------------------
    ```
3.  If a fix command was identified and copied, you can now paste (`Cmd+V` or `Ctrl+Shift+V`) the suggested command directly into your terminal.
4.  *If automatic output capture fails, a warning is shown, and the request proceeds without it.*
5.  *If automatic clipboard copy fails (e.g., no tool found), a warning is shown, and the suggested fix command will be printed to the terminal instead of being copied.*

## How it Works

* Uses a `precmd` Zsh hook for reliable capture of the last command's exit status (`$?`).
* Reads the command string from history (`fc -ln -1`).
* Detects the OS type (`OSTYPE` / `uname`).
* **Output Capture (Optional, iTerm2):**
    * If `ITERM_SESSION_ID` is set and the Python script exists, it calls `get_last_output.py`.
    * The Python script connects to the iTerm2 API (`iterm2` library).
    * It reads the current terminal session's screen buffer.
    * It parses iTerm2 Shell Integration markers (`OSC 133 B/D`) to extract the previous command's output block.
* **Prompt Construction:** Builds a prompt for Claude including the command, status, OS, and truncated captured output (if available). It specifically asks Claude to place the most likely fix command in `<userfix>...</userfix>` tags at the end.
* **API Call:** Uses `curl` to send the request to the specified Claude API endpoint with the API key.
* **Response Handling:**
    * Checks the `curl` exit status.
    * Saves the response to a temporary file.
    * **Checks for API errors** (e.g., invalid key, rate limit) by looking for `{"type": "error"}` in the JSON response *before* processing further. If an error is found, it reports details and exits.
    * Parses the JSON response using `jq` to extract the main suggestion text.
    * **Clipboard Feature:**
        * Searches the suggestion text for `<userfix>` and `</userfix>` tags.
        * If found, extracts the command string between them.
        * Detects available clipboard tools (`pbcopy`, `wl-copy`, `xclip`, `xsel`).
        * If a tool is found, pipes the extracted command to it.
        * Removes the `<userfix>...</userfix>` block from the suggestion text.
    * Prints the (potentially modified) suggestion text to the terminal.
    * Prints status messages about output capture and clipboard actions to stderr.

## Configuration

You can adjust the following variables directly within the `helpai()` function definition in `helpai.plugin.zsh`:

* `CLAUDE_API_ENDPOINT`: URL for the Claude Messages API.
* `CLAUDE_MODEL`: Specific Claude model to use (ensure it's valid for your key).
* `MAX_TOKENS`: Max tokens for Claude's response.
* `output_char_limit` / `output_line_limit`: Control truncation of captured command output sent in the prompt.

## Limitations & Troubleshooting

* **Output Capture:**
    * Requires **iTerm2** on macOS with **Python 3**, the **`iterm2` library**, **API enabled**, and working **Shell Integration**.
    * Shell Integration is fragile. If markers (`OSC 133 B/D`) are missing (due to Zsh/OMZ conflicts, bad install), capture fails. Reinstalling (Step 3) and restarting iTerm2 is the first fix. Persistent issues may indicate Zsh configuration conflicts.
    * Captured output is truncated.
* **Clipboard Copy:**
    * Requires a supported **clipboard utility** (`pbcopy`, `wl-copy`, `xclip`, `xsel`) to be installed and in the `PATH`.
    * `xclip` and `xsel` typically require a running X11 session and the `$DISPLAY` environment variable to be set correctly. They may not work in basic TTY sessions or improperly configured SSH sessions.
    * If no tool is found or the copy fails, the suggested command is printed as a fallback.
* **API Errors:** The script now checks for common API errors (authentication, rate limits) reported by Claude and provides more specific error messages. Ensure your `CLAUDE_API_KEY` is correct and active.
* **AI Suggestion Quality:** The usefulness depends on Claude's understanding of the context provided. The clipboard feature relies on the AI correctly identifying a single command and using the specified tags.