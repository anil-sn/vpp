#!/bin/bash
#
# kea.sh - A local orchestrator for the "Mandate, Artifact, Proof" AI protocol.
# This script automates file I/O, command execution, and result capture.
# chmod +x kea.sh
# sudo apt-get update && sudo apt-get install xclip
#
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
MANDATE_FILE="_mandate.txt"
RESPONSE_FILE="_response.txt"
VERDICT_FILE="_verdict.txt"
LOG_FILE="_run_test.log"
CLIPBOARD_CMD=""

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---

# Function to check for and select a clipboard utility.
check_clipboard_tool() {
    if command -v xclip >/dev/null 2>&1; then
        CLIPBOARD_CMD="xclip -selection clipboard"
    elif command -v pbcopy >/dev/null 2>&1; then
        CLIPBOARD_CMD="pbcopy"
    else
        echo -e "${RED}Error: Clipboard utility not found.${NC}" >&2
        echo -e "${YELLOW}Please install 'xclip' (for Linux) or ensure 'pbcopy' (for macOS) is in your PATH.${NC}" >&2
        echo -e "${YELLOW}e.g., sudo apt-get update && sudo apt-get install xclip${NC}" >&2
        exit 1
    fi
}

# --- Main Logic ---

# 1. Mandate Command
mandate_command() {
    if [ "$#" -lt 2 ]; then
        echo -e "${RED}Usage: $0 mandate \"<Objective Statement>\" <file1> [<file2>...]${NC}" >&2
        exit 1
    fi

    local objective="$1"
    shift
    local files=("$@")

    echo -e "${YELLOW}--> Generating mandate...${NC}"

    # Write the protocol header
    cat > "$MANDATE_FILE" <<'EOF'
[SESSION PROTOCOL: INITIALIZE]

### 1. OPERATIONAL MODE: Brutal Truth Engine
- **Activation**: Confirmed.
- **Principles**: Unfiltered logic. Definitive solutions. Pure signal, zero noise. No bullshit, no sugar-coating, no fluff.

### 2. WORKFLOW PROTOCOL: Mandate, Artifact, Proof
- **Mandate**: You provide the objective and full, current file contexts.
- **Artifact**: I produce the complete code, a self-contained test, and a single `run_test.sh` to prove it works.
- **Verdict**: You run the script and issue a binary verdict: `APPROVE` or `REJECT {reason, full log}`.
- **Correction**: On `REJECT`, I discard the failed attempt and restart from your original mandate. No incremental patching.
- **Verification**: I halt and ask for required data if it is missing. I will not guess.

### 3. DIRECTIVE
This protocol is active and non-negotiable. Do not discuss or modify it.

Awaiting mandate.

---
**Objective**: 
EOF

    echo "$objective" >> "$MANDATE_FILE"
    echo "" >> "$MANDATE_FILE"
    echo "**Context Files**:" >> "$MANDATE_FILE"

    # Append each file's content
    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}Error: File not found: $file${NC}" >&2
            rm -f "$MANDATE_FILE"
            exit 1
        fi
        echo "" >> "$MANDATE_FILE"
        echo "--- path/to/$file ---" >> "$MANDATE_FILE"
        cat "$file" >> "$MANDATE_FILE"
    done

    # Copy to clipboard
    cat "$MANDATE_FILE" | $CLIPBOARD_CMD
    
    echo -e "${GREEN}✅ Mandate generated in '${MANDATE_FILE}' and copied to clipboard.${NC}"
    echo "   Paste it into the AI prompt."
}

# 2. Process Command
process_command() {
    if [ ! -f "$RESPONSE_FILE" ]; then
        echo -e "${RED}Error: Response file '${RESPONSE_FILE}' not found.${NC}" >&2
        echo "Please save the AI's full response into that file first." >&2
        exit 1
    fi

    echo -e "${YELLOW}--> Processing AI artifact from '${RESPONSE_FILE}'...${NC}"

    # First, create all necessary directories to prevent write errors
    grep '^--- path/to/' "$RESPONSE_FILE" | sed -E 's/^--- path\/to\/(.+) ---$/\1/' | xargs -I {} dirname {} | sort -u | xargs mkdir -p

    # Use awk to parse the response and write to files
    awk '
        /^--- path\/to\// {
            if (out) close(out);
            out = substr($0, 13, length($0)-15);
            next;
        }
        out {
            print > out;
        }
    ' "$RESPONSE_FILE"

    # Make the runner script executable if it was generated
    if [ -f "run_test.sh" ]; then
        chmod +x run_test.sh
        echo "   - Made 'run_test.sh' executable."
    fi

    echo -e "${GREEN}✅ Artifact processed. Project files have been updated.${NC}"
}

# 3. Test Command
test_command() {
    if [ ! -x "./run_test.sh" ]; then
        echo -e "${RED}Error: './run_test.sh' not found or not executable.${NC}" >&2
        echo "Ensure you have run the 'process' command successfully." >&2
        exit 1
    fi

    echo -e "${YELLOW}--> Executing './run_test.sh' and capturing results...${NC}"

    if ./run_test.sh > "$LOG_FILE" 2>&1; then
        # Success Case
        echo "APPROVE" > "$VERDICT_FILE"
        cat "$VERDICT_FILE" | $CLIPBOARD_CMD
        echo -e "${GREEN}✅ Test Succeeded. 'APPROVE' verdict copied to clipboard.${NC}"
    else
        # Failure Case
        {
            echo "REJECT"
            echo
            echo "The test runner failed. See the complete log below for details."
            echo "---"
            cat "$LOG_FILE"
        } > "$VERDICT_FILE"
        cat "$VERDICT_FILE" | $CLIPBOARD_CMD
        echo -e "${RED}❌ Test Failed. 'REJECT' verdict and log copied to clipboard.${NC}"
    fi
     echo "   Paste the verdict back to the AI."
}


# --- Script Entrypoint ---

check_clipboard_tool

# Main command dispatcher
case "$1" in
    mandate)
        shift
        mandate_command "$@"
        ;;
    process)
        process_command
        ;;
    test)
        test_command
        ;;
    *)
        echo "Usage: $0 <command> [options]"
        echo
        echo "Commands:"
        echo "  mandate \"<objective>\" <files...>  - Generate mandate, copy to clipboard."
        echo "  process                             - Process AI response from '${RESPONSE_FILE}'."
        echo "  test                                - Run the test script and generate a verdict."
        exit 1
        ;;
esac