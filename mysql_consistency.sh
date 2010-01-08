#!/bin/bash

# Version: 0.2
#
## v0.2 by (c) Vitaliy Okulov - 2010 - www.vokulov.ru 
# * Добавлена поддержка MYSQL_PORT и MYSQL_SOCKET
# * Реализован функционал исключений slave серверов из проверки
# * Добавлена поддержка 2-х дополнительных аргументов и проверка их наличия
#
# v0.1 by (c) Alex Williams - 2009 - www.alexwilliams.ca
# * Initial release
#     
#
###############
#
# Slaves *must* have reporting enabled in their my.cnf
# example:
# 	[mysqld]
# 	report-host     = 172.16.0.63
# 	report-port     = 3306


#########################
# User Defined Variables
#########################

MYSQL_HOST="localhost"	# The MASTER database IP
MYSQL_PORT="$2"		# The MASTER database PORT
MYSQL_USER="msandbox"
MYSQL_PASS="msandbox"
MYSQL_SOCKET="$3"
MYSQL_CHECKSUM="test.checksum"	# The database (test) and table (checksum) to store checksum results

# Array of slave IP addresses for exlude from check
exclude_slave=()

# Mandatory commands for this script to work.
COMMANDS="mysql mk-table-checksum awk"	

##############
# Exit Codes
##############

E_INVALID_ARGS=65
E_INVALID_COMMAND=66
E_NO_SLAVES=67
E_DB_PROBLEM=68

##########################
# Script Functions
##########################

error() {
        E_CODE=$?
        echo "Exiting: ERROR ${E_CODE}: $E_MSG"

        exit $E_CODE   
}

usage() {
	echo -e "Usage $0: [options] mysql_port mysql_socket"
	echo -e "\nOptions: "
	echo -e "\t-c\tCheck for inconsistent slave(s)"
	echo -e "\tmysql_port - port of mysql server"
	echo -e "\tmysql_socket - path to mysql server socket"
	echo -e ""

	exit $E_INVALID_ARGS
}

##
# Perform sanity checks before allowing the script to run
##
sanity_checks() {
	##
	# Verify if commands exist
	##
	for command in $COMMANDS
	do
		##
		# Set the full path of the command
		##
		PROG=`which $command`
		if [ ! ${PROG} ]; then
			##
			# Error message if the command doesn't exist
			##
			E_MSG="missing command '$command'"
			return $E_INVALID_COMMAND
		else
			##
			# Create a variable (i.e: $prog_tar)
			# 	substitutes all - for _ (i.e: prog_mk-audit becomes prog_mk_audit)
			##
			E_MSG="Command not found"
			eval prog_${command//-/_}=${PROG} || return
		fi
	done
}


###
# Check for inconsistent slaves
###
check() {
	##
	# Run the mk_table_checksum command
	##
	E_MSG="Problem running '$prog_mk_table_checksum' at the top of check() function"

	$prog_mk_table_checksum --quiet --replicate=$MYSQL_CHECKSUM --create-replicate-table --socket $MYSQL_SOCKET \
        --empty-replicate-table h=$MYSQL_HOST,P=$MYSQL_PORT,u=$MYSQL_USER,p=$MYSQL_PASS || return $E_DB_PROBLEM

	SLAVE_LIST=`$prog_mysql --user=$MYSQL_USER --password=$MYSQL_PASS --port=$MYSQL_PORT --socket=$MYSQL_SOCKET -e "SHOW SLAVE HOSTS\G"`

	##
	# Create arrays for the slave ids, hosts, ports
	# To manually create the slave arrays, do something like this instead:
	#
	# slave_ids=(3 4 5)
	# slave_hosts=(172.16.0.63 172.16.0.64 172.16.0.65)
	# slave_ports=(3306 3306 3306)
	#
	##
	slave_ids=(`echo "$SLAVE_LIST" | grep "Server_id" | $prog_awk -F ": " '{ print $2 }'`)
	slave_hosts=(`echo "$SLAVE_LIST" | grep "Host" | $prog_awk -F ": " '{ print $2 }'`)
	slave_ports=(`echo "$SLAVE_LIST" | grep "Port" | $prog_awk -F ": " '{ print $2 }'`)
	ids4delete=()


    ##
    # Check slave_* arrays for exclude slave IP addresses
    ##

    for excl in ${exclude_slave[@]}
    do
        for (( i = 0 ; i < ${#slave_hosts[@]} ; i++ ))
        do
            if [ "$excl" == "${slave_hosts[$i]}" ]; then
                echo "Found IP: $excl from exclude list, with ID: $i"
                ids4delete[${#ids4delete[*]}]="$i"
                break
            fi
        done
    done

    ##
    # Delete values from slave_* arrays if there is any data in ids4delete array
    ##

    for ids in ${ids4delete[@]}
    do
        unset slave_ids[$ids]
        unset slave_hosts[$ids]
        unset slave_ports[$ids]
        echo "Delete SLAVE server with ID: $ids from all arrays"
    done
    unset ids4delete

	##
	# Define the number of slaves by the number of entries in the slave_ids[] array
	##
	num_slaves=${#slave_ids[*]}

	index=0

	if [ $num_slaves -eq 0 ]; then
		echo "No Replication Slaves appear in 'SHOW SLAVE HOSTS'"
		return $E_NO_SLAVES
	fi

	##
	# verify the checksums on each replicated slave
	##
	while [ "$index" -lt "$num_slaves" ]
	do
		slave_id=${slave_ids[$index]}
		slave_host=${slave_hosts[$index]}
		slave_port=${slave_ports[$index]}

		CHECKSUM=`$prog_mk_table_checksum --replicate=$MYSQL_CHECKSUM --replicate-check 2 \
                h=$slave_host,P=$slave_port,u=$MYSQL_USER,p=$MYSQL_PASS` || CHECKSUM="not consistent"

		if [ "$CHECKSUM" ]; then
			echo "Replication Slave ID $slave_id on $slave_host:$slave_port is inconsistent. Requires rebuild"
		else
			echo "Replication Slave ID $slave_id on $slave_host:$slave_port is consistent."
		fi
		let "index = $index + 1"
	done
}

if [ $# -ne 3 ]; then
    echo -e "\nError: Please specify mysql_port and mysql_socket\n"
    usage
    exit 0
else

for arg in "$@"

do
    case $1 in
        -c) arg_c=true;;
        *) usage;;
    esac
done

if sanity_checks; then
	sanity=true

	if [ $arg_c ]; then
		echo "Checking consistency"
		check || error
	else
		usage
	fi
else
	error
fi
fi
