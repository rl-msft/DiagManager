#!/bin/bash
outputdir="$PWD/output"


###NOT USED FILE............... the logs are being collected by collect_sql_logs.sh
# get container directive from config file
CONFIG_FILE="./pssdiag_collector.conf"
if [[ -f $CONFIG_FILE ]]; then
. $CONFIG_FILE
fi

# Specify the defaults here if not specified in config file.
COLLECT_CONTAINER=${COLLECT_CONTAINER:-"NO"}

#Check the ability to run container commands, if we cant then set COLLECT_CONTAINER to NO regardless of scenario setting.
checkContainerCommand="NO"
# Check if podman is installed and can run podman ps
if command -v podman >/dev/null 2>&1 && podman ps >/dev/null 2>&1; then
    checkContainerCommand="yes"
# Check if docker is installed and can run docker ps
elif command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    checkContainerCommand="yes"
fi
if [[ "$COLLECT_CONTAINER" != "NO" && "$checkContainerCommand" == "NO" ]] ; then
	COLLECT_CONTAINER="NO"
fi



if [[ "$COLLECT_CONTAINER" != "NO" ]]; then
# we need to collect logs from containers
# create a subfolder to collect all logs from containers
mkdir -p $outputdir/log
if [ "$EUID" -eq 0 ]; then
  group=$(id -gn "$SUDO_USER")
  chown "$SUDO_USER:$group" "$outputdir" -R
else
	chown $(id -u):$(id -g) "$outputdir" -R
fi

	if [[ "$COLLECT_CONTAINER" != "ALL" ]]; then
	# we need to process just the specific container
		name=$COLLECT_CONTAINER
		echo "Collecting logs from container : $name"
		dockerid=$(docker ps -q --filter name=$name)
		dockername=$(docker inspect -f "{{.Name}}" $dockerid)
		docker cp $dockerid:/var/opt/mssql/log/. $outputdir/log/$dockername | 2>/dev/null

	else
	# we need to iterate through all containers
		#dockerid_col=$(docker ps | grep 'microsoft/mssql-server-linux' | awk '{ print $1 }')
		dockerid_col=$(docker ps --no-trunc | grep -e '/opt/mssql/bin/sqlservr' | awk '{ print $1 }')
		for dockerid in $dockerid_col;
		do
			dockername=$(docker inspect -f "{{.Name}}" $dockerid)
			echo "Collecting logs from container : $dockername"
			docker cp $dockerid:/var/opt/mssql/log/. $outputdir/log/$dockername | 2>/dev/null
		done;
	fi

fi

