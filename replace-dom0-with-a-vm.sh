#!/bin/bash
set -eux

if ! [ -e minvm.xva ]; then
    wget -qO minvm.xva http://downloads.vmd.citrix.com/OpenStack/minvm.xva
fi

VM=$(xe vm-import filename=minvm.xva)

# Rollback Operation for later
cat > remove_machine.sh << REMOVE_MACHINE
#!/bin/bash
set -eux
VBDS=\$(xe vbd-list vm-uuid=$VM params=vdi-uuid --minimal | sed -e 's/,/ /g')

xe vm-uninstall uuid=$VM force=true

for vdi in \$VBDS; do
    xe vdi-destroy uuid=\$vdi
done
REMOVE_MACHINE
chmod +x remove_machine.sh

PIF=$(xe pif-list device=eth0 --minimal)
IP=$(xe pif-param-get param-name=IP uuid=$PIF)
NETMASK=$(xe pif-param-get param-name=netmask uuid=$PIF)
GATEWAY=$(xe pif-param-get param-name=gateway uuid=$PIF)
DNS_ADDRESSES=$(xe pif-param-get param-name=DNS uuid=$PIF | sed -e "s/,/ /g")
HOST_INT_NET=$(xe network-list name-label="Host internal management network" --minimal)
MAC=$(xe pif-param-get param-name=MAC  uuid=$PIF)
ORIGINAL_MGT_NET=$(xe pif-param-get param-name=network-uuid uuid=$PIF)

# Wipe all vifs
for vif in $(xe vif-list vm-uuid=$VM --minimal); do xe vif-destroy uuid=$vif; done

xe vif-create vm-uuid=$VM network-uuid=$HOST_INT_NET device=0

xe vm-start uuid=$VM

while ! ping -c 1 "${VM_IP:-}" > /dev/null 2>&1; do
    VM_IP=$(xe vm-param-get param-name=networks uuid=$VM | sed -e 's,^.*0/ip: ,,g' | sed -e 's,;.*$,,g')
    sleep 1
done

rm -f tempkey
rm -f tempkey.pub

ssh-keygen -f tempkey -P ""

DOMID=$(xe vm-param-get param-name=dom-id uuid=$VM)

# Authenticate myself to the VM
xenstore-write /local/domain/$DOMID/authorized_keys/user "$(cat tempkey.pub)"
xenstore-chmod -u /local/domain/$DOMID/authorized_keys/user r$DOMID

function run_on_vm() {
    ssh \
        -i tempkey \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "user@$VM_IP" "$@"
}

while ! run_on_vm true < /dev/null > /dev/null 2>&1; do
    echo "waiting for key to be activated"
    sleep 1
done

# Execute this script to restore original config
cat > restore.sh << RESTORE
#!/bin/bash
set -eux

xe pif-reconfigure-ip uuid=$PIF mode=static IP=$IP netmask=$NETMASK gateway=$GATEWAY
RESTORE
chmod +x restore.sh

cat > swap.sh << SWAP
#!/bin/bash
set -eux

sleep 1

xe pif-reconfigure-ip uuid=$PIF mode=static IP=0.0.0.0 netmask=0.0.0.0
vif=\$(xe vif-create vm-uuid=$VM network-uuid=$ORIGINAL_MGT_NET mac=$MAC device=1)

xe vm-start uuid=$VM
SWAP
chmod +x swap.sh

{
cat << EOF
auto eth1
iface eth1 inet static
  address $IP
  netmask $NETMASK
  gateway $GATEWAY
  dns-nameservers $DNS_ADDRESSES
EOF
} | run_on_vm "sudo tee -a /etc/network/interfaces"

# Remove authorized_keys updater
echo "" | run_on_vm sudo crontab -

# Make sure user can utenticate to new box as well
cat .ssh/authorized_keys | run_on_vm "cat >> .ssh/authorized_keys"

run_on_vm "sudo halt -p" < /dev/null || true

# Wait till VM halts
while ! xe vm-param-get param-name=power-state uuid=$VM | grep -q "halted"; do
    sleep 1
done

nohup ./swap.sh < /dev/null > /dev/null 2>&1 &

echo "Done, the VM should come up in seconds."
