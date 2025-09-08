#!/bin/bash

# include helper functions
source ./pssdiag_support_functions.sh

# function definitions


sql_stop_xevent()
{
if [[ $COLLECT_EXTENDED_EVENTS == [Yy][eE][sS]  ]]; then
	echo -e "$(date -u +"%T %D") Stopping Extended events Collection if started..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"pssdiag_xevent_stop.sql" -o"$outputdir/${1}_${2}_Stop_XECollection.log"
fi
}

sql_stop_trace()
{
if [[ $COLLECT_SQL_TRACE == [Yy][eE][sS]  ]]; then
        echo -e "$(date -u +"%T %D") Stopping SQL Trace Collection if started..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"pssdiag_trace_stop.sql" -o"$outputdir/${1}_${2}_Stop_TraceCollection.log"
fi
}

sql_collect_xevent()
{
if [[ $COLLECT_EXTENDED_EVENTS == [Yy][eE][sS]  ]]; then
        echo -e "$(date -u +"%T %D") Collecting Extended events..." | tee -a $pssdiag_log
	docker exec $1 sh -c "cd /var/opt/mssql/log  && tar cf /tmp/sql_xevent.tar *pssdiag_xevent*.xel "
        docker cp $1:/tmp/sql_xevent.tar ${outputdir}/${2}_${3}_sql_xevent.tar | 2>/dev/null
        docker exec $1 sh -c "rm -f /tmp/sql_xevent.tar"
fi
}

sql_collect_trace()
{
if [[ $COLLECT_SQL_TRACE == [Yy][eE][sS]  ]]; then
        echo -e "$(date -u +"%T %D") Collecting SQL Trace..." | tee -a $pssdiag_log
        docker exec $1 sh -c "cd /var/opt/mssql/log  && tar cf /tmp/sql_trace.tar *pssdiag_trace*.trc "
        docker cp $1:/tmp/sql_trace.tar ${outputdir}/${2}_${3}_sql_trace.tar | 2>/dev/null
        docker exec $1 sh -c "rm -f /tmp/sql_trace.tar"
fi
}

sql_collect_alwayson()
{
if [[ $COLLECT_SQL_HA_LOGS == [Yy][eE][sS]  ]]; then
        echo -e "$(date -u +"%T %D") Collecting SQL AlwaysOn configuration at Shutdown..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"SQL_AlwaysOnDiagScript.sql" -o"$outputdir/${1}_${2}_SQL_AlwaysOnDiag_Shutdown.out"
fi
}

sql_collect_querystore()
{
if [[ $COLLECT_QUERY_STORE == [Yy][eE][sS]  ]]; then
        echo -e "$(date -u +"%T %D") Collecting SQL Query Store information at Shutdown..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"SQL_QueryStore.sql" -o"$outputdir/${1}_${2}_SQL_QueryStore_Shutdown.out"
fi
}

sql_collect_perfstats_snapshot()
{
        echo -e "$(date -u +"%T %D") Collecting SQL Perf Stats Snapshot at Shutdown..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"SQL_Perf_Stats_Snapshot.sql" -o"$outputdir/${1}_${2}_SQL_Perf_Stats_Snapshot_Shutdown.out"
}

sql_collect_config()
{
	echo -e "$(date -u +"%T %D") Collecting SQL Configuration Snapshot at Shutdown..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"SQL_Configuration.sql" -o"$outputdir/${1}_${2}_SQL_Configuration_Shutdown.out"

        #echo -e "$(date -u +"%T %D") Collecting SQL traces information at Shutdown..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"SQL_active_profiler_xe_traces.sql" -o"$outputdir/${1}_${2}_SQL_ActiveProfilerXeventTraces.out"

        echo -e "$(date -u +"%T %D") Collecting SQL MiscDiag information at Shutdown..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"SQL_MiscDiaginfo.sql" -o"$outputdir/${1}_${2}_SQL_MiscDiagInfo.out"
}

sql_collect_linux_snapshot()
{
        echo -e "$(date -u +"%T %D") Collecting SQL Linux Snapshot at Shutdown..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"SQL_Linux_Snapshot.sql" -o"$outputdir/${1}_${2}_SQL_Linux_Snapshot_Shutdown.out"
}

sql_collect_databases_disk_map()
{
        echo -e "$(date -u +"%T %D") Collecting SQL database disk map information..." | tee -a $pssdiag_log
        ./collect_sql_database_disk_map.sh "$SQL_SERVER_NAME" "$CONN_AUTH_OPTIONS" >> $outputdir/${1}_${2}_SQL_Databases_Disk_Map_Shutdown.out
}

sql_collect_top_plans_CPU()
{
        echo -e "$(date -u +"%T %D") Collecting TOP Plan by CPU..." | tee -a $pssdiag_log
        for i in {1..10}
        do

        TOP10PLANS_QUERY=$"SET NOCOUNT ON;SELECT xmlplan FROM (
                SELECT ROW_NUMBER() OVER(ORDER BY (highest_cpu_queries.total_worker_time/highest_cpu_queries.execution_count) DESC) AS RowNumber,
                CAST(query_plan AS XML) xmlplan
                FROM (
                SELECT TOP 10 qs.plan_handle, qs.total_worker_time, qs.execution_count
                FROM sys.dm_exec_query_stats qs
                ORDER BY qs.total_worker_time DESC
                ) AS highest_cpu_queries
                CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS q
                CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS p
        ) AS x
        WHERE RowNumber = $i"

        "$SQLCMD" -S"$SQL_SERVER_NAME" $CONN_AUTH_OPTIONS -C -y 0 -Q "$TOP10PLANS_QUERY" > "$outputdir/${1}_${2}_Top_CPU_QueryPlansXml_Shutdown_${i}.sqlplan"

        done
}
 
# end of function definitions

##############################
# Start of main script
#############################

authentication_mode=${1^^}

pssdiag_inside_container_get_instance_status
find_sqlcmd


if grep -q "SUDO:YES" "$outputdir/pssdiag_intiated_as_user.log"; then
    STARTED_WITH_SUDO=true
fi

# Checks: if we run with SUDO and not inside a container, and provide the warning.
if [ -z "$SUDO_USER" ] && [ "$is_instance_inside_container_active" = "NO" ] && [ "$STARTED_WITH_SUDO" = true ]; then
	echo -e "\e[31mWarning: PSSDiag was initiated with elevated (sudo) permissions.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
        echo -e "\e[31mHowever, PSSDiag Stop was not initiated wtih elevated (sudo) permissions.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[31mElevated (sudo) permissions are required for PSSDiag to stop the collectors that are currently.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
        echo -e "\e[31mexisting... .\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
        echo -e "" | tee -a "$pssdiag_log"
	echo -e "\e[31mPlease run 'sudo ./stop_collector.sh' .\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	exit 1
fi

#Checks: make sure we have a valid authentication entered, we are running with system that has systemd
if [[ ! -z "$authentication_mode" ]] && [[ $is_instance_inside_container_active == "NO" ]] && [[ "$authentication_mode" != "SQL" ]] && [[ "$authentication_mode" != "AD" ]] && [[ "$authentication_mode" != "NONE" ]]; then
	echo -e "\x1B[33mwarning: Invalid authentication mode (first argument passed to PSSDiag)\x1B[0m"
	echo "" 
	echo "Valid options are:" 
	echo "  SQL"
	echo "  AD"
	echo "  NONE"
	echo "" 
	echo -e "\x1B[33mIgnoring the entry, PSSDiag will ask you which Authentication Mode to use...\x1B[0m" 
	exit 1	
fi

#Checks: make sure we have a valid authentication entered, we are running with system that has no systemd
if [[ ! -z "$authentication_mode" ]] && [[ $is_instance_inside_container_active == "YES" ]] && [[ "$authentication_mode" != "SQL" ]]; then
	echo -e "\x1B[33mwarning: Invalid authentication mode (first argument passed to PSSDiag)\x1B[0m"
	echo "" 
	echo "Valid options are:" 
	echo "  SQL"
	echo "" 
	echo -e "\x1B[33mIgnoring the entry, PSSDiag will use 'SQL' Authentication Mode...\x1B[0m" 
fi

outputdir="$PWD/output"
NOW=`date +"%m_%d_%Y_%H_%M"`
#credentials to collect shutdown script

# Read the PID we stored from the Start of the script
# kills all the PID's stored in the file
# after all work is done, remove the PID files

echo -e "\x1B[2;34m============================================= Stopping PSSDiag =============================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

if [[ -f $outputdir/pssdiag_stoppids_sql_collectors.log ]]; then
	echo "$(date -u +"%T %D") Starting to stop background processes that were collecting sql data..." | tee -a $pssdiag_log
	#cat $outputdir/pssdiag_stoppids_sql_collectors.log
	kill -9 `cat $outputdir/pssdiag_stoppids_sql_collectors.log` 2> /dev/null
        killedlist=$(awk '{ for (i=1; i<=NF; i++) RtoC[i]= (RtoC[i]? RtoC[i] FS $i: $i) } END{ for (i in RtoC) print RtoC[i] }' $outputdir/pssdiag_stoppids_sql_collectors.log)
        echo "$(date -u +"%T %D") Stopping the following PIDs $killedlist" | tee -a $pssdiag_log
	#rm -f $outputdir/pssdiag_stoppids_sql_collectors.log 2> /dev/null
fi
if [[ -f $outputdir/pssdiag_stoppids_os_collectors.log ]]; then
	echo "$(date -u +"%T %D") Starting to stop background processes that were collecting os data..." | tee -a $pssdiag_log
	#cat $outputdir/pssdiag_stoppids_os_collectors.log
	kill -9 `cat $outputdir/pssdiag_stoppids_os_collectors.log` 2> /dev/null
        killedlist=$(awk '{ for (i=1; i<=NF; i++) RtoC[i]= (RtoC[i]? RtoC[i] FS $i: $i) } END{ for (i in RtoC) print RtoC[i] }' $outputdir/pssdiag_stoppids_os_collectors.log)
        echo "$(date -u +"%T %D") Stopping the following PIDs $killedlist" | tee -a $pssdiag_log
	#rm -f $outputdir/pssdiag_stoppids_os_collectors.log 2> /dev/null
fi

CONFIG_FILE="./pssdiag_collector.conf"
if [[ -f $CONFIG_FILE ]]; then
. $CONFIG_FILE
fi

# Specify the defaults here if not specified in config file.
COLLECT_HOST_SQL_INSTANCE=${COLLECT_HOST_SQL_INSTANCE:-"NO"}
COLLECT_CONTAINER=${COLLECT_CONTAINER:-"NO"}
COLLECT_SQL_DUMPS=${COLLECT_SQL_DUMPS:-"NO"}
COLLECT_SQL_LOGS=${COLLECT_SQL_LOGS:-"NO"}
COLLECT_OS_LOGS=${COLLECT_OS_LOGS:-"NO"}
COLLECT_OS_CONFIG=${COLLECT_OS_CONFIG:-"NO"}
COLLECT_EXTENDED_EVENTS=${COLLECT_EXTENDED_EVENTS:-"NO"}
COLLECT_SQL_TRACE=${COLLECT_SQL_TRACE:-"NO"}
COLLECT_QUERY_STORE=${COLLECT_QUERY_STORE:-"NO"}
COLLECT_SQL_HA_LOGS=${COLLECT_SQL_HA_LOGS:-"NO"}
COLLECT_SQL_SEC_AD_LOGS=${COLLECT_SQL_SEC_AD_LOGS:-"NO"}
COLLECT_SQL_BEST_PRACTICES=${COLLECT_SQL_BEST_PRACTICES:-"NO"}
if [[ ${authentication_mode} == "SQL" ]] || [[ ${authentication_mode} == "AD" ]] || [[ ${authentication_mode} == "NONE" ]]; then
	SQL_CONNECT_AUTH_MODE=${authentication_mode:-"SQL"}
fi

#this section will connect to sql server instances and collect sql script outputs
#host instance
if [[ "$COLLECT_HOST_SQL_INSTANCE" == "YES" ]];then
        #we collect information from base host instance of SQL Server
        get_host_instance_status
	if [ "${is_host_instance_service_active}" == "YES" ]; then
                SQL_LISTEN_PORT=$(get_sql_listen_port "host_instance")
                SQL_SERVER_NAME="$HOSTNAME,$SQL_LISTEN_PORT"
                echo -e "\x1B[7m$(date -u +"%T %D") Collecting information from host instance $HOSTNAME and port $SQL_LISTEN_PORT...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                sql_connect "host_instance" "${HOSTNAME}" "${SQL_LISTEN_PORT}" "${authentication_mode}"
                sqlconnect=$?
                if [[ $sqlconnect -ne 1 ]]; then
        	        echo -e "\x1B[31mTesting the connection to host instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			echo -e "Please refer to the above lines for errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                else
                        sql_stop_xevent "${HOSTNAME}" "host_instance" 
                        sql_stop_trace "${HOSTNAME}" "host_instance" 

                        echo -e "\x1B[2;34m======================================== Collecting Static Logs ============================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

                        sql_collect_config "${HOSTNAME}" "host_instance"
                        sql_collect_top_plans_CPU "${HOSTNAME}" "host_instance"
                        sql_collect_linux_snapshot "${HOSTNAME}" "host_instance"
                  	sql_collect_perfstats_snapshot "${HOSTNAME}" "host_instance"
                        #chown only if pattern exists.
                        stat -t -- $output/*.xel >/dev/null 2>&1 && chown $USER: $outputdir/*.xel
                        # *.xel and *.trc files are placed in the output folder, nothing to collect here 
                        sql_collect_alwayson "${HOSTNAME}" "host_instance"
                        sql_collect_querystore "${HOSTNAME}" "host_instance"
                        sql_collect_databases_disk_map "${HOSTNAME}" "host_instance"
                fi
        fi

fi

#this section will connect to sql server instances and collect sql script outputs
#Collect informaiton if we are running inside container
if [[ "$COLLECT_HOST_SQL_INSTANCE" == "YES" ]];then
	pssdiag_inside_container_get_instance_status
	if [ "${is_instance_inside_container_active}" == "YES" ]; then
                SQL_SERVER_NAME="$HOSTNAME,1433"
                echo -e "\x1B[7m$(date -u +"%T %D") Collecting information from instance $HOSTNAME and port 1433...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                sql_connect "instance" "${HOSTNAME}" "1433" "${authentication_mode}"
                sqlconnect=$?
                if [[ $sqlconnect -ne 1 ]]; then
        	        echo -e "\x1B[31mTesting the connection to instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			echo -e "Please refer to the above lines for errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                else
                        sql_stop_xevent "${HOSTNAME}" "instance" 
                        sql_stop_trace "${HOSTNAME}" "instance" 

                        echo -e "\x1B[2;34m======================================== Collecting Static Logs ============================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

                        #chown only if pattern exists.
                        stat -t -- $output/*.xel >/dev/null 2>&1 && chown $USER: $outputdir/*.xel
                        # *.xel and *.trc files are placed in the output folder, nothing to collect here 
                        sql_collect_alwayson "${HOSTNAME}" "instance"
                        sql_collect_querystore "${HOSTNAME}" "instance"
                        sql_collect_config "${HOSTNAME}" "instance"
                        sql_collect_top_plans_CPU "${HOSTNAME}" "instance"
                        sql_collect_linux_snapshot "${HOSTNAME}" "instance"
                        sql_collect_perfstats_snapshot "${HOSTNAME}" "instance"
                fi
        fi  
fi


if [[ "$COLLECT_CONTAINER" != "NO" ]]; then
# we need to collect logs from containers
        get_container_instance_status
        if [ "${is_container_runtime_service_active}" == "YES" ]; then
                if [[ "$COLLECT_CONTAINER" != "ALL" ]]; then
                # we need to process just the specific container
                        dockerid=$(docker ps -q --filter name=$COLLECT_CONTAINER)
                        #moved to helper function
                        get_docker_mapped_port "${dockerid}"
                        #SQL_SERVER_NAME="$HOSTNAME,$dockerport"    
                        SQL_SERVER_NAME="$dockername,$dockerport"
                        echo -e "\x1B[7m$(date -u +"%T %D") Collecting information from container instance ${dockername} and port ${dockerport}\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                        sql_connect "container_instance" "${dockername}" "${dockerport}" "${authentication_mode}"
                        sqlconnect=$?
                        if [[ $sqlconnect -ne 1 ]]; then
                                echo -e "\x1B[31mTesting the connection to container instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                                echo -e "Please refer to the above lines for errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                        else
                                sql_stop_xevent "${dockername}" "container_instance"
                                sql_stop_trace "${dockername}" "container_instance"

                                echo -e "\x1B[2;34m======================================== Collecting Static Logs ============================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

                                sql_collect_xevent "${dockerid}" "${dockername}" "container_instance"
                                sql_collect_trace "${dockerid}" "${dockername}" "container_instance"
                                sql_collect_alwayson "${dockername}" "container_instance"
                                sql_collect_querystore "${dockername}" "container_instance"
                                sql_collect_config "${dockername}" "container_instance"
                                sql_collect_top_plans_CPU "${dockername}" "container_instance"
                                sql_collect_linux_snapshot "${dockername}" "container_instance"
                                sql_collect_perfstats_snapshot "${dockername}" "container_instance"
                        fi
                # we finished processing the requested container
                else
                # we need to iterate through all containers
                        #dockerid_col=$(docker ps | grep 'microsoft/mssql-server-linux' | awk '{ print $1 }')
                        dockerid_col=$(docker ps --no-trunc | grep -e '/opt/mssql/bin/sqlservr' | awk '{ print $1 }')

                        for dockerid in $dockerid_col;
                        do
                                #moved to helper function
                                get_docker_mapped_port "${dockerid}"
                                SQL_SERVER_NAME="$dockername,$dockerport"
                                echo -e "\x1B[7m$(date -u +"%T %D") Collecting information from container instance ${dockername} and port ${dockerport}\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                                sql_connect "container_instance" "${dockername}" "${dockerport}" "${authentication_mode}"
                                sqlconnect=$?
                                if [[ $sqlconnect -ne 1 ]]; then
                                        echo -e "\x1B[31mTesting the connection to container instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                                        echo -e "Please refer to the above lines for errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
                                else
                                        sql_stop_xevent "${dockername}" "container_instance"
                                        sql_stop_trace "${dockername}" "container_instance"

                                        echo -e "\x1B[2;34m======================================== Collecting Static Logs ============================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

                                        sql_collect_xevent "${dockerid}" "${dockername}" "container_instance"
                                        sql_collect_trace "${dockerid}" "${dockername}" "container_instance"
                                        sql_collect_alwayson "${dockername}" "container_instance"
                                        sql_collect_querystore "${dockername}" "container_instance"
                                        sql_collect_config "${dockername}" "container_instance"
                                        sql_collect_top_plans_CPU "${dockername}" "container_instance"
                                        sql_collect_linux_snapshot "${dockername}" "container_instance"
                                        sql_collect_perfstats_snapshot "${dockername}" "container_instance"
                                fi
                        done;
                # we finished processing all the container
                fi
        fi
fi


#collect basic machine configuration
if [[ $COLLECT_OS_CONFIG == "YES" ]]; then
        ./collect_machineconfig.sh
        ./collect_container_info.sh
fi

#gather os logs from host
if [[ "$COLLECT_OS_LOGS" == "YES" ]]; then
	./collect_os_logs.sh
fi

#Gather pcs logs
if [[ "$COLLECT_OS_HA_LOGS" == "YES" ]]; then
	./collect_os_ha_logs.sh
fi

#Gather krb5 and sssd logs from host 
if [[ "$COLLECT_OS_SEC_AD_LOGS" == "YES" ]]; then
	./collect_os_ad_logs.sh
fi

#gather sql logs from containers or host
if [[ "$COLLECT_SQL_LOGS" == "YES" ]]; then
	./collect_sql_logs.sh
fi
#gather sql dumps from containers or host
if [[ "$COLLECT_SQL_DUMPS" == "YES" ]]; then
	./collect_sql_dumps.sh
fi
#gather SQL Security and AD logs from containers or host
if [[ "$COLLECT_SQL_SEC_AD_LOGS" == "YES" ]]; then
	./collect_sql_ad_logs.sh
fi

#gather SQL Best Practices Analyzer
if [[ "$COLLECT_SQL_BEST_PRACTICES" == "YES" ]]; then
	echo -e "$(date -u +"%T %D") Collecting SQL Linux Best Practices Analyzer..." | tee -a $pssdiag_log
        ./sql_linux_best_practices_analyzer.sh --explain-all >> $outputdir/${HOSTNAME}_host_instance_SQL_Linux_Best_Practice_Analyzer.out

        echo -e "$(date -u +"%T %D") Collecting SQL Linux Known issues Analyzer..." | tee -a $pssdiag_log
        ./sql_linux_known_issues_analyzer.sh "$SQL_SERVER_NAME" "$CONN_AUTH_OPTIONS" >> $outputdir/${HOSTNAME}_host_instance_SQL_Linux_Known_Issues_Analyzer.out
fi

if [ "$EUID" -ne 0 ]; then
# for minimal collecton, where user didnt use sudo, we cant compress the output file as it may contains files with mssql user, like XEL and TRC files.
  echo -e "\x1B[2;34m============================================================================================================\x1B[0m" 
  echo "Data collected in the output folder, Compress the output folder with sudo to include all the files." 
  echo -e "\x1B[2;34m=================================================== Done ===================================================\x1B[0m" 
  exit 0
fi

echo -e "\x1B[2;34m=======================================  Creating Compressed Archive =======================================\x1B[0m" 
#zip up output directory
short_hostname="${HOSTNAME%%.*}"
tar -cjf "output_${short_hostname}_${NOW}.tar.bz2" output
echo -e "*** Data collected is in the file output_${short_hostname}_${NOW}.tar.bz2 ***"
echo -e "\x1B[2;34m=================================================== Done ===================================================\x1B[0m"


