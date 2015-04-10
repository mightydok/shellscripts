#!/bin/bash
#  v 0.1

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/comcom

set -u
set -e

# Config
VMLIST="testrelo prodrelo"
LXCDIR="/var/lib/lxc"
BACKUPDIR="/backup/vmfiles"
CURRDATE=`date +%Y%m%d`
RTNF=5
DEV=1

# Remove old backups
function delete_old_files {
	# $1 - $BACKUPDIR
        # $2 - $RTNF
        # $3 - $VM

	# Keep  last $RTNF files in backp directory
        find $1 -type f -name "*$3*.*.dar" \
             | sort | head -n -$2 \
             | xargs --no-run-if-empty rm -f


	# Exit of something wrong
        if [ $? -ne 0 ];then
                echo "Something wrong..."
                exit 1
        fi
}

# Main cycle
for VM in $VMLIST;do
	# Sync fs
        sync && sleep 3

	# Check if $DEV flag is on
	if [ $DEV -eq 0 ];then
	        btrfs subvolume snapshot -r $LXCDIR/$VM/rootfs $LXCDIR/snap/$VM || \
			{ echo "Snapshot of $VM VM failed"; \
			  	exit 1; }
	fi

        sleep 5

	# Pack $VM dir and exclude mysql directory
        cd $LXCDIR/snap/
        dar -D -Q -v -z 5 -c $BACKUPDIR/$VM"_"$CURRDATE -P $VM/var/lib/mysql || \
                { echo "Backup of $VM VM FAILED"; \
			btrfs subvolume delete $LXCDIR/snap/$VM; \
			exit 1; }

	# Check if $DEV flag is on
	if [ $DEV -eq 0 ];then
        	btrfs subvolume delete $LXCDIR/snap/$VM
	fi

	# Remove old backup files
        if [ -d "$BACKUPDIR" ]; then
                delete_old_files $BACKUPDIR $RTNF $VM
        else
                echo "Cant access backup directory."
                exit 1
        fi;
done

exit 0
