#!/usr/bin/env python3

# (Keep the last full Python script version that used BEL and current_... session path)
# (Includes imports, marker defs using BEL, get_output_between_markers, main, run_until_complete)
import iterm2
import asyncio
import sys
import os

OSC = "\x1b]"
TERMINATOR = "\x07" # BEL (\007) confirmed from user's script
MARKER_START = f"{OSC}133;B{TERMINATOR}"
MARKER_END_PREFIX = f"{OSC}133;D;" # Includes status, ends with TERMINATOR

async def get_output_between_markers(session, start_marker_code, end_marker_prefix, terminator):
    try:
        contents = await session.async_get_screen_contents()
        if not contents: return None
        text_buffer = ""; i=0
        for i in range(contents.number_of_lines): text_buffer += contents.line(i).string + "\n"
        # Find the LAST occurrence of the end marker prefix
        last_end_prefix_idx = text_buffer.rfind(end_marker_prefix)
        if last_end_prefix_idx == -1: return None
        # Find the last start marker *before* the end marker prefix
        last_start_marker_idx = text_buffer.rfind(start_marker_code, 0, last_end_prefix_idx)
        if last_start_marker_idx == -1: return None
        # Extract text
        start_pos = last_start_marker_idx + len(start_marker_code)
        end_pos = last_end_prefix_idx
        output_block = text_buffer[start_pos:end_pos]
        # print(f"Debug: Found block between markers (len: {len(output_block)}).", file=sys.stderr) # Optional Debug
        return output_block.strip()
    except Exception as e:
        print(f"Error getting/parsing screen contents: {e}", file=sys.stderr); return None

async def main(connection):
    session = None
    try:
        app = await iterm2.async_get_app(connection)
        # Use the 'current' path
        current_window = app.current_terminal_window
        if not current_window: print("Error: No current window.", file=sys.stderr); sys.exit(1)
        current_tab = current_window.current_tab
        if not current_tab: print("Error: No current tab.", file=sys.stderr); sys.exit(1)
        session = current_tab.current_session
        if not session: print("Error: No current session.", file=sys.stderr); sys.exit(1)
        # Call the parsing function
        output = await get_output_between_markers(session, MARKER_START, MARKER_END_PREFIX, TERMINATOR)
        if output is not None: sys.stdout.write(output); sys.stdout.flush()
        # else: print("Debug: Markers not found.", file=sys.stderr) # Optional Debug
    except Exception as e:
        print(f"Error in iTerm2 logic: {e}", file=sys.stderr); sys.exit(1)

if __name__ == "__main__":
    try:
        iterm2.run_until_complete(main)
    except Exception as e:
         print(f"Failed script run: {e}", file=sys.stderr); sys.exit(1)