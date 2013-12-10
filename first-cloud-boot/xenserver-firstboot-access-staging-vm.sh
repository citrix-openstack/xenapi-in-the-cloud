#!/bin/bash
set -eux

while ! xe host-list --minimal; do
    sleep 1
done

. /root/cloud-settings

xe pif-introduce device=eth0 host-uuid=$(xe host-list --minimal) mac=$MACADDRESS

PIF=$(xe pif-list device=eth0 --minimal)
HOST_INT_NET=$(xe network-list name-label="Host internal management network" --minimal)

ORIGINAL_MGT_NET=$(xe pif-param-get param-name=network-uuid uuid=$PIF)
NEW_MGT_NET=$(xe network-create name-label=mgt name-description=mgt)
sleep 1
NEW_MGT_VLAN=$(xe vlan-create vlan=100 pif-uuid=$PIF network-uuid=$NEW_MGT_NET)
NEW_PIF=$(xe pif-list VLAN=100 device=eth0 --minimal)
VM=$(xe vm-list name-label="Staging VM" --minimal)
DNS_ADDRESSES=$(echo "$NAMESERVERS" | sed -e "s/,/ /g")

xe pif-reconfigure-ip \
    uuid=$PIF \
    mode=static \
    IP=0.0.0.0 \
    netmask=0.0.0.0

xe pif-reconfigure-ip \
    uuid=$NEW_PIF \
    mode=static \
    IP=192.168.33.2 \
    netmask=255.255.255.0 \
    gateway=192.168.33.1 \
    DNS=192.168.33.1

xe host-management-reconfigure pif-uuid=$NEW_PIF

# Create vifs for the staging VM
xe vif-create vm-uuid=$VM network-uuid=$HOST_INT_NET device=0
xe vif-create vm-uuid=$VM network-uuid=$ORIGINAL_MGT_NET mac=$MACADDRESS device=1
xe vif-create vm-uuid=$VM network-uuid=$NEW_MGT_NET device=2

xe vm-start uuid=$VM

# Wait until Staging VM is accessible
while ! ping -c 1 "${VM_IP:-}" > /dev/null 2>&1; do
    VM_IP=$(xe vm-param-get param-name=networks uuid=$VM | sed -e 's,^.*0/ip: ,,g' | sed -e 's,;.*$,,g')
    sleep 1
done

rm -f tempkey
rm -f tempkey.pub
ssh-keygen -f tempkey -P ""

DOMID=$(xe vm-param-get param-name=dom-id uuid=$VM)

# Authenticate temporary key to Staging VM
xenstore-write /local/domain/$DOMID/authorized_keys/root "$(cat tempkey.pub)"
xenstore-chmod -u /local/domain/$DOMID/authorized_keys/root r$DOMID

function run_on_vm() {
    ssh \
        -i tempkey \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        "root@$VM_IP" "$@"
}

while ! run_on_vm true < /dev/null > /dev/null 2>&1; do
    echo "waiting for key to be activated"
    sleep 1
done

{
cat << EOF
auto eth1
iface eth1 inet static
  address $ADDRESS
  netmask $NETMASK
  gateway $GATEWAY
  dns-nameservers $DNS_ADDRESSES

auto eth2
  iface eth2 inet static
  address 192.168.33.1
  netmask 255.255.255.0
EOF
} | run_on_vm "tee -a /etc/network/interfaces"

# Configure shorewall and dnsmasq
run_on_vm "bash -s" << EXECUTE_ON_STAGING_VM
tee /etc/shorewall/interfaces << EOF
net      eth1           detect          dhcp,tcpflags,nosmurfs
lan      eth2           detect          dhcp
EOF

tee /etc/shorewall/zones << EOF
fw      firewall
net     ipv4
lan     ipv4
EOF

tee /etc/shorewall/policy << EOF
lan             net             ACCEPT
lan             fw              ACCEPT
fw              net             ACCEPT
fw              lan             ACCEPT
net             all             DROP
all             all             REJECT          info
EOF

tee /etc/shorewall/rules << EOF
ACCEPT  net                     fw      tcp     22
EOF


tee /etc/shorewall/masq << EOF
eth1 eth2
EOF

# Turn on IP forwarding
sed -i /etc/shorewall/shorewall.conf \
    -e 's/IP_FORWARDING=.*/IP_FORWARDING=On/g'

# Enable shorewall on startup
sed -i /etc/default/shorewall \
    -e 's/startup=.*/startup=1/g'

# Configure dnsmasq
tee -a /etc/dnsmasq.conf << EOF
interface=eth2
dhcp-range=192.168.33.50,192.168.33.150,12h
bind-interfaces
EOF
EXECUTE_ON_STAGING_VM

# Remove authorized_keys updater
echo "" | run_on_vm crontab -

# Disable temporary private key and reboot
cat /root/.ssh/authorized_keys | run_on_vm "cat > /root/.ssh/authorized_keys && reboot"

# Enable password based authentication on XenServer
sed -ie "s,PasswordAuthentication no,PasswordAuthentication yes,g" /etc/ssh/sshd_config
/etc/init.d/sshd restart
