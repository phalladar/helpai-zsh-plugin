# Oh My Zsh plugin file for 'helpai'

# --- Global variable and Hook for capturing last status ---
_HELP_AI_LAST_STATUS=0
_helpai_capture_status() { _HELP_AI_LAST_STATUS=$?; }
# Add the hook using modern add-zsh-hook if available, otherwise fallback
if command -v add-zsh-hook >/dev/null 2>&1; then
    add-zsh-hook precmd _helpai_capture_status
else
    if [[ -z "${precmd_functions[(r)_helpai_capture_status]}" ]]; then
        precmd_functions=(_helpai_capture_status "${precmd_functions[@]}")
    fi
fi
# --- End Hook Setup ---


# --- Main helpai function ---
helpai() {
  # --- Configuration ---
  local CLAUDE_API_ENDPOINT="https://api.anthropic.com/v1/messages"
  local CLAUDE_MODEL="claude-3-7-sonnet-20250219" # Ensure this model is valid and accessible
  local MAX_TOKENS=1024
  local output_char_limit=2000  # Max chars of captured output to send
  local output_line_limit=50    # Max lines of captured output to send
  # --- End Configuration ---

  # Prerequisite checks
  if ! command -v jq &> /dev/null; then echo "Error: 'jq' command not found. Please install it." >&2; return 1; fi
  if ! command -v curl &> /dev/null; then echo "Error: 'curl' command not found. Please install it." >&2; return 1; fi
  if [[ -z "$CLAUDE_API_KEY" ]]; then echo "Error: CLAUDE_API_KEY environment variable is not set." >&2; return 1; fi

  # Read exit status captured by the precmd hook
  local last_exit_status=${_HELP_AI_LAST_STATUS:--1} # Default to -1 if somehow unset

  # Get the last command, removing leading whitespace
  local last_command; last_command=$(fc -ln -1 | sed 's/^[[:space:]]*//')

  # If the last command was 'helpai' itself, get the one before that
  if [[ "$last_command" == "helpai" ]]; then
     last_command=$(fc -ln -2 | head -n 1 | sed 's/^[[:space:]]*//')
     # Note: Exit status might be from the previous 'helpai' call in this edge case
     echo "Warning: Analyzing command run before the previous 'helpai'. Exit status ($last_exit_status) might be from 'helpai', not the command you intended." >&2
  fi

  local os_type=${OSTYPE:-$(uname -s)} # Get OS type

  echo "Analyzing command: $last_command"
  echo "Exit status: $last_exit_status"

  # --- Attempt to call Python script to get command output (iTerm2 specific) ---
  local last_output=""
  local python_script_path="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/helpai/get_last_output.py"
  local python_executable="python3" # Assumes python3 is in PATH

  echo "Attempting to retrieve last command output via iTerm2 API..."
  # Only attempt if the script exists and we are likely in iTerm (ITERM_SESSION_ID is set)
  if [[ -x "$python_script_path" ]]; then
     if [[ -z "$ITERM_SESSION_ID" ]]; then
         echo "Warning: ITERM_SESSION_ID not found. Cannot capture output automatically (requires iTerm2)." >&2
     else
         # Run python script, capture stdout, hide stderr unless debugging
         last_output=$(command $python_executable "$python_script_path" 2>/dev/null)
         local py_exit_status=$?
         if [[ $py_exit_status -ne 0 ]]; then
             echo "Warning: Python script for output capture failed to execute correctly (Exit Status: $py_exit_status). Ensure Python 3 and 'iterm2' library are installed." >&2
             last_output="" # Ensure empty on failure
         # elif [[ -z "$last_output" ]]; then
             # Optional: Debug message if script ran ok but found no output
             # echo "Debug: Python script ran but found no output (iTerm2 Shell Integration markers likely missing or malfunctioning)." >&2
         fi
     fi
  # else
     # Optional: Warn if script is missing
     # echo "Debug: Python script $python_script_path not found or not executable." >&2
  fi
  # --- End Get Output ---

  echo "Asking Claude for help (Model: $CLAUDE_MODEL)..."

  # --- Construct Prompt ---
  local prompt_text
  prompt_text="I ran the following command in my Zsh terminal (OS type: $os_type):\n\n"
  prompt_text+="\`\`\`bash\n$last_command\n\`\`\`\n\n"
  prompt_text+="It finished with exit status: $last_exit_status\n\n"

  # Add captured output (truncated) IF it was captured
  local truncated_output=""
  if [[ -n "$last_output" ]]; then
     echo "Output captured, adding to prompt (truncated if needed)."
     # Truncate by lines first, then by characters for Claude context window
     truncated_output=$(echo "$last_output" | tail -n $output_line_limit)
     if [[ ${#truncated_output} -gt $output_char_limit ]]; then
         truncated_output=${truncated_output: -$output_char_limit}
         echo "(Output truncated to last ${output_char_limit} chars for prompt)" >&2
     fi
     prompt_text+="\nThe command produced the following output (potentially truncated):\n\`\`\`\n"
     # Use printf -v for safe concatenation, especially if output has format chars
     printf -v prompt_text -- '%s%s\n' "$prompt_text" "$truncated_output"
     prompt_text+="\`\`\`\n"
  else
     # Only show warning if output capture was expected to work (i.e., python script existed)
     if [[ -x "$python_script_path" ]]; then
       echo "Warning: Failed to automatically capture command output (requires iTerm2 with working Shell Integration markers)." >&2
     fi
  fi

  # Add final analysis request, conciseness hints, and instruction for the fix command tag
  prompt_text+="\nPlease analyze this command, its exit status, and its output (if provided). What might have gone wrong? How can I fix it or achieve the intended goal?"
  prompt_text+="\nTry to be concise. Pick your most plausible solution and pitch it."
  prompt_text+="\n\nIMPORTANT: If you identify a specific command that is the most likely fix for the user's problem, please append ONLY that command string to the VERY END of your response, enclosed in <userfix> and </userfix> tags. Example: <userfix>git push --set-upstream origin main</userfix>. Do not add any explanation within or after these tags."
  # --- End Construct Prompt ---

  # Prepare JSON payload using jq for safety
  local json_payload; json_payload=$(jq -n \
      --arg model "$CLAUDE_MODEL" \
      --argjson max_tokens "$MAX_TOKENS" \
      --arg prompt "$prompt_text" \
      '{model: $model, max_tokens: $max_tokens, messages: [{"role": "user", "content": $prompt}]}')
  if [[ $? -ne 0 ]]; then echo "Error: Failed to create JSON payload using jq." >&2; return 1; fi

  # Make the API Call using curl
  local response; response=$(curl -s "$CLAUDE_API_ENDPOINT" \
      -H "x-api-key: $CLAUDE_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$json_payload")
  local curl_exit_status=$?
  if [[ $curl_exit_status -ne 0 ]]; then
      echo "Error: curl command failed to connect or transfer data (status: $curl_exit_status)." >&2
      # Avoid printing potentially huge response on curl error
      # echo "Response: $response" >&2
      return 1
  fi

  # Save response to a temporary file for reliable parsing
  local temp_response_file; temp_response_file=$(mktemp)
  # Setup reliable cleanup for the temp file using a trap
  trap 'rm -f "$temp_response_file" >/dev/null 2>&1; trap - EXIT INT TERM HUP' EXIT INT TERM HUP
  printf "%s" "$response" > "$temp_response_file"

  # --- Check for API Error in Response ---
  # See if the response JSON matches the Anthropic error structure
  if jq -e '.type == "error"' "$temp_response_file" > /dev/null 2>&1; then
      echo "Error: Claude API returned an error." >&2
      local error_type=$(jq -r '.error.type // "unknown_type"' "$temp_response_file")
      local error_message=$(jq -r '.error.message // "No error message provided."' "$temp_response_file")
      echo "  API Error Type: $error_type" >&2
      echo "  API Error Message: $error_message" >&2

      # Provide hints for common errors
      if [[ "$error_type" == "authentication_error" || "$error_message" == *"api-key"* ]]; then
           echo "  -> Check your CLAUDE_API_KEY environment variable (missing, incorrect, expired?)." >&2
      elif [[ "$error_type" == "invalid_request_error" && "$error_message" == *"model"* ]]; then
           echo "  -> Check if the model '$CLAUDE_MODEL' is correct and available to your key." >&2
      elif [[ "$error_type" == "rate_limit_error" ]]; then
           echo "  -> You may have hit an API rate limit or quota." >&2
      fi
      # Cleanup is handled by trap
      return 1 # Exit indicating failure
  fi
  # --- End Check for API Error ---


  # --- Process Successful Response ---
  # Validate overall JSON structure first (though API error check reduces need)
  if ! jq -e '.' "$temp_response_file" > /dev/null 2>&1; then
      echo "Error: Invalid JSON received from API (not a recognized API error)." >&2
      if [[ $(wc -c < "$temp_response_file") -lt 5000 ]]; then # Show small invalid responses
          echo "Raw response:" >&2; cat "$temp_response_file" >&2
      fi
      return 1
  fi

  # Extract the main message content safely
  local assistant_message
  assistant_message=$(jq -re '.content[0].text // ""' "$temp_response_file")
  if [[ $? -ne 0 ]]; then
      echo "Error: Failed to extract '.content[0].text' from JSON response." >&2
      echo "Raw JSON structure:" >&2; jq '.' "$temp_response_file" >&2
      return 1
  fi
  if [[ -z "$assistant_message" && ! "$response" =~ '"text": ""' ]]; then # Distinguish empty text from parsing failure
      echo "Warning: Received empty or non-standard message content from Claude." >&2
  fi

  # --- Feature: Extract <userfix> command, copy to clipboard, hide from output ---
  local fix_command=""
  local display_message="$assistant_message" # Default to showing the full message

  # Check if the specific tags exist
  if [[ "$assistant_message" == *'<userfix>'* && "$assistant_message" == *'</userfix>'* ]]; then
      # Extract content using Zsh parameter expansion
      fix_command=${assistant_message##*<userfix>}
      fix_command=${fix_command%<\/userfix>*}

      # Prepare the message for display: remove the tag block and trim trailing space
      display_message=${assistant_message%<userfix>*}
      display_message=${display_message%%[[:space:]]} # Trim trailing whitespace/newlines

      if [[ -n "$fix_command" ]]; then
          # Determine the appropriate clipboard command
          local clipboard_cmd=""
          local clipboard_tool_name=""
          if command -v pbcopy >/dev/null 2>&1; then
              clipboard_cmd="pbcopy"
              clipboard_tool_name="pbcopy (macOS)"
          elif command -v wl-copy >/dev/null 2>&1; then
              clipboard_cmd="wl-copy"
              clipboard_tool_name="wl-copy (Wayland)"
          elif command -v xclip >/dev/null 2>&1 && [[ -n "$DISPLAY" ]]; then
              clipboard_cmd="xclip -selection clipboard"
              clipboard_tool_name="xclip (X11)"
          elif command -v xsel >/dev/null 2>&1 && [[ -n "$DISPLAY" ]]; then
               clipboard_cmd="xsel --clipboard --input"
               clipboard_tool_name="xsel (X11)"
          fi

          # Attempt to copy if a usable command was found
          if [[ -n "$clipboard_cmd" ]]; then
              # Use printf for safety with special characters in the command
              printf "%s" "$fix_command" | $clipboard_cmd
              if [[ $? -eq 0 ]]; then
                   echo "[Suggested fix command copied to clipboard via $clipboard_tool_name.]" >&2
              else
                   echo "Warning: Found fix command but failed to copy to clipboard (using '$clipboard_cmd')." >&2
                   echo "Suggested fix was:" >&2; echo "$fix_command" >&2 # Show if copy failed
              fi
          else
              echo "Warning: Found fix command but no suitable clipboard tool found (pbcopy, wl-copy, xclip/xsel with \$DISPLAY)." >&2
              echo "Suggested fix was:" >&2; echo "$fix_command" >&2 # Show if no tool
          fi
      # else
          # Optional Debug: echo "Debug: <userfix> tags found but were empty." >&2
      fi
  fi
  # --- End Feature ---

  # Print the final message (potentially without the <userfix> block)
  echo # Add a blank line for separation
  echo "--- Claude's Suggestion ---"
  printf "%s\n" "$display_message" # Use printf for safety
  echo "---------------------------\n"

  # Cleanup trap will remove the temp file automatically
  return 0
}