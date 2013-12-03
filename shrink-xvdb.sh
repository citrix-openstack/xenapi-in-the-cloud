set -eux

fsck -n /dev/xvdb1
tune2fs -O ^has_journal /dev/xvdb1
e2fsck -fp /dev/xvdb1
resize2fs /dev/xvdb1 4G

# Number of 4k blocks
NUMBER_OF_BLOCKS=$(tune2fs -l /dev/xvdb1 | grep "Block count" | tr -d " " | cut -d":" -f 2)

# Convert them to 512 byte sectors
SIZE_OF_PARTITION=$(expr $NUMBER_OF_BLOCKS * 8)

sfdisk -d /dev/xvdb | sed -e "s,[0-9]\{8\},$SIZE_OF_PARTITION,g" | sfdisk /dev/xvdb
partprobe /dev/xvdb
tune2fs -j /dev/xvdb1

sync 
halt -p
