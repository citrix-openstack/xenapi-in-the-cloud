#!/bin/bash
set -xu

VM_NAME="$1"
XENSERVER_PASSWORD="$2"

VM_KILLER_SCRIPT="kill-$VM_NAME.sh"

WORK_DIR=$(mktemp -d)
TEMPORARY_PRIVKEY="$WORK_DIR/tempkey.pem"
TEMPORARY_PRIVKEY_NAME="tempkey-$VM_NAME"

ACCESS_PRIVKEY="$VM_NAME.priv"
ACCESS_PUBKEY="$ACCESS_PRIVKEY.pub"

if nova keypair-list | grep -q "$TEMPORARY_PRIVKEY_NAME"; then
    echo "ERROR: A keypair already exists with the name $TEMPORARY_PRIVKEY_NAME"
    exit 1
fi

cat > "$VM_KILLER_SCRIPT" << EOF
#!/bin/bash

set -eux
EOF
chmod +x "$VM_KILLER_SCRIPT"

# Create a keypair
if [ -e "$ACCESS_PRIVKEY" ] || [ -e "$ACCESS_PUBKEY" ]; then
    echo "ERROR: A local file exists with the name $ACCESS_PRIVKEY or $ACCESS_PUBKEY"
    exit 1
else
    ssh-keygen -t rsa -N "" -f "$ACCESS_PRIVKEY"
    [ -e "$ACCESS_PUBKEY" ]
fi
AUTHORIZED_KEYS="$(cat $ACCESS_PUBKEY)"

cat >> "$VM_KILLER_SCRIPT" << EOF
rm -f $ACCESS_PRIVKEY
rm -f $ACCESS_PUBKEY
EOF

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

ssh -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP \
    bash -s -- "$XENSERVER_PASSWORD" "$AUTHORIZED_KEYS" << EOF
set -eux
halt -p
EOF

sleep 5

nova rescue "$VM_ID"

sleep 5

wait_for_ssh "$VM_IP"

cat shrink-xvdb.sh | ssh -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP \
    bash -s -- "$XENSERVER_PASSWORD" "$AUTHORIZED_KEYS"

sleep 5

nova unrescue "$VM_ID"

sleep 5

wait_for_ssh "$VM_IP"

{
cat << EOF
XENSERVER_PASSWORD="$XENSERVER_PASSWORD"
AUTHORIZED_KEYS="$AUTHORIZED_KEYS"
EOF
cat start-xenserver-installer.sh
} | ssh -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP \
    bash -s -- "$XENSERVER_PASSWORD" "$AUTHORIZED_KEYS"

sleep 30

wait_for_ssh "$VM_IP"

{
cat prepare-to-firstboot.sh
echo "reboot"
} | ssh -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$TEMPORARY_PRIVKEY" root@$VM_IP \
    bash -s -- "$XENSERVER_PASSWORD" "$AUTHORIZED_KEYS"

wait_for_ssh "$VM_IP"

cat << EOF
development breakpoint.

To access XenServer:

ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "$TEMPORARY_PRIVKEY" root@$VM_IP
EOF

exit 0

# Launch a domU and use dom0's IP there
cat replace-dom0-with-a-vm.sh | ssh  -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$ACCESS_PRIVKEY" root@$VM_IP \
    bash -s --

# A small delay is needed here...
sleep 5

wait_for_ssh "$VM_IP"

# Setup the VM as a router
cat setup-routing.sh | ssh  -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$ACCESS_PRIVKEY" user@$VM_IP \
    bash -s --

sleep 5

# Run devstack
{
cat << EOF
XENSERVER_PASSWORD="$XENSERVER_PASSWORD"
EOF
cat start-devstack.sh
} | ssh  -q \
    -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -i "$ACCESS_PRIVKEY" user@$VM_IP \
    bash -s --

cat << EOF
Finished!

To access your machine, type:

ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i "$ACCESS_PRIVKEY" user@$VM_IP
EOF
