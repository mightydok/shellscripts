#!/bin/bash
#  v 0.2
# Author: vitaliy.okulov@gmail.com
# Web: http://vokulov.ru
# License: GPL
# TODO: Rewrite check_tool, create_snapshot, delete_snapshot functions

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/comcom

# Config
VMLIST="testrelo prodrelo"
LXCDIR="/var/lib/lxc"
BACKUPDIR="/backup/vmfiles"
EXCLUDEDIR="/var/lib/mysql"
CURRDATE=$(date +%Y%m%d)
# Set number of FULL backup for each VM in VMLIST that we want to keep in BACKUPDIR
RTNF=5
# Set args vor dar backup tool
DARARGSFULL="-D -Q -z 5"
DARARGSDIFF=$DARARGSFULL" -A"
# Choose: btrfs or lvm
FS="lvm"
LVMDISK="/dev/VG0/LV0"
# Set if u dont have btrfs or lvm partition
DEV=1

function check_tools		{
	# Lets find btrfs tools binary file
	if [ $FS == "btrfs" ] && [ -f "/sbin/btrfs" ];then
		echo "Btrfs tool binary was found"
	else
                echo "You choose BTRFS fs, but btrfs tools are not installed"
		exit 1
	fi

	# Lets check for dar backup tool
	if [ -f "/usr/bin/dar" ];then
		echo "Dar binary was found"
	else
		echo "Please install dar backup tool"
		exit 1
	fi

	# Lets check lvcreate tool
	if [ -f "/sbin/lvcreate" ];then
		echo "lvcreate binary was found"
	else
		 echo "Please install lvm"
		 exit 1
	fi

	return 0

}

function create_snapshot	{
	# Local var
	# Set VM name to first argument
	VM=$1 

        # Check if $DEV flag is off and we use btrfs tool to create snapshot
	if [ $DEV -eq 0 ] && [ $FS == "btrfs" ];then
		# Lets check of snapshot directory already created
		if [ -d $LXCDIR/snap/$VM ];then
			echo "Snapshot for $VM already created, please check snapshot directory"
			exit 1
		fi
		# Lets create read only snapshot
		btrfs subvolume snapshot -r $LXCDIR/$VM/rootfs $LXCDIR/snap/$VM || \
			{ echo "Snapshot of $VM VM failed"; \
				exit 1; }
	fi

	# Check if $DEV flag is off and we use lvcreate tool to create snapshot
	if [ $DEV -eq 0 ] && [ $FS == "lvm" ];then
		# Lets check for old lvm snapshots
		SNAPSHOT=$(lvdisplay | grep $LVMDISK"_snap")
		if [ "$SNAPSHOT" != "" ]
			echo "Snapshot for $VM already created, please check LVM snapshot"
			exit 1
		fi

		# Lets create shapshot
		# Freeze VM
		lxc-freeze -n $VM || \
			{ echo "Cant freeze $VM"; exit 1 }
		# Create LVM snapshot
		lvcreate -L 5G -n $LVMDISK"_snap" -s $LVMDISK || \
	                 { lxc-unfreeze -n $VM; echo "Snapshot of $VM VM failed"; \
	                         exit 1; }

		# Unfreeze VM
		lxc-unfreeze -n $VM || \
			{ echo "Lets try to unfreeze $VM second time"; lxc-unfreeze -n $VM; }

                # Mount LVM to SNAPSHOT directory
		mount $LVMDISK"_snap" $LXCDIR/snap/ || \
				{ echo "Cant mount LVM snapshot to snap folder"; exit 1; } 
		# Lets sync fs state
		sync
		sleep 3
	fi
}

function delete_snapshot	{
	# Local var
        # Set VM name to first argument
	VM=$1

        # Check if $DEV flag is off and we use btrfs tool to create snapshot
	if [ $DEV -eq 0 ] && [ $FS == "btrfs" ];then
                # Lets check of snapshot directory already created
		if [ -d $LXCDIR/snap/$VM ];then
			echo "Found $VM snapshot directory, lets try to delete it"
			btrfs subvolume delete $LXCDIR/snap/$VM || \
				{ echo "Cant delete snapshot for $VM"; \
					exit 1; }
		else
			echo "Strange, but $VM snapshot directory not found, please check snapshot directory"
			exit 1
		fi
	fi

	# Check LVM snapshot
	if [ $DEV -eq 0 ] && [ $FS == "lvm" ];then
		# Lets check for snapshot
		SNAPSHOT=$(lvdisplay | grep $LVMDISK"_snap")
		if [ "$SNAPSHOT" != "" ]
			echo "Found snapshot for $VM, lets try to delete it"
			# Lets umount snapshot
			umount $LXCDIR/snap/
			# Remove snapshot
			lvremove -f $LVMDISK"_snap" || \
			        { echo "Cant delete snapshot for $VM"; \
			                exit 1; }
		else
			echo "Strange, but $VM snapshot not found, please check LVM"
			exit 1
		fi
	fi
}

function check_archive_file	{
	# Local vars
	VM=$1
	TYPE=$2

	# Lets find archive with current date name, or dar will rise error if archive already exist
	BACKUP=$(ls $BACKUPDIR | sort | grep $VM | grep $TYPE | grep $CURRDATE)

	if [ "$BACKUP" != "" ];then
		echo "Backup file for $VM and for $CURRDATE already created. Please check $BACKUPDIR"
		return 1
	else	
		return 0
	fi

}

function create_archive		{
	# Local var
	VM=$1
	TYPE=$2

	# Lets create FULL type of archive
	if [ "$TYPE" == "FULL" ];then
		cd $LXCDIR/snap/ && \
			 dar $DARARGSFULL -c $BACKUPDIR/$VM"_"$CURRDATE"_"$TYPE -P $VM$EXCLUDEDIR
			 return $?
	else
		# We have only 2 types of backups: FULL or DIFF
		TYPE="DIFF"
		# Lets find lastt FULL backup
		LASTFULL=$(ls $BACKUPDIR | sort | grep $VM | grep "FULL" | tail -n 1 | cut -d "." -f 1)
		# Dar need name of last full backup without slice name and extension
		DATEOFFULLBACKUP=$(echo $LASTFULL | cut -d "_" -f 2)

		if [ "$LASTFULL" != "" ];then
			 cd $LXCDIR/snap/ && \
			 	dar $DARARGSDIFF $BACKUPDIR/$LASTFULL -c $BACKUPDIR/$VM"_"$CURRDATE"_"$TYPE"BACKUPFOR_"$DATEOFFULLBACKUP -P $VM$EXCLUDEDIR
		 		return $?
		else
			echo "Cant find last FULL backup for $VM. Please run FULL backup first"
			return 1
		fi
	fi
}

function delete_old_archives    {
	# Local var
        VM=$1

	cd $BACKUPDIR

	# Create reverse ordered array of all FULL archives for that VM
	FULL=($(ls -r | grep $VM | grep "FULL"))
	# Count size of array
	FULLNUM=${#FULL[*]}

	if [ $FULLNUM -gt $RTNF ];then
		# Slice array for more than RTNF number of FULL archives, and remove FULL and DIFF archives with that date
		for OLDARCH in ${FULL[*]:$RTNF};do
			FULLDATE=$(echo $OLDARCH | cut -d "_" -f 2)
        		# Keep  last $RTNF files in backp directory
        		find $BACKUPDIR -type f -name $VM"*"$FULLDATE"*.dar" \
             			| sort \
             			| xargs --no-run-if-empty rm -f || \
	     			{ echo "Cant delete old archive $OLDARCH"; };
		done
	fi

	return 0
}


function main	{
	# Local vars
	TYPE=$1

	for VM in $VMLIST;do

		create_snapshot $VM
		check_archive_file $VM $TYPE
		if [ $? -eq 0 ];then
			create_archive $VM $TYPE
		fi
		delete_snapshot $VM

		# Remove old backup files
        	if [ -d "$BACKUPDIR" ]; then
                	delete_old_archives $VM
	        else
        	        echo "Cant access backup directory"
                	exit 1
	        fi;
	done
}


# Main cycle
# Lets sync fs
sync && sleep 1

check_tools

case $1 in
	"FULL")
		main "FULL"
	;;

	"DIFF")
		main "DIFF"
	;;

	*)
		echo "Usage:"
		echo "FULL - for full backups"
		echo "DIFF - for diff backups"
		echo ""
		echo "You can create cron jobs for this script:"
		echo "0       3       *       *       7       cd /usr/local/comcom; ./backupvm2.sh FULL"
		echo "0       3       *       *       1-6     cd /usr/local/comcom; ./backupvm2.sh DIFF"
		exit 1
	;;
esac

exit 0
