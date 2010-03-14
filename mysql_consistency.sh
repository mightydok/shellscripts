#!/bin/bash

# Script perform consistency checks on replicated MySQL databases
# Version: 0.5 stable
#
# v0.5 by (c) Vitaliy Okulov - 14.03.2010 - www.vokulov.ru 
# * Добавлена проверка наличия функции FNV_64 для корректной работы mk-table-checksum
#
# v0.4 by (c) Vitaliy Okulov - 12.01.2010 - www.vokulov.ru 
# * Изменены параметры запуска скрипта mk-table-checksum, теперь используется алгоритм XOR и функция
# FNV_64. Для поддержки работы скрипта необходимо установить UDF с поддержкой хеш функции FNV. Исходный
# код UDF доступен по адресу - http://code.google.com/p/maatkit/source/browse/#svn/trunk/udf
# * Исправлен баг с определением slave серверов для проверки и обработкой списка исключений. 
#
# v0.3 by (c) Vitaliy Okulov - 10.01.2010 - www.vokulov.ru 
# * Добавлена поддержка системы монитринга Nagios с помощью демона NSCA.
#
# v0.2 by (c) Vitaliy Okulov - 2010 - www.vokulov.ru 
# * Добавлена поддержка MYSQL_PORT и MYSQL_SOCKET как аргументов к скрипту
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
# 	report-host     = sql1.lan.net
# 	report-port     = 3306
# 
# For Nagios support:
# Report-host variable *MUST* be equal to host_name variable in Nagios monitoring system
# Set nagios_support=1

#########################
# User Defined Variables
#########################

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

MYSQL_HOST="localhost"	# The MASTER database IP
MYSQL_PORT="$2"		# The MASTER database PORT
MYSQL_USER="msandbox"
MYSQL_PASS="msandbox"
MYSQL_SOCKET="$3"
MYSQL_CHECKSUM="test.checksum"	# The database (test) and table (checksum) to store checksum results

# Array of slave IP addresses for exclude from check
# Sample: "|node1|node2|node3"
exclude_slave=""

###
# Nagios support variables
# 1 - enable nagios nsca support
# 0 - disable nagios nsca support
###
nagios_support=0

# Name of the nagios service
NAGIOS_SERVICE_NAME="MySQL Checksum Check"

# Set NSCA host and port
NSCA_HOST="localhost"
NSCA_PORT="5667"

##########################
##########################
##########################

if ((nagios_support));then
    send_nsca="send_nsca"
else
    send_nsca=""
fi

# Mandatory commands for this script to work.
COMMANDS="mysql mk-table-checksum awk mk-table-sync $send_nsca"	

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
        echo $E_CODE
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
# Notify Nagios via send_nsca utility
# Accepted arguments:
# $1 - hostname of server in nagios monitoring
# $2 - nagios plugin exit code (0 - OK, 1 - WARNING, 2 - ERROR, 3 - UNKNOWN)
# $3 - nagios plugin exit message
# $NAGIOS_SERVICE_NAME - is name of the service in nagios web interface
###


notify_mon() {

    if [ "$prog_send_nsca" ];then

        echo -e "$1\t$NAGIOS_SERVICE_NAME\t$2\t$3\n" | $prog_send_nsca $NSCA_HOST -p $NSCA_PORT 1>&/dev/null 2>&1

        if [ $? -eq 0 ];then
            echo "Notification to NSCA succesfully send."
            return 0
        else
            echo "WARNING!!! Notification error occured. Please check NSCA service."
            return 1
        fi
    fi

}

# Check for FNV_64 function in mysql
check_fnv() {

    out=`$prog_mysql --user=$MYSQL_USER --password=$MYSQL_PASS --port=$MYSQL_PORT --socket=$MYSQL_SOCKET -e 'select FNV_64(1234567890);'`

    E_MSG="Plase install FNV_64 function"

    echo $out | grep -q 'FUNCTION FNV_64 does not exist' || return $E_DB_PROBLEM
    echo $out | grep -q '7937388694469814499' || return $E_DB_PROBLEM
}

###
# Check for inconsistent slaves
###
check() {
	##
	# Run the mk_table_checksum command
	##
	E_MSG="Problem running '$prog_mk_table_checksum' at the top of check() function"

    $prog_mk_table_checksum --quiet --algorithm BIT_XOR --chunk-size 500000 --nocrc --empty-replicate-table --float-precision 5 \
    --function FNV_64 --optimize-xor --replicate=$MYSQL_CHECKSUM --sleep-coef=0.3 --socket $MYSQL_SOCKET \
    h=$MYSQL_HOST,P=$MYSQL_PORT,u=$MYSQL_USER,p=$MYSQL_PASS || return $E_DB_PROBLEM

	SLAVE_LIST=`$prog_mysql --user=$MYSQL_USER --password=$MYSQL_PASS --port=$MYSQL_PORT --socket=$MYSQL_SOCKET -e "SHOW SLAVE HOSTS"`

	##
	# Create arrays for the slave ids, hosts, ports
	# To manually create the slave arrays, do something like this instead:
	#
	# slave_ids=(3 4 5)
	# slave_hosts=(172.16.0.63 172.16.0.64 172.16.0.65)
	# slave_ports=(3306 3306 3306)
	#
	##
	slave_ids=(`echo "$SLAVE_LIST" | grep -Ev "Server$exclude_slave" | awk '{ORS = " "} {print $1}'`)
	slave_hosts=(`echo "$SLAVE_LIST" | grep -Ev "Server$exclude_slave" | awk '{ORS = " "} {print $2}'`)
	slave_ports=(`echo "$SLAVE_LIST" | grep -Ev "Server$exclude_slave" | awk '{ORS = " "} {print $3}'`)

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

		CHECKSUM=`$prog_mk_table_checksum --replicate=$MYSQL_CHECKSUM --replicate-check 0 --recursion-method hosts \
                h=$slave_host,P=$slave_port,u=$MYSQL_USER,p=$MYSQL_PASS` || CHECKSUM="not consistent"

		if [ "$CHECKSUM" ]; then
			msg="Replication Slave ID $slave_id on $slave_host:$slave_port is inconsistent. Requires rebuild"
            echo $msg
            notify_mon $slave_host 1 "$msg"
		else
			msg="Replication Slave ID $slave_id on $slave_host:$slave_port is consistent."
            echo $msg
            notify_mon $slave_host 0 "$msg"
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
        check_fnv || error
		check || error
	else
		usage
	fi
else
	error
fi
fi
