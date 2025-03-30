# HelpAI Oh My Zsh Plugin

Provides a `helpai` command for your Zsh terminal (optimized for Oh My Zsh) that analyzes the last executed command. It sends the **command string**, its **exit status**, and your **OS type** to the Anthropic Claude API for troubleshooting assistance and suggestions.

**Additionally, if you are running within iTerm2 and have prerequisites met, it will attempt to capture and send the last command's output (stdout/stderr) for more accurate analysis.** If output capture fails (e.g., not using iTerm2, prerequisites not met, or shell integration issues), it will print a warning and proceed without the output.

This version uses a Zsh `precmd` hook for reliable exit status capture.

## Prerequisites

To use the basic functionality (analyzing command, status, OS):

1.  **Oh My Zsh:** Must be installed. See [OMZ Installation](https://ohmyz.sh/#install).
2.  **`jq`:** Command-line JSON processor.
3.  **`curl`:** Command-line tool for transferring data (usually pre-installed).
4.  **Claude API Key:** An active API key from Anthropic.

For the **optional automatic output capture** feature:

5.  **iTerm2:** Must be using the iTerm2 terminal emulator on macOS.
6.  **Python 3:** A working Python 3 installation (`python3`).
7.  **`iterm2` Python Library:** The official iTerm2 Python library (`pip3 install iterm2`).
8.  **iTerm2 Python API Enabled:** Must be enabled in iTerm2 Preferences.
9.  **iTerm2 Shell Integration:** Must be installed and working correctly (injecting markers).

## Installation

1.  **Install Python/Terminal Prerequisites (if needed):**
    * Ensure Python 3 and pip are installed.
    * Install the `iterm2` Python library:
        ```bash
        pip3 install iterm2
        ```
    * Install `jq` and `curl`:
        ```bash
        # macOS (using Homebrew)
        brew install jq curl

        # Debian/Ubuntu (example)
        # sudo apt update && sudo apt install jq curl python3-pip

        # Fedora (example)
        # sudo dnf install jq curl python3-pip
        ```

2.  **Enable iTerm2 Python API:**
    * Open iTerm2 Preferences (`Cmd + ,`).
    * Go to the **API** tab.
    * Ensure **"Enable Python API"** is **checked**.
    * Restart iTerm2 if you changed this setting.

3.  **Install/Verify iTerm2 Shell Integration:** This is crucial for output capture. Even if previously installed, conflicts can prevent it from working. Re-running the installer is often the best way to ensure it's correctly set up.
    ```bash
    # Run this command in iTerm2:
    curl -L [https://iterm2.com/shell_integration/install_shell_integration.sh](https://iterm2.com/shell_integration/install_shell_integration.sh) | bash
    ```
    * **Important:** After running this, **quit and restart iTerm2 completely** (Cmd+Q, then reopen).

4.  **Clone the Plugin Repository:**
    Clone this repository (which includes `helpai.plugin.zsh`, `get_last_output.py`, etc.) into your Oh My Zsh custom plugins directory:
    ```bash
    # Replace with YOUR repo URL if you host it elsewhere
    git clone [https://github.com/YOUR_USERNAME/helpai-zsh-plugin.git](https://github.com/YOUR_USERNAME/helpai-zsh-plugin.git) ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/helpai
    ```

5.  **Set Claude API Key:** Add your API key as an environment variable in `~/.zshrc` or `~/.zshenv`:
    ```bash
    # In ~/.zshrc or ~/.zshenv
    export CLAUDE_API_KEY="YOUR_ANTHROPIC_API_KEY_HERE"
    ```
    *(Secure the file with `chmod 600` and reload your shell after adding it).*

6.  **Enable Plugin in `.zshrc`:** Add `helpai` to the `plugins=(...)` list:
    ```zsh
    plugins=(
        # other plugins...
        helpai
    )
    ```

7.  **Reload Zsh:** Run `source ~/.zshrc` or open a new iTerm2 tab/window.

## Usage

1.  Run any command in your terminal (ideally iTerm2 for output capture).
2.  If you encounter an error or want analysis, immediately run the `helpai` command on the next line:
    ```bash
    $ command --that-produces --error
    # (Command finishes, potentially printing errors)
    $ helpai
    Analyzing command: command --that-produces --error
    Exit status: 1 # Or other non-zero status
    Attempting to retrieve last command output via iTerm2 API...
    # [Optional: Output captured message OR Warning message if capture fails]
    Asking Claude for help (Model: ...)...

    --- Claude's Suggestion ---
    (Claude's analysis based on command, status, OS, and output if captured)
    ---------------------------
    ```
    *If automatic output capture fails, you will see a warning message, and the request will be sent to Claude without the command's output.*

## How it Works

* Uses a `precmd` hook for reliable exit status capture.
* Reads the command string from history (`fc`).
* Detects the OS type.
* **If running in iTerm2:** Calls the `get_last_output.py` script.
    * The Python script connects to the iTerm2 API using the `iterm2` library.
    * It attempts to find the current terminal session.
    * It reads the terminal screen buffer content.
    * It tries to parse iTerm2 Shell Integration markers (`OSC 133 B/D`) to extract the previous command's output block.
* Constructs a prompt including command, status, OS, and the captured output (if available and truncated).
* Uses `curl` to query Claude and `jq` to parse the response.

## Configuration

You can adjust the following variables directly within the `helpai()` function definition in the `helpai.plugin.zsh` file if needed:

* `CLAUDE_API_ENDPOINT`: The URL for the Claude Messages API.
* `CLAUDE_MODEL`: The specific Claude model to use (Default: `"claude-3-7-sonnet-20250219"` - *ensure this model name is valid and accessible via your API key*).
* `MAX_TOKENS`: The maximum number of tokens for the Claude response.
* `output_char_limit` / `output_line_limit`: Variables within the Zsh script controlling how much captured output is sent.

## Limitations & Troubleshooting Output Capture

* **iTerm2 Required:** Automatic output capture **only works in iTerm2**. In other terminals, the script will skip this step.
* **Python API & Library Required:** Needs Python 3, the `iterm2` pip package, and the iTerm2 Python API enabled in Preferences.
* **Shell Integration MUST Work:** Capture relies entirely on iTerm2 Shell Integration correctly injecting markers (`OSC 133 B/D`) around commands. If markers are missing (due to Zsh/OMZ conflicts, bad installation, etc.), capture will fail, and a warning will be shown. Reinstalling shell integration (Step 3 in Installation) and restarting iTerm2 is the first troubleshooting step. If problems persist, it may indicate conflicts with your specific Zsh configuration.
* **Output Truncation:** Captured output is truncated (default: last 50 lines/2000 chars) before being sent to Claude.
* **Potential Fragility:** Parsing terminal buffers via scripting can sometimes be fragile depending on command output complexity or shell state.