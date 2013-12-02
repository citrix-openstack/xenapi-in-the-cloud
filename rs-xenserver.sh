#!/bin/bash
set -xu

VM_NAME="$1"
XENSERVER_PASSWORD="$2"

WORK_DIR=$(mktemp -d)
TEMPORARY_PRIVKEY="$WORK_DIR/tempkey.pem"
TEMPORARY_PRIVKEY_NAME="tempkey-$VM_NAME"

ACCESS_PRIVKEY="$VM_NAME.priv"
ACCESS_PUBKEY="$ACCESS_PRIVKEY.pub"

if nova keypair-list | grep -q "$TEMPORARY_PRIVKEY_NAME"; then
    echo "ERROR: A keypair already exists with the name $TEMPORARY_PRIVKEY_NAME"
    exit 1
fi

# Create a keypair
if [ -e "$ACCESS_PRIVKEY" ] || [ -e "$ACCESS_PUBKEY" ]; then
    echo "ERROR: A local file exists with the name $ACCESS_PRIVKEY or $ACCESS_PUBKEY"
    exit 1
else
    ssh-keygen -t rsa -N "" -f "$ACCESS_PRIVKEY"
    [ -e "$ACCESS_PUBKEY" ]
fi
AUTHORIZED_KEYS="$(cat $ACCESS_PUBKEY)"

if nova list | grep -q "$VM_NAME"; then
    echo "ERROR: An instance already exists with the name $VM_NAME"
    exit 1
fi

function wait_for_ssh() {
    local host

    host="$1"

    while ! echo "kk" | nc -w 1 "$host" 22 > /dev/null 2>&1; do
            sleep 1
    done
}

nova keypair-add "$TEMPORARY_PRIVKEY_NAME" > "$TEMPORARY_PRIVKEY"
chmod 0600 "$TEMPORARY_PRIVKEY"

nova boot \
	--image "Ubuntu 13.04 (Raring Ringtail) (PVHVM beta)" \
	--flavor "performance1-8" \
	"$VM_NAME" --key-name "$TEMPORARY_PRIVKEY_NAME"

while ! nova list | grep "$VM_NAME" | grep -q ACTIVE; do
	sleep 5
done

VM_ID=$(nova list | grep "$VM_NAME" | tr -d " " | cut -d "|" -f 2)

while true; do
	VM_IP=$(nova show $VM_ID | grep accessIPv4 | tr -d " " | cut -d "|" -f 3)
	if [ -z "$VM_IP" ]; then
		sleep 1
	else
		break
	fi
done

wait_for_ssh "$VM_IP"

cat start-xenserver-installer.sh | ssh -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP \
    bash -s -- "$XENSERVER_PASSWORD" "$AUTHORIZED_KEYS"

sleep 30

wait_for_ssh "$VM_IP"

# Launch a domU and use dom0's IP there
cat replace-dom0-with-a-vm.sh | ssh  -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$ACCESS_PRIVKEY" root@$VM_IP \
    bash -s --

wait_for_ssh "$VM_IP"

# Setup the VM as a router
cat setup-routing.sh | ssh  -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$ACCESS_PRIVKEY" user@$VM_IP \
    bash -s --
