#!/bin/bash
set -eux

while ! ping -c 1 xenserver.org > /dev/null 2>&1; do
    sleep 1
done

mkdir -p /mnt/xenserver/
mount /dev/xvda2 /mnt/xenserver/

sed -ie 's,default ubuntu,default xe-serial,g' /mnt/xenserver/boot/extlinux.conf
cat /root/.ssh/authorized_keys > /mnt/xenserver/root/.ssh/authorized_keys

ADDRESS=$(grep -m 1 "address" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
NETMASK=$(grep -m 1 "netmask" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
GATEWAY=$(grep -m 1 "gateway" /etc/network/interfaces | sed -e 's,^ *,,g' | cut -d " " -f 2)
MACADDRESS=$(ifconfig eth0 | sed -ne 's/.*HWaddr \(.*\)$/\1/p' | tr -d " ")
NAMESERVERS=$(cat /etc/resolv.conf | grep nameserver | cut -d " " -f 2 | sort | uniq | tr '\n' , | sed -e 's/,$//g')

cat > /mnt/xenserver/etc/firstboot.d/96-cloud << SET_ENV_WAIT_FOR_XAPI
#!/bin/bash
set -eux

ADDRESS="$ADDRESS"
NETMASK="$NETMASK"
GATEWAY="$GATEWAY"
MACADDRESS="$MACADDRESS"
NAMESERVERS="$NAMESERVERS"

while ! xe host-list --minimal; do
    sleep 1
done
SET_ENV_WAIT_FOR_XAPI

cat root/xenserver-first-cloud-boot.sh >> /mnt/xenserver/etc/firstboot.d/96-cloud

chmod 777 /mnt/xenserver/etc/firstboot.d/96-cloud

umount /mnt/xenserver
reboot
