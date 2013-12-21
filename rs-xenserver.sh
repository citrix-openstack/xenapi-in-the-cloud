#!/bin/bash
set -exu

VM_NAME="$1"
XENSERVER_PASSWORD="$2"
DEVMODE="${DEVMODE:-false}"

VM_KILLER_SCRIPT="kill-$VM_NAME.sh"

TEMPORARY_PRIVKEY="$VM_NAME.pem"
TEMPORARY_PRIVKEY_NAME="tempkey-$VM_NAME"

if nova keypair-list | grep -q "$TEMPORARY_PRIVKEY_NAME"; then
    echo "ERROR: A keypair already exists with the name $TEMPORARY_PRIVKEY_NAME"
    exit 1
fi

cat > "$VM_KILLER_SCRIPT" << EOF
#!/bin/bash

set -eux
EOF
chmod +x "$VM_KILLER_SCRIPT"

if nova list | grep -q "$VM_NAME"; then
    echo "ERROR: An instance already exists with the name $VM_NAME"
    exit 1
fi

function wait_for_ssh() {
    local host

    host="$1"

    set +x
    echo -n "Waiting for port 22 on ${host}"
    while ! echo "kk" | nc -w 1 "$host" 22 > /dev/null 2>&1; do
            sleep 1
            echo -n "."
    done
    echo "Connectable!"
    set -x
}

nova keypair-add "$TEMPORARY_PRIVKEY_NAME" > "$TEMPORARY_PRIVKEY"
chmod 0600 "$TEMPORARY_PRIVKEY"

cat >> "$VM_KILLER_SCRIPT" << EOF
nova keypair-delete "$TEMPORARY_PRIVKEY_NAME"
rm -f "$TEMPORARY_PRIVKEY"
EOF

nova boot \
	--image "Ubuntu 13.04 (Raring Ringtail) (PVHVM beta)" \
	--flavor "performance1-8" \
	"$VM_NAME" --key-name "$TEMPORARY_PRIVKEY_NAME"

while ! nova list | grep "$VM_NAME" | grep -q ACTIVE; do
	sleep 5
done

VM_ID=$(nova list | grep "$VM_NAME" | tr -d " " | cut -d "|" -f 2)

cat >> "$VM_KILLER_SCRIPT" << EOF
nova delete "$VM_ID"
EOF

while true; do
	VM_IP=$(nova show $VM_ID | grep accessIPv4 | tr -d " " | cut -d "|" -f 3)
	if [ -z "$VM_IP" ]; then
		sleep 1
	else
		break
	fi
done

wait_for_ssh "$VM_IP"

scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" \
    "xenserver-upstart.sh" "root@$VM_IP:xenserver-upstart.sh"

ssh -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP \
    bash /root/xenserver-upstart.sh minvm

while true; do
    wait_for_ssh "$VM_IP"
    if ssh -q \
        -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP \
        test -e /root/done.stamp; then
        break
    fi
    sleep 10
done

cat << EOF
Instance is accessible through ssh:

ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "$TEMPORARY_PRIVKEY" root@$VM_IP
EOF
