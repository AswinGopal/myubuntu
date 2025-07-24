#!/bin/sh

KEY_PATH=""

# Check if SSH agent is running and usable
is_agent_running() {
    [ -n "$SSH_AUTH_SOCK" ] && ssh-add -l >/dev/null 2>&1
}

# Start SSH agent
start_agent() {
    echo "Starting ssh-agent..."
    eval "$(ssh-agent -s)" > /dev/null
}

# Add key to agent
add_key() {
    if [ -f "$KEY_PATH" ]; then
        echo "Adding SSH key..."
        ssh-add "$KEY_PATH"
    else
        echo "SSH key not found: $KEY_PATH" >&2
    fi
}

main() {
    if ! is_agent_running; then
        start_agent
        add_key
    else
        echo "SSH agent already running with keys loaded."
    fi
}

main
