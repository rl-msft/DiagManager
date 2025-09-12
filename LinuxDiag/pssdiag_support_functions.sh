#!/bin/bash

script_version="20250901"
MSSQL_CONF="/var/opt/mssql/mssql.conf"
outputdir="$PWD/output"
#SQL_LOG_DIR=${SQL_LOG_DIR:-"/var/opt/mssql/log"}
pssdiag_log="$outputdir/pssdiag.log"

# Arguments:
#   1. Title
#   2. Command
#
function capture_system_info_command()
{
    title=$1
    command=$2

    echo "=== $title ===" >> $infolog_filename
    eval "$2 2>&1" >> $infolog_filename
    echo "" >> $infolog_filename
}

find_sqlcmd() 
{
	SQLCMD=""
	# Try known sqlcmd paths in order
	if [ -x /opt/mssql-tools/bin/sqlcmd ]; then
		SQLCMD="/opt/mssql-tools/bin/sqlcmd"
	elif [ -x /opt/mssql-tools18/bin/sqlcmd ]; then
		SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
	else
		SQLCMD=""
	fi
}

get_sql_listen_port()
{
CONFIG_NAME="tcpport"
DEFAULT_VALUE="1433"

if [[ "$1" == "host_instance" ]]; then
	FILE_EXISTS=$(sh -c "test -f ${MSSQL_CONF} && echo 'exists' || echo 'not exists'")
	if [[ "${FILE_EXISTS}" == "exists" ]]; then
        	tcpport=`cat ${MSSQL_CONF} | grep -i -w ${CONFIG_NAME} | sed 's/ *= */=/g' | awk -F '=' '{ print $2}'`
        	if [[ ${tcpport} != "" ]] ; then
                	echo "${tcpport}"
        	else
                	echo "${DEFAULT_VALUE}"
        	fi
	else
		echo "${DEFAULT_VALUE}"
	fi
fi

if [[ "$1" == "container_instance" ]]; then
	FILE_EXISTS=$(docker exec ${3} sh -c "test -f ${MSSQL_CONF} && echo 'exists' || echo 'not exists'")
	if [[ "${FILE_EXISTS}" == "exists" ]]; then
		tcpportline=$(docker exec ${3} sh -c "cat ${MSSQL_CONF} | grep -i -w ${CONFIG_NAME}")
		tcpport=`echo ${tcpportline} | sed 's/ *= */=/g' | awk -F '=' '{ print $2}'`
        	if [[ ${tcpport} != "" ]] ; then
                	echo "${tcpport}"
        	else
                	echo "${DEFAULT_VALUE}"
        	fi
	else
		echo "${DEFAULT_VALUE}"
	fi
fi
}

get_docker_mapped_port()
{
               
   dockername=$(docker inspect -f "{{.Name}}" $dockerid | tail -c +2)
   #echo "collecting docker mapped port from sql container instance : $dockername"
   SQL_LISTEN_PORT=$(get_sql_listen_port "container_instance" "2" $dockerid)
   #dynamically build?
   inspectcmd="docker inspect --format='{{(index (index .HostConfig.PortBindings \""
   inspectcmd+=$SQL_LISTEN_PORT
   inspectcmd+="/tcp\") 0).HostPort}}' $dockerid"
   dockerport=`eval $inspectcmd`
   # echo "${dockerport}"
}

#Checking host instance status
get_host_instance_status() 
{
    is_host_instance_service_installed="NO"
    is_host_instance_service_enabled="NO"
    is_host_instance_service_active="NO"
    is_host_instance_process_running="NO"

    # Check if system uses systemd
    if [[ "$(readlink /sbin/init)" == *systemd* ]]; then
        if systemctl list-units --all | grep -q mssql-server.service; then
            is_host_instance_service_installed="YES"

            if systemctl -q is-enabled mssql-server; then
                is_host_instance_service_enabled="YES"
            fi

            if systemctl -q is-active mssql-server; then
                is_host_instance_service_active="YES"
            fi

			if pgrep -f "/opt/mssql/bin/sqlservr" >/dev/null 2>&1; then
				is_host_instance_process_running="YES"
			fi
        fi
    fi
}


#Checking containers status, including podman
get_container_instance_status()
{
	is_container_runtime_service_installed="NO"
	is_container_runtime_service_enabled="NO"
	is_container_runtime_service_active="NO"
	is_docker_sql_containers="NO"
	is_podman_sql_containers="NO"
	is_podman_sql_containers_no_docker_runtime="NO"

  # Check if system uses systemd
    if [[ "$(readlink /sbin/init)" == *systemd* ]]; then
        if systemctl list-units --type=service --state=active | grep -q docker; then
            is_container_runtime_service_installed="YES"

            if systemctl -q is-enabled docker &>/dev/null; then
                is_container_runtime_service_enabled="YES"
            fi

            if systemctl -q is-active docker &>/dev/null; then
                is_container_runtime_service_active="YES"
            fi
        fi
    fi

    # Check for running sql containers using docker 
    if command -v docker &>/dev/null; then
        docker_sql_count=$(docker ps --no-trunc | grep -c '/opt/mssql/bin/sqlservr')
        if (( docker_sql_count > 0 )); then
            is_docker_sql_containers="YES"
        fi
    fi

    # Check for running sql containers using podman
    if command -v podman &>/dev/null; then
        podman_sql_count=$(podman ps --no-trunc | grep -c '/opt/mssql/bin/sqlservr')
        if (( podman_sql_count > 0 )); then
            is_podman_sql_containers="YES"
        fi
    fi

    # Check for running podman SQL containers only if docker is not installed
    if [[ "$is_container_runtime_service_installed" == "NO" ]] && command -v podman &>/dev/null; then
        podman_sql_count_no_docker_runtime=$(podman ps --no-trunc | grep -c '/opt/mssql/bin/sqlservr')
        if (( podman_sql_count_no_docker_runtime > 0 )); then
            is_podman_sql_containers_no_docker_runtime="YES"
        fi
    fi
}

#when pssdiag is running inside, kubernetes, pod or container. get the status
pssdiag_inside_container_get_instance_status()
{
	is_instance_inside_container_active="NO"
	#Check if we are runing in kubernetes pod or inside container, sql parent process should have PID=1
	#first check, we should have no systemd
	if (! echo "$(readlink /sbin/init)" | grep systemd >/dev/null 2>&1); then
		#starting sql process is 1
		if [[ "$(ps -C sqlservr -o pid= | head -n 1 | tr -d ' ')" == "1" ]]; then
			is_instance_inside_container_active="YES"
		fi
	fi
}

#Check if we are running inside WSL
get_wsl_instance_status()
{
	is_host_instance_inside_wsl="NO"
	if [ -n "$WSL_DISTRO_NAME" ]; then
		is_host_instance_inside_wsl="YES"
	fi
}

get_servicemanager_and_sqlservicestatus()
{
	servicemanager="unknown"
	sqlservicestatus="unknown"

	get_container_instance_status
	get_host_instance_status
	pssdiag_inside_container_get_instance_status

	if [[ "${1}" == "host_instance" ]] && [[ "${is_host_instance_service_installed}" == "YES" ]]; then
		if [[ ${is_host_instance_process_running} == "YES" ]]; then
			sqlservicestatus="active"
			servicemanager="systemd"
		else
			sqlservicestatus="unknown"
			servicemanager="systemd"
		fi
	fi
	
	#Check if sql is started by supervisor
	if [[ "${1}" == "host_instance" ]] && [[ "${sqlservicestatus}" == "unknown" ]]; then
		supervisorctl status mssql-server >/dev/null 2>&1 && { sqlservicestatus="active"; servicemanager="supervisord"; } || { sqlservicestatus="unknown"; servicemanager="unknown"; }	
	fi

	#Check if sql is running in docker
	if [[ "${1}" == "container_instance" ]] && [[ ! -z "$(docker ps -q --filter name=${2})" ]]; then
		sqlservicestatus="active"
		servicemanager="docker"
	fi

	#Check if we are runing in kubernetes pod or inside container, sql parent process should have PID=1
	#first check, we should have no systemd
	if (! echo "$(readlink /sbin/init)" | grep systemd >/dev/null 2>&1); then
		#starting sql process is 1
		if [[ "$(ps -C sqlservr -o pid= | head -n 1 | tr -d ' ')" == "1" ]]; then
			sqlservicestatus="active"
			servicemanager="none"
		fi
	fi
		echo "$(date -u +"%T %D") SQL server is configured to run under ${servicemanager}" >> $pssdiag_log
		echo "$(date -u +"%T %D") SQL Server is status ${sqlservicestatus}" >> $pssdiag_log
}


sql_connect()
{
	echo -e "\x1B[2;34m============================================================================================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

	MAX_ATTEMPTS=3
	attempt_num=1
	sqlconnect=0
	find_sqlcmd
	get_servicemanager_and_sqlservicestatus ${1} ${2}
	
	if [[ "${sqlservicestatus}" == "unknown" ]]; then
		return $sqlconnect
	fi
	
	auth_mode=${4}
	CONN_AUTH_OPTIONS=''
	sqlconnect=0

	#force SQL Authentication when PSSDiag is running from inside Container
	if [[ $is_instance_inside_container_active == "YES" ]]; then auth_mode="SQL"; fi

	#if the user selected NONE Mode, ask then about what they need to use to this instance we are trying to connect to
	while [[ "${auth_mode}" != "SQL" ]] && [[ "${auth_mode}" != "AD" ]]; do
		read -r -p $'\e[1;34mSelect Authentication Mode: 1 SQL Authentication (Default), 2 AD Authentication: \e[0m' lmode < /dev/tty 2> /dev/tty
		lmode=${lmode:-1}
		if [ 1 = $lmode ]; then
			auth_mode="SQL"
		fi
		if [ 2 = $lmode ]; then
			auth_mode="AD"
		fi
	done 

	#Check if we have valid AD ticket before moving forward
	#making sure that klist is installed
	if ( command -v klist 2>&1 >/dev/null ); then 
		check_ad_cache=$(klist -l | tail -n +3 | awk '!/Expired/' | wc -l)
		if [[ "$check_ad_cache" == 0 ]] && [[ "$auth_mode" == "AD" ]]; then
			echo -e "\x1B[33mWarning: AD Authentication was selected as Authentication mode to connect to sql, however, no Kerberos credentials found in default cache, they may have expired"  
			echo -e "Warning: AD Authentication will fail"
			echo -e "to correct this, run 'sudo kinit user@DOMAIN.COM' in a separate terminal with AD user that is allowed to connect to sql server, then press enter in this terminal. \x1B[0m" 
			read -p "Press enter to continue"
		fi
	fi

	echo -e "$(date -u +"%T %D") Establishing SQL connection to ${1} ${2} and port ${3} using ${auth_mode} authentication mode" | tee -a $pssdiag_log
	
	#Test SQL Authentication, we allow them to try few times using SQL Auth
	if [[ $auth_mode = "SQL" ]]; then
		while [[ $attempt_num -le $MAX_ATTEMPTS ]]
		do
			#container do not connect using thier names if they do not have DNS record. so safer to connect using local host and container port
			## all of them its safer to use HOSTNAME, leaving this condition per instance type for now... force HOSTNAME
			if [ ${1} == "container_instance" ]; then
				SQL_SERVER_NAME="${HOSTNAME},${3}"
			fi
			if [ ${1} == "host_instance" ]; then
				SQL_SERVER_NAME="${HOSTNAME},${3}"
			fi
			if [ ${1} == "instance" ]; then
				SQL_SERVER_NAME="${HOSTNAME},${3}"
			fi
			#prompt for credentials for SQL authentication
			read -r -p $'\e[1;34mEnter SQL UserName: \e[0m' XsrX < /dev/tty 2> /dev/tty
			read -s -r -p $'\e[1;34mEnter User Password: \e[0m' XssX < /dev/tty 2> /dev/tty
			"$SQLCMD" -S$SQL_SERVER_NAME -U$XsrX -P$XssX -C -Q"select @@version" 2>&1 >/dev/null
			if [[ $? -eq 0 ]]; then
				sqlconnect=1
				echo ""
				echo -e "\x1B[32m$(date -u +"%T %D") Connection was successful....\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
				sql_ver=$("$SQLCMD" -S$SQL_SERVER_NAME -U$XsrX -P$XssX -C -Q"PRINT CONVERT(NVARCHAR(128), SERVERPROPERTY('ProductVersion'))")
				echo "$(date -u +"%T %D") SQL Server version  ${sql_ver}" >> $pssdiag_log
				CONN_AUTH_OPTIONS="-U$XsrX -P$XssX"
				break
			else
				echo -e "\x1B[31mLogin Attempt failed - Attempt ${attempt_num} of ${MAX_ATTEMPTS}, Please try again\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			fi
			attempt_num=$(( attempt_num + 1 ))
		done
	else
		#Test AD Authentication
		#container configured with AD Auth has DNS record so we can connect using thier name and container port
		if [ ${1} == "container_instance" ]; then
			SQL_SERVER_NAME="${2},${3}"
		fi
		if [ ${1} == "host_instance" ]; then
			SQL_SERVER_NAME="${HOSTNAME},${3}"
		fi
		"$SQLCMD" -S$SQL_SERVER_NAME -E -C -Q"select @@version" 2>&1 >/dev/null
    	if [[ $? -eq 0 ]]; then   	
			sqlconnect=1;
			CONN_AUTH_OPTIONS='-E'
			echo -e "\x1B[32m$(date -u +"%T %D") Connection was successful....\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			sql_ver=$("$SQLCMD" -S$SQL_SERVER_NAME -E -C -Q"PRINT CONVERT(NVARCHAR(128), SERVERPROPERTY('ProductVersion'))")
			echo "$(date -u +"%T %D") SQL Server version  ${sql_ver}" >> $pssdiag_log
		else
			#in case AD Authentication fails, try again using SQL Authentication for this particular instance 
			echo -e "\x1B[33mWarning: AD Authentication failed for ${1} ${2}, refer to the above lines for errors, switching to SQL Authentication for ${1} ${2}" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			sql_connect ${1} ${2} ${3} "SQL"
		fi
	fi
	#set the orginal connect method to allow the next instance to select its own method
	#echo -e "\x1B[34m============================================================================================================\x1B[0m" | tee -a $pssdiag_log
	return $sqlconnect	
}

get_sql_log_directory()
{
CONFIG_NAME="defaultlogdir"
DEFAULT_VALUE="/var/opt/mssql/log"

if [[ "$1" == "host_instance" ]]; then
        FILE_EXISTS=$(sh -c "test -f ${MSSQL_CONF} && echo 'exists' || echo 'not exists'")
        if [[ "${FILE_EXISTS}" == "exists" ]]; then
                logdir=`cat ${MSSQL_CONF} | grep -i ${CONFIG_NAME} | sed 's/ *= */=/g' | awk -F '=' '{ print $2}'`
                if [[ ${logdir} != "" ]] ; then
                        echo "${logdir}" | tee -a $pssdiag_log
                else
                        echo "${DEFAULT_VALUE}" | tee -a $pssdiag_log
                fi
        else
                echo "${DEFAULT_VALUE}" | tee -a $pssdiag_log
        fi
fi

if [[ "$1" == "container_instance" ]]; then
        FILE_EXISTS=$(docker exec ${3} sh -c "test -f ${MSSQL_CONF} && echo 'exists' || echo 'not exists'")
        if [[ "${FILE_EXISTS}" == "exists" ]]; then
                logdirline=$(docker exec ${3} sh -c "cat ${MSSQL_CONF} | grep -i ${CONFIG_NAME}")
                logdir=`echo ${tcpportline} | sed 's/ *= */=/g' | awk -F '=' '{ print $2}'`
                if [[ ${logdir} != "" ]] ; then
                        echo "${logdir}" | tee -a $pssdiag_log
                else
                        echo "${DEFAULT_VALUE}" | tee -a $pssdiag_log
                fi
        else
                echo "${DEFAULT_VALUE}" | tee -a $pssdiag_log
        fi
fi
}

#get_conf_option '/var/opt/mssql/mssql.conf' 'sqlagent' 'errorlogfile' '/var/opt/mssql/log/sqlagent'
#get_conf_option '/var/opt/mssql/mssql.conf' 'filelocation' 'errorlogfile' '/var/opt/mssql/log/errorlog'
#get_conf_option '/var/opt/mssql/logger.ini' 'Output:sql' 'filename' 'NA' 
get_conf_option()
{
unset result
unset config_section_found
while IFS= read -r line; do
	
	#skip comments
	if [[ "${line}" == \#* ]]; then
			continue
	fi

	config_section=$(echo "${line}" | tr -d '[]' | xargs)
	if [[ "${config_section}" == "${2}" ]]; then
		config_section_found=1
	fi
	option=$(echo ${line} | cut -d "=" -f1 | xargs )
	if [[ "${config_section_found}" == 1 ]] && [[ "${option}" == "${3}" ]]; then
		result=$(echo ${line//"$option"/} | tr -d '=' | xargs) 
		break 
	fi
done < $1

if [ "${result}" ]; then
	echo "$(date -u +"%T %D") Host instance ${HOSTNAME} conf file ${1} setting option [${2}] ${3} is set to : ${result}">>$pssdiag_log
elif [ "${4}" == "NA" ]; then
	echo "$(date -u +"%T %D") Host instance ${HOSTNAME} conf file ${1} setting option [${2}] ${3} is not set in the conf file, no default for this setting">>$pssdiag_log
else
	echo "$(date -u +"%T %D") Host instance ${HOSTNAME} conf file ${1} setting option [${2}] ${3} is not set in the conf file, using the default : ${4}">>$pssdiag_log
fi
echo ${result:-$4} 
}

#get_conf_option '/var/opt/mssql/mssql.conf' 'sqlagent' 'errorlogfile' '/var/opt/mssql/log/sqlagent' 'dockername'
#get_conf_option '/var/opt/mssql/mssql.conf' 'filelocation' 'errorlogfile' '/var/opt/mssql/log/errorlog' 'dockername'
#get_conf_option '/var/opt/mssql/logger.ini' 'Output:sql' 'filename' 'NA' 'dockername'
get_docker_conf_option()
{
unset result
unset config_section_found

tmpcontainertmpfile="./$(uuidgen).pssdiag.mssql.conf.tmp"
echo "$(docker exec --user root ${5} sh -c "cat ${1}")" > "$tmpcontainertmpfile"

while IFS= read -r line; do

	#skip comments
	if [[ "${line}" == \#* ]]; then
			continue
	fi
	
	config_section=$(echo "${line}" | tr -d '[]' | xargs)
	if [[ "${config_section}" == "${2}" ]]; then
		config_section_found=1
	fi
	option=$(echo ${line} | cut -d "=" -f1 | xargs)
	if [[ "${config_section_found}" == 1 ]] && [[ "${option}" == "${3}" ]]; then
		result=$(echo ${line//"$option"/} | tr -d '=' | xargs) 
		break 
	fi
done < "$tmpcontainertmpfile"

#Remove tmpcontainertmpfile
rm "$tmpcontainertmpfile"
if [ "${result}" ]; then
	echo "$(date -u +"%T %D") Container instance ${5} conf file ${1} setting option [${2}] ${3} is set to : ${result}">>$pssdiag_log
elif [ "${4}" == "NA" ]; then
	echo "$(date -u +"%T %D") Container instance ${5} conf file ${1} setting option [${2}] ${3} is not set in the conf file, no default for this setting">>$pssdiag_log
else
	echo "$(date -u +"%T %D") Container instance ${5} conf file ${1} setting option [${2}] ${3} is not set in the conf file, using the default : ${4}">>$pssdiag_log
fi
echo ${result:-$4} 
}


#tee -a $pssdiag_log
