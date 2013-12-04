set -eux

wget -qO xs62.iso http://downloadns.citrix.com.edgesuite.net/akdlm/8159/XenServer-6.2.0-install-cd.iso
wget -qO staging_vm.xva http://downloads.vmd.citrix.com/OpenStack/minvm.xva

sed -ie 's/^GRUB_HIDDEN_TIMEOUT/#GRUB_HIDDEN_TIMEOUT/g' /etc/default/grub
sed -ie 's/^GRUB_HIDDEN_TIMEOUT_QUIET/#GRUB_HIDDEN_TIMEOUT_QUIET/g' /etc/default/grub
# sed -ie 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=-1/g' /etc/default/grub
sed -ie 's/^.*GRUB_TERMINAL=.*$/GRUB_TERMINAL=console/g' /etc/default/grub


# xsint will be searched
rm -rf /xsint
mkdir /xsinst
mv xs62.iso /xsinst/

mkdir -p /mnt/xs-iso
mount -o loop /xsinst/xs62.iso /mnt/xs-iso
mkdir /opt/xs-install

mv staging_vm.xva /opt/xs-install/

cp -r /mnt/xs-iso/* /opt/xs-install/
umount /mnt/xs-iso

## Remastering the initial root disk

rm -rf /opt/xs-install/install_modded.img
rm -rf /opt/xs-install/install-remaster/
mkdir -p /opt/xs-install/install-remaster/
(
cd /opt/xs-install/install-remaster/
zcat "/opt/xs-install/install.img" | cpio -idum --quiet
cat > answerfile.xml << EOF
<?xml version="1.0"?>
<installation srtype="ext">
<primary-disk preserve-first-partition="true">sda</primary-disk>
<keymap>us</keymap>
<root-password>$XENSERVER_PASSWORD</root-password>
<source type="url">file:///tmp/ramdisk</source>
<admin-interface name="eth0" proto="static">
<ip>192.168.34.2</ip>
<subnet-mask>255.255.255.0</subnet-mask>
<gateway>192.168.34.1</gateway>
</admin-interface>
<timezone>America/Los_Angeles</timezone>
<script stage="filesystem-populated" type="url">file:///postinst.sh</script>
</installation>
EOF

cat > postinst.sh << EOF
#!/bin/sh
touch \$1/tmp/postinst.sh.executed
cp /firstboot.sh \$1/etc/firstboot.d/95-firstboot
chmod 777 \$1/etc/firstboot.d/95-firstboot
sed -ie "s,PasswordAuthentication yes,PasswordAuthentication no,g" \$1/etc/ssh/sshd_config
echo "$AUTHORIZED_KEYS" > \$1/root/.ssh/authorized_keys
EOF

cat > firstboot.sh << EOF
#!/bin/bash

mkdir -p /mnt/ubuntu
mount /dev/sda1 /mnt/ubuntu

KERNEL=\$(ls -1c /mnt/ubuntu/boot/vmlinuz-* | head -1)
INITRD=\$(ls -1c /mnt/ubuntu/boot/initrd.img-* | head -1)

cp \$KERNEL /boot/vmlinuz-ubuntu
cp \$INITRD /boot/initrd-ubuntu

umount /mnt/ubuntu

cat >> /boot/extlinux.conf << UBUNTU
label ubuntu
    LINUX /boot/vmlinuz-ubuntu
    APPEND root=/dev/xvda1 ro quiet splash
    INITRD /boot/initrd-ubuntu
UBUNTU

# Boot Ubuntu next time
sed -ie's,default xe-serial,default ubuntu,g' /boot/extlinux.conf

# Import staging VM
xe vm-import filename=/mnt/ubuntu/opt/xs-install/staging_vm.xva

xe host-management-disable
IFS=,
for pif in \$(xe pif-list --minimal); do
    xe pif-forget uuid=\$pif
done
unset IFS

HOST=\$(xe host-list --minimal)
xe host-disable host=\$HOST

reboot
EOF

find . -print | cpio -o --quiet -H newc | xz --format=lzma > /opt/xs-install/install_modded.img
)

cat > /etc/grub.d/45_xs-install << EOF
cat << XS_INSTALL
menuentry 'XenServer installer' {
    multiboot /opt/xs-install/boot/xen.gz dom0_max_vcpus=1-2 dom0_mem=max:752M com1=115200,8n1 console=com1,vga
    module /opt/xs-install/boot/vmlinuz xencons=hvc console=tty0 console=hvc0 make-ramdisk=/dev/sda1 answerfile=file:///answerfile.xml install
    module /opt/xs-install/install_modded.img
}
XS_INSTALL
EOF

# answerfile=file:///answerfile.xml install 

chmod +x /etc/grub.d/45_xs-install

sed -ie 's/GRUB_DEFAULT=0/GRUB_DEFAULT=4/g' /etc/default/grub
update-grub
reboot

