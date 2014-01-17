#!/bin/bash
set -eu

REMOTE_SERVER="$1"
PRIVKEY="$2"

COMMON_SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
SSH="ssh -q -o BatchMode=yes $COMMON_SSH_OPTIONS"


if echo "$REMOTE_SERVER" | grep -q "@"; then
    USERNAME=$(echo "$REMOTE_SERVER" | cut -d @ -f 1)
    VM_IP=$(echo "$REMOTE_SERVER" | cut -d @ -f 2)
else
    USERNAME=root
    VM_IP="$REMOTE_SERVER"
fi

function main() {
    wait_till_done
}

function print_dot_and_sleep() {
    if [ -z "${BUILD_NUMBER:-}" ]; then
        echo -n "."
    else
        echo "."
    fi
    sleep 10
}

function wait_for_ssh() {
    while ! echo "kk" | nc -w 1 "$VM_IP" 22 > /dev/null 2>&1; do
            print_dot_and_sleep
    done
}

function wait_till_file_exists() {
    local fname

    fname="$1"

    echo -n "Waiting for $fname"

    while true; do
        wait_for_ssh
        if $SSH -i $PRIVKEY $USERNAME@$VM_IP test -e $fname; then
            break
        else
            print_dot_and_sleep
        fi
    done
    echo "Found!"
}

function wait_till_done() {
    wait_till_file_exists $(./print-stamp-path.sh)
}

main
