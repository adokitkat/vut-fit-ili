#!/bin/env bash

# Check for a root privilege
if [ "$(id -u)" -ne 0 ] ; then
    echo "This script must be executed with root privileges." 1>&2
    echo "Please run this script as root (use 'su')." 1>&2
    exit 1
fi

# 0
echo "Installing required software..."
dnf install coreutils lvm2 e2fsprogs
echo ""

# 1
echo "1. Creating 4 loop devices:"
echo "   ~/disk0     ~/disk1     ~/disk2     ~/disk3"
echo "   /dev/loop0  /dev/loop1  /dev/loop2  /dev/loop3"
echo ""
i=0
while [ $i -lt 4 ]
do
    dd if=/dev/zero of=~/disk$i bs=200MB count=1 > /dev/null
    losetup loop$i ~/disk$i #2>&1
    true $(( i++ ))
done
echo ""

# 2 
echo "2. Creating RAID1: /dev/loop0 /dev/loop1 -> /dev/md0"
mdadm --create /dev/md0 --level=1 --metadata=0.90 --raid-devices=2 /dev/loop0 /dev/loop1 #> /dev/null
echo ""
echo "   Creating RAID0: /dev/loop2 /dev/loop3 -> /dev/md1"
mdadm --create /dev/md1 --level=0 --metadata=0.90 --raid-devices=2 /dev/loop2 /dev/loop3 #> /dev/null
echo ""

# 3
echo "3. Creating volume group FIT_vg"
vgcreate FIT_vg /dev/md0 /dev/md1 #2>&1
echo ""

# 4
echo "4. Creating logical volumes FIT_lv1 & FIT_lv2"
lvcreate FIT_vg -n FIT_lv1 -L100M
lvcreate FIT_vg -n FIT_lv2 -L100M
echo ""

# 5
echo "5. Creating EXT4 file system on FIT_lv1"
echo ""
mkfs.ext4 /dev/FIT_vg/FIT_lv1
echo ""

# 6
echo "6. Creating XFS file sstem on FIT_lv2"
echo ""
mkfs.xfs /dev/FIT_vg/FIT_lv2
echo ""

# 7
echo "7. Creating /mnt/test1, /mnt/test2 folders & mounting filesystems"
mkdir /mnt/test1
mount /dev/FIT_vg/FIT_lv1 /mnt/test1 

mkdir /mnt/test2
mount /dev/FIT_vg/FIT_lv2 /mnt/test2
echo ""

# 8
echo "8. Resizing FIT_lv1 logical partition and its filesystem to claim all free space"
echo ""
lvresize -l +100%FREE /dev/FIT_vg/FIT_lv1
echo ""
resize2fs /dev/FIT_vg/FIT_lv1

echo "   Result of 'df -h' command:" 
echo ""
df -h
echo ""

# 9
echo "9. Creating /mnt/test1/big_file from /dev/urandom (can take a while, please wait..."
echo ""
dd if=/dev/urandom of=/mnt/test1/big_file bs=30MB count=10
echo ""
echo "   Checksum:"
sha512sum /mnt/test1/big_file > /mnt/test1/big_file.sha512
cat /mnt/test1/big_file.sha512
echo ""

# 10
echo "10. Emulating faulty disk replacement:"
echo ""
echo " a) Creating 5th loop device ('/dev/loop4') representing a new disk"
echo ""
dd if=/dev/zero of=~/disk4 bs=200MB count=1
losetup loop4 ~/disk4
echo ""
echo " b) Replacing one of the RAID1 loop devices ('/dev/loop0')"
echo ""
mdadm --manage /dev/md0 --fail /dev/loop0
mdadm --manage /dev/md0 --remove /dev/loop0
mdadm --manage /dev/md0 --add /dev/loop4
echo ""
echo " c) Verifying successful recovery (waiting for 5 seconds for the new disk to fully attach & RAID1 to repair itself)"
echo ""
sleep 5
cat /proc/mdstat
echo ""

echo "Success. Everything done :)"
echo ""