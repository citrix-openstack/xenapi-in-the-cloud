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

cat > /mnt/xenserver/etc/firstboot.d/96-cloud << ON_XS
#!/bin/bash
set -eux

while ! xe host-list --minimal; do
    sleep 1
done

xe pif-introduce device=eth0 host-uuid=\$(xe host-list --minimal) mac=$MACADDRESS
xe pif-reconfigure-ip uuid=\$(xe pif-list device=eth0 --minimal) mode=static IP=$ADDRESS netmask=$NETMASK gateway=$GATEWAY DNS=$NAMESERVERS
xe host-management-reconfigure pif-uuid=\$(xe pif-list device=eth0 --minimal)
ON_XS
chmod 777 /mnt/xenserver/etc/firstboot.d/96-cloud

umount /mnt/xenserver
reboot
