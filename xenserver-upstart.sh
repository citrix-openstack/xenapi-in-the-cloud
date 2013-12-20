#!/bin/bash
set -eux

THIS_FILE="/root/xenserver-upstart.sh"
STATE_FILE="${THIS_FILE}.state"

function set_state() {
    local state

    state="$1"

    echo "$state" > $STATE_FILE
}

function get_state() {
    if [ -e "$STATE_FILE" ]; then
        cat $STATE_FILE
    else
        echo "START"
    fi
}

function create_resizing_initramfs_config() {
    cat > /usr/share/initramfs-tools/hooks/resize << EOF
#!/bin/sh

set -e

PREREQ=""

prereqs () {
	echo "\${PREREQ}"
}

case "\${1}" in
	prereqs)
		prereqs
		exit 0
		;;
esac

. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/resize2fs
copy_exec /sbin/e2fsck
copy_exec /usr/bin/expr
copy_exec /sbin/tune2fs
copy_exec /bin/grep
copy_exec /usr/bin/tr
copy_exec /usr/bin/cut
copy_exec /sbin/sfdisk
copy_exec /sbin/partprobe
copy_exec /bin/sed
EOF
    chmod +x /usr/share/initramfs-tools/hooks/resize

    cat > /usr/share/initramfs-tools/scripts/local-premount/resize << EOF
#!/bin/sh -e

PREREQ=""

# Output pre-requisites
prereqs()
{
        echo "\$PREREQ"
}

case "\$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /scripts/functions

log_begin_msg "Resize started"
touch /etc/mtab

tune2fs -O ^has_journal /dev/xvda1
e2fsck -fp /dev/xvda1
resize2fs /dev/xvda1 4G

# Number of 4k blocks
NUMBER_OF_BLOCKS=\$(tune2fs -l /dev/xvda1 | grep "Block count" | tr -d " " | cut -d":" -f 2)

# Convert them to 512 byte sectors
SIZE_OF_PARTITION=\$(expr \$NUMBER_OF_BLOCKS \\* 8)

# Sleep - otherwise sfdisk complains "BLKRRPART: Device or resource busy"
sleep 2

sfdisk -d /dev/xvda | sed -e "s,[0-9]\{8\},\$SIZE_OF_PARTITION,g" | sfdisk /dev/xvda
partprobe /dev/xvda
tune2fs -j /dev/xvda1

sync

log_end_msg "Resize finished"

EOF
    chmod +x /usr/share/initramfs-tools/scripts/local-premount/resize
}


function delete_resizing_initramfs_config() {
    rm -f /usr/share/initramfs-tools/hooks/resize
    rm -f /usr/share/initramfs-tools/scripts/local-premount/resize
}

function update_initramfs() {
    update-initramfs -u
}

function create_upstart_config() {
    cat > /etc/init/xenserver.conf << EOF
start on stopped rc RUNLEVEL=[2345]

task

script
    /bin/bash $THIS_FILE
    reboot
end script
EOF
}

function create_done_file() {
    touch /root/done.stamp
}

case "$(get_state)" in
    "START")
        create_upstart_config
        create_resizing_initramfs_config
        update_initramfs
        delete_resizing_initramfs_config
        set_state "RESIZED"
        reboot
        ;;
    "RESIZED")
        create_done_file
        exit 1
        ;;
esac
