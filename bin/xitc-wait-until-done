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
    local stamp_file

    stamp_file=$(xitc-print-stamp-path)

    cat << EOF
Waiting for stamp file [$stamp_file]
    ADDRESS : $VM_IP
    USERNAME: $USERNAME

 X - failed to connect to port 22
 . - stamp file did not exist
EOF

    wait_till_file_exists $(xitc-print-stamp-path)
    echo "Found!"
}

function print_dot_and_sleep() {
    local dot_type

    dot_type="$1"

    if [ -z "${BUILD_NUMBER:-}" ]; then
        echo -n "$dot_type"
    else
        echo "$dot_type"
    fi
    sleep 10
}

function wait_for_ssh() {
    while ! echo "kk" | nc -w 1 "$VM_IP" 22 > /dev/null 2>&1; do
            print_dot_and_sleep X
    done
}

function wait_till_file_exists() {
    local fname

    fname="$1"


    while true; do
        wait_for_ssh
        if $SSH -i $PRIVKEY $USERNAME@$VM_IP test -e $fname; then
            break
        else
            print_dot_and_sleep .
        fi
    done
}

main
