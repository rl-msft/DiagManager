#!/bin/bash

# include helper functions
source ./pssdiag_support_functions.sh

# defining all functions upfront

sql_collect_perfstats()
{
        if [[ $COLLECT_PERFSTATS == [Yy][eE][sS] ]] ; then
                #Start regular PerfStats script as a background job
                echo -e "$(date -u +"%T %D") Starting SQL Perf Stats script as a background job..." | tee -a $pssdiag_log
                `"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"$PerfStatsfilename" -o"$outputdir/${1}_${2}_SQL_Perf_Stats.out"` &
                mypid=$!
                #printf "%s\n" "$mypid" >> $outputdir/pssdiag_stoppids_sql_collectors.log
				sleep 5s
                pgrep -P $mypid  >> $outputdir/pssdiag_stoppids_sql_collectors.log

				#Start Linux Stats script as a background job
				echo -e "$(date -u +"%T %D") Starting SQL Linux Stats script as a background job..." | tee -a $pssdiag_log
                `"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_linux_stats.sql" -o"$outputdir/${1}_${2}_SQL_Linux_Perf_Stats.out"` &
                mypid=$!
                #printf "%s\n" "$mypid" >> $outputdir/pssdiag_stoppids_sql_collectors.log
				sleep 5s
                pgrep -P $mypid  >> $outputdir/pssdiag_stoppids_sql_collectors.log

				#Start HighCPU Stats script as a background job
				echo -e "$(date -u +"%T %D") Starting SQL High CPU Stats script as a background job..." | tee -a $pssdiag_log
                `"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_highcpu_perf_stats.sql" -o"$outputdir/${1}_${2}_SQL_HighCPU_Perf_Stats.out"` &
                mypid=$!
                #printf "%s\n" "$mypid" >> $outputdir/pssdiag_stoppids_sql_collectors.log
				sleep 5s
                pgrep -P $mypid  >> $outputdir/pssdiag_stoppids_sql_collectors.log

				#Start High_IO Stats script as a background job
				echo -e "$(date -u +"%T %D") Starting SQL High IO Stats script as a background job..." | tee -a $pssdiag_log
                `"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_highio_perf_stats.sql" -o"$outputdir/${1}_${2}_SQL_HighIO_Perf_Stats.out"` &
                mypid=$!
                #printf "%s\n" "$mypid" >> $outputdir/pssdiag_stoppids_sql_collectors.log
				sleep 5s
                pgrep -P $mypid  >> $outputdir/pssdiag_stoppids_sql_collectors.log

        fi
}

sql_collect_counters()
{
        if [[ $COLLECT_SQL_COUNTERS == [Yy][eE][sS] ]] ; then
                #Start sql performance counter script as a background job
                #Replace Interval with SED
                sed -i'' -e"2s/.*/SET @SQL_COUNTER_INTERVAL = $SQL_COUNTERS_INTERVAL/g" sql_performance_counters.sql
                echo -e "$(date -u +"%T %D") Starting SQL Performance counter script as a background job... " | tee -a $pssdiag_log
                `"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_performance_counters.sql" -o"$outputdir/${1}_${2}_SQL_Performance_Counters.out"` &
                mypid=$!
                #printf "%s\n" "$mypid" >> $outputdir/pssdiag_stoppids_sql_collectors.log
		sleep 5s
                pgrep -P $mypid  >> $outputdir/pssdiag_stoppids_sql_collectors.log
        fi
}


sql_collect_memstats()
{
        if [[ $COLLECT_SQL_MEM_STATS == [Yy][eE][sS] ]] ; then
                #Start SQL Memory Status script as a background job
                echo -e "$(date -u +"%T %D") Starting SQL Memory Status script as a background job... " | tee -a $pssdiag_log
                `"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_mem_stats.sql" -o"$outputdir/${1}_${2}_SQL_Mem_Stats.out"` &
                mypid=$!
                #printf "%s\n" "$mypid" >> $outputdir/pssdiag_stoppids_sql_collectors.log
		sleep 5s
                pgrep -P $mypid  >> $outputdir/pssdiag_stoppids_sql_collectors.log
        fi
}

sql_collect_sql_custom()
{
        if [[ $CUSTOM_COLLECTOR == [Yy][eE][sS] ]] ; then
                #Start Custom Collector  scripts as a background job
                echo -e "$(date -u +"%T %D") Starting SQL Custom Collector Scripts as a background job... " | tee -a $pssdiag_log
                for filename in my_sql_custom_collector*.sql; do
                   `"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"${filename}" -o"$outputdir/${1}_${2}_${filename}_Output.out"` &
                    mypid=$!
		    		sleep 5s
                    pgrep -P $mypid  >> $outputdir/pssdiag_stoppids_sql_collectors.log
                done
        fi
}

sql_collect_xevent()
{
        #start any XE collection if defined? XE file should be named pssdiag_xevent_.sql.
        if [[ $COLLECT_EXTENDED_EVENTS == [Yy][eE][sS]  ]]; then
                echo -e "$(date -u +"%T %D") Starting SQL Extended Events collection...  " | tee -a $pssdiag_log
                "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"${EXTENDED_EVENT_TEMPLATE}.sql" -o"$outputdir/${1}_${2}_pssdiag_xevent.log"
                cp -f ./pssdiag_xevent_start.template ./pssdiag_xevent_start.sql
		if [[ "$2" == "host_instance" ]] || [[ "$2" == "instance" ]]; then
	                sed -i "s|##XeFileName##|${outputdir}/${1}_${2}_pssdiag_xevent.xel|" pssdiag_xevent_start.sql
		else
                    sed -i "s|##XeFileName##|/tmp/${1}_${2}_pssdiag_xevent.xel|" pssdiag_xevent_start.sql
		fi
                "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"pssdiag_xevent_start.sql" -o"$outputdir/${1}_${2}_pssdiag_xevent_start.log"
        fi
}

sql_collect_trace()
{
        #start any SQL trace collection if defined? 
        if [[ $COLLECT_SQL_TRACE == [Yy][eE][sS]  ]]; then
		echo -e "$(date -u +"%T %D") Creating helper stored procedures in tempdb from MSDiagprocs.sql" >> $pssdiag_log
		"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"MSDiagProcs.sql" -o"$outputdir/${1}_${2}_MSDiagprocs.out"
                echo -e "$(date -u +"%T %D") Starting SQL trace collection...  " | tee -a $pssdiag_log
                cp -f ./${SQL_TRACE_TEMPLATE}.template ./pssdiag_trace_start.sql
		if [[ "$2" == "host_instance" ]] || [[ "$2" == "instance" ]]; then
			sed -i "s|##TraceFileName##|${outputdir}/${1}_${2}_pssdiag_trace|" pssdiag_trace_start.sql
		else
			sed -i "s|##TraceFileName##|/tmp/${1}_${2}_pssdiag_trace|" pssdiag_trace_start.sql
		fi
		"$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"pssdiag_trace_start.sql" -o"$outputdir/${1}_${2}_pssdiag_trace_start.out"
        fi
}

sql_collect_config()
{
        #include whatever base collector scripts exist here
        echo -e "$(date -u +"%T %D") Collecting SQL Configuration information at startup..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_configuration.sql" -o"$outputdir/${1}_${2}_SQL_Configuration_Startup.out"
}

sql_collect_linux_snapshot()
{
        echo -e "$(date -u +"%T %D") Collecting SQL Linux Snapshot at Startup..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_linux_snapshot.sql" -o"$outputdir/${1}_${2}_SQL_Linux_Snapshot_Startup.out"
}

sql_collect_perfstats_snapshot()
{
        echo -e "$(date -u +"%T %D") Collecting SQL Perf Stats Snapshot at Startup..." | tee -a $pssdiag_log
        "$SQLCMD" -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -i"sql_perf_stats_snapshot.sql" -o"$outputdir/${1}_${2}_SQL_Perf_Stats_Snapshot_Startup.out"
}

# end of all function definitions

#########################
# Start of main script  #
# - start_collector.sh  #
#########################

echo "" 

get_host_instance_status
get_container_instance_status
pssdiag_inside_container_get_instance_status
get_wsl_instance_status
find_sqlcmd

#Checks: if user passed any parameter to the script 
scenario=${1,,}
authentication_mode=${2^^}
PerfStatsfilename="${3,,}"; : "${PerfStatsfilename:=sql_perf_stats.sql}"

# setup the output directory to collect data and logs
working_dir="$PWD"
outputdir="$working_dir/output"

#Checks: if output directory exists, if yes prompt to overwrite
if [[ -d "$outputdir" ]]; then
  echo -e "\e[31mOutput directory {$outputdir} exists..\e[0m"
  read -p "Do you want to overwrite? (y/n): " choice < /dev/tty 2> /dev/tty
  case "$choice" in
    y|Y ) ;;
    n|N ) exit 1;;
    * ) exit 1;;
  esac
fi

# Checks: Make sure the output directory is not owned by root
if [ "$(id -u)" -ne 0 ]; then
    if [ -e "$outputdir" ]; then
        owner=$(stat -c '%U' "$outputdir")  # Use -f '%Su' on macOS
        if [ "$owner" = "root" ]; then
            echo "The folder \"$outputdir\" is owned by root."
			echo "This folder cannot be deleted because PSSDiag was started without elevated (sudo) permissions. Please remove it manually using sudo, then re-run the script."
            exit 1
        fi
    fi
fi

# --remove the output directory
if [ -d "$outputdir" ]; then
  rm -rf "$outputdir"
fi
mkdir -p $working_dir/output
chmod a+w $working_dir/output
if [ "$EUID" -eq 0 ]; then
  group=$(id -gn "$SUDO_USER")
  chown "$SUDO_USER:$group" "$outputdir" -R
else
	chown $(id -u):$(id -g) "$outputdir" -R
fi

#setting up the log file, and set the directive to send errors presented to user to the log file.
pssdiag_log="$outputdir/pssdiag.log"
exec 2> >(tee -a $pssdiag_log >&2) 


# Checks: if we run with SUDO and not inside a container, and provide the warning.
if [ -z "$SUDO_USER" ] && [ "$is_instance_inside_container_active" = "NO" ]; then
	echo -e ""
	echo -e "\e[31mWarning: PSSDiag was started without elevated (sudo) permissions.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[31mElevated (sudo) permissions are required for PSSDiag to collect complete diagnostic dataset.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "" | tee -a "$pssdiag_log"
	echo -e "\e[31mWithout elevated permissions:\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[31m** PSSDiag will not able to read mssql.conf to get SQL log file location and port number.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[31m** PSSDiag will not able to copy errorlog, extended events and dump files..\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[31m** Some host OS log collector may fail.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[31m** All SQL container collectors will fail.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[31m** Only T-SQL based collectors will be able run for SQL host instance with default port 1433.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "" | tee -a "$pssdiag_log"
	echo -e "\e[33mIf you still prefer to run PSSDiag without elevated (sudo) permissions, please ensure the user executing PSSDiag has the following:.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[33m** Ownership of PSSDiag folder.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[33m** Read access to mssql.conf, as well as the SQL log and dump directories.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "\e[33m** Membership in the Docker group (or an equivalent group), if data is being collected from containers.\e[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	echo -e "" | tee -a "$pssdiag_log"
	read -p "Do you want to continue? (y/n): " choice < /dev/tty 2> /dev/tty
	case "$choice" in
		y|Y ) ;;
		n|N ) exit 1;;
		* ) exit 1;;
	esac
fi

#Checks: make sure we have a valid scenario entered, we are running with system that has systemd
if [[ ! -z "$scenario" ]] && [[ "$is_instance_inside_container_active" == "NO" ]] && [[ "$scenario" != "static_collect.scn" ]] && [[ "$scenario" != "sql_perf_light.scn" ]] && [[ "$scenario" != "sql_perf_general.scn" ]] && [[ "$scenario" != "sql_perf_detailed.scn" ]]; then
	echo -e "\x1B[31mError is specifying a scenario (first argument passed to PSSDiag)\x1B[0m"
	echo "" 
	echo "Valid options are:" 
	echo "  static_collect.scn"
	echo "  sql_perf_minimal.scn"
	echo "  sql_perf_light.scn"
	echo "  sql_perf_general.scn"
	echo "  sql_perf_detailed.scn"
	echo "" 
	echo "if you are unsure what option to pass, just run 'sudo /bin/bash ./start_collector.sh' and PSSDiag will guide you" 
	echo "" 
	echo "exiting..." 
	echo "" 
	exit 1	
fi

#Checks: make sure we have a valid authentication entered, we are running with system that has systemd
if [[ ! -z "$authentication_mode" ]] && [[ "$is_instance_inside_container_active" == "NO" ]] && [[ "$authentication_mode" != "SQL" ]] && [[ "$authentication_mode" != "AD" ]] && [[ "$authentication_mode" != "NONE" ]]; then
	echo -e "\x1B[31mError in specifying authentication mode (second argument passed to PSSDiag)\x1B[0m"
	echo "" 
	echo "Valid options are:" 
	echo "  SQL"
	echo "  AD"
	echo "  NONE"
	echo "" 
	echo "if you are unsure what option to pass, just run 'sudo /bin/bash ./start_collector.sh' and PSSDiag will guide you" 
	echo "" 
	echo "exiting..." 
	echo "" 
	exit 1	
fi

#Checks: make sure we have a valid scenario entered, we are running with system that has no systemd
if [[ ! -z "$scenario" ]] && [[ "$is_instance_inside_container_active" == "YES" ]] && [[ "$scenario" != "static_collect_kube.scn" ]] && [[ "$scenario" != "sql_perf_light_kube.scn" ]] && [[ "$scenario" != "sql_perf_general_kube.scn" ]] && [[ "$scenario" != "sql_perf_detailed_kube.scn" ]]; then
	echo -e "\x1B[31mError is specifying a scenario (first argument passed to PSSDiag)\x1B[0m"
	echo "" 
	echo "Valid options are:" 
	echo "  static_collect_kube.scn"
	echo "  sql_perf_minimal_kube.scn"
	echo "  sql_perf_light_kube.scn"
	echo "  sql_perf_general_kube.scn"
	echo "  sql_perf_detailed_kube.scn"	
	echo "" 
	echo "if you are unsure what option to pass, just run '/bin/bash ./start_collector.sh' and PSSDiag will guide you" 
	echo "exiting..." 
	echo "" 
	exit 1	
fi

#Checks: make sure we have a valid authentication entered, we are running with system that has no systemd
if [[ ! -z "$authentication_mode" ]] && [[ "$is_instance_inside_container_active" == "YES" ]] && [[ "$authentication_mode" != "SQL" ]]; then
	echo -e "\x1B[31mError in specifying authentication mode (second argument passed to PSSDiag)\x1B[0m"
	echo "" 
	echo "Valid options are:" 
	echo "  SQL"
	echo "" 
	echo "if you are unsure what option to pass, just run '/bin/bash ./start_collector.sh' and PSSDiag will guide you" 
	echo "exiting..." 
	echo "" 
	exit 1	
fi

#if the scenario is valid, then use it for pssdiag_collector.conf
if [[ -n "$scenario" ]]; then
	# Parameter processing from config scenario file scenario_<name>.conf in same directory
	# Read config files, if defaults are overwridden there, they will be adhered to
	# Config file values are  Key value pairs Example"  COLLECT_CONFIG=YES
	CONFIG_FILE="./${scenario}"
	echo "Reading configuration values from config scenario file $CONFIG_FILE" 
	if [[ -f $CONFIG_FILE ]]; then
		. $CONFIG_FILE
		cp -f ./${scenario} ./pssdiag_collector.conf
	else
 		echo "" 
		echo "Error reading configuration file specified as input, make sure that $scenario exists" 
		exit 1
	fi
fi

# ─────────────────────────────────────────────────────────────────────────────────────
# - Get user input for scenario   
# - if scenario has not been passed and we are running with systemd system                  
# - PSSDiag running on host OS                
# ─────────────────────────────────────────────────────────────────────────────────────

if [[ -z "$scenario" ]] && [[ "$is_instance_inside_container_active" == "NO" ]]; then
	echo -e "\x1B[2;34m============================================ Select Run Scenario ===========================================\x1B[0m" 
	echo "Run Scenario's:"
	echo ""
	echo "Specify the level of data collection from Host OS and SQL instance, whether the SQL instance is running on the host or within a container"
	echo ""
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo -e "|No |Run Scenario           |Description                                                                   |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "| 1 |static_collect.scn     |Passive data collection approach,focusing solely on copying standard logs from|"
	echo -e "|   |                       |host OS and SQL without collecting any performance data. \x1B[34m(Default)\x1B[0m            |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "| 2 |sql_perf_minimal.scn   |Collects minimal performance data from SQL without extended events            |"
	echo    "|   |                       |suitable for extended use.                                                    |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "| 3 |sql_perf_light.scn     |Collects lightweight performance data from SQL and host OS,                   |"
	echo    "|   |                       |suitable for extended use.                                                    |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "| 4 |sql_perf_general.scn   |Collects general performance data from SQL and host OS, suitable for          |"
	echo    "|   |                       |15 to 20-minute collection periods, covering most scenarios.                  |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "| 5 |sql_perf_detailed.scn  |Collects detailed performance data at statement level, Avoid using this       |"
	echo    "|   |                       |scenario as it may affect server performance                                  |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo ""
	scn_user_selected=""
	while [[ ${scn_user_selected} != [1-5] ]]
	do
		read -r -p $'\e[1;34mSelect a Scenario [1-5] (Enter to select the default "static_collect.scn"): \e[0m' scn_user_selected < /dev/tty 2> /dev/tty

		#Set the defaul scnario to 1 if user just hits enter
		scn_user_selected=${scn_user_selected:-1}

		#check if we have a valid selection
		if [[ ! "$scn_user_selected" =~ ^[1-5]$ ]]; then
    		echo "Invalid selection. Exiting..."
    		exit 1
		fi

		#Set the scenario variable based on user selection
		if [[ ${scn_user_selected} == 1 ]]; then
			scenario="static_collect.scn"
		fi
		if [[ ${scn_user_selected} == 2 ]]; then
			scenario="sql_perf_minimal.scn"
		fi
		if [[ ${scn_user_selected} == 3 ]]; then
			scenario="sql_perf_light.scn"
		fi
		if [[ ${scn_user_selected} == 4 ]]; then
			scenario="sql_perf_general.scn"
		fi
		if [[ ${scn_user_selected} == 5 ]]; then
			scenario="sql_perf_detailed.scn"
		fi
		echo ""

		#Check if scenario is set to one of the performance-impacting options
		if [[ "$scenario" == "sql_perf_detailed.scn" ]]; then
	    echo -e "\033[0;31mAre you sure you want to use scenario: $scenario?\033[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
    	echo -e "\033[0;31mThis will collect performance data at the statement level, which may affect server performance.\033[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

			read -p "Do you want to continue? (yes/no): " choice

			case "$choice" in
				yes|y|Y)
					echo "Proceeding with scenario: $scenario"
					echo ""
					;;
				no|n|N)
					echo "Exiting as requested."
					exit 1
					;;
				*)
					echo "Invalid input. Exiting."
					exit 1
					;;
			esac
		fi

		CONFIG_FILE="./${scenario}"

		#echo "Reading configuration values from config scenario file $CONFIG_FILE" 
		echo "Reading configuration values from config scenario file $CONFIG_FILE"  | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
		if [[ -f $CONFIG_FILE ]]; then
			. $CONFIG_FILE
			cp -f ./${scenario} ./pssdiag_collector.conf
		else
 			echo "" 
	 		echo "Error reading configuration file specified as input, make sure that $scenario exists"  | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			exit 1
		fi
	done 
fi

# ─────────────────────────────────────────────────────────────────────────────────────
# - Get user input for authentication_mode   
# - if authentication_mode has not been passed                
# - PSSDiag running on host OS                
# ─────────────────────────────────────────────────────────────────────────────────────

#if authentication_mode has not been passed and we are running with systemd system, ask the user for input
if [[ -z "$authentication_mode" ]] && [[ "$is_instance_inside_container_active" == "NO" ]]; then
	echo -e "\x1B[2;34m======================================== Select Authentication Mode ========================================\x1B[0m" 
	echo "Authentication Modes:"
	echo ""
	echo "Defines the Authentication Mode to use when connecting to SQL whether they are host or container instance"
	echo ""
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "|No |Authentication Mode    |Description                                                                   |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo -e "| 1 |SQL                    |Use SQL Authentication. \x1B[34m(Default)\x1B[0m                                             |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "| 2 |AD                     |Use AD Authentication                                                         |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo    "| 3 |NONE                   |Allows to select the method per instance when multiple instances              |"
	echo    "|   |                       |host instance and container instance/s running on the same host,              |"
	echo    "|   |                       |not applicable for sql running on Kubernetes                                  |"
	echo    "+---+-----------------------+------------------------------------------------------------------------------+"
	echo ""
	auth_mode_selected=""
	while [[ ${auth_mode_selected} != [1-3] ]]
	do
		read -r -p $'\e[1;34mSelect an Authentication Method [1-3] (Enter to select the default "SQL"): \e[0m' auth_mode_selected < /dev/tty 2> /dev/tty

		#set the default authentication mode to 1 if user just hits enter
		auth_mode_selected=${auth_mode_selected:-1}

		#check if we have a valid selection
		if [[ ! "$auth_mode_selected" =~ ^[1-3]$ ]]; then
    		echo "Invalid selection. Exiting..."
    		exit 1
		fi

		#set the authentication_mode variable based on user selection
		if [ $auth_mode_selected == 1 ]; then
			authentication_mode="SQL"
		fi
		if [ $auth_mode_selected == 2 ]; then
			authentication_mode="AD"
		fi
		if [ $auth_mode_selected == 3 ]; then
			authentication_mode="NONE"
		fi
	done 
fi

# ─────────────────────────────────────────────────────────────────────────────────────
# - Get user input for scenario                  
# - if scenario has not been passed and we are with no systemd     
# - PSSDiag running inside container               
# ─────────────────────────────────────────────────────────────────────────────────────
if [[ -z "$scenario" ]] && [[ "$is_instance_inside_container_active" == "YES" ]]; then
	echo -e "\x1B[2;34m============================================ Select Run Scenario ===========================================\x1B[0m" 
	echo "Run Scenario's:"
	echo ""
	echo "Specify the level of data collection from SQL"
	echo ""
	echo    "+---+--------------------------+---------------------------------------------------------------------------+"
	echo    "|No |Run Scenario              |Description                                                                |"
	echo    "+---+--------------------------+---------------------------------------------------------------------------+"
	echo    "| 1 |static_collect_kube.scn   |Passive data collection approach,focusing solely on copying standard logs  |"
	echo    "|   |                          |from the SQL without collecting any performance data.                      |"
	echo -e "|   |                          |\x1B[34m(Default) \x1B[0m                                                                 |"
	echo    "+---+--------------------------+---------------------------------------------------------------------------+"
	echo    "| 2 |sql_perf_minimal_kube.scn |Collects minimal performance data from SQL without extended events         |"
	echo    "|   |                          |suitable for extended use.                                                 |"
	echo    "+---+--------------------------+---------------------------------------------------------------------------+"
	echo    "| 3 |sql_perf_light_kube.scn   |Collects lightweight performance data from SQL, suitable for extended use. |"
	echo    "+---+--------------------------+---------------------------------------------------------------------------+"
	echo    "| 4 |sql_perf_general_kube.scn |Collects general performance data from SQL, suitable for 15 to 20-minute   |"
	echo    "|   |                          |collection periods, covering most scenarios.                               |"
	echo    "+---+--------------------------+---------------------------------------------------------------------------+"
	echo    "| 5 |sql_perf_detailed_kube.scn|Collects detailed performance data at statement level, Avoid using this    |"
	echo    "|   |                          |scenario as it may affect server performance                               |"
	echo    "+---+--------------------------+---------------------------------------------------------------------------+"
	echo ""
	scn_user_selected=""
	while [[ ${scn_user_selected} != [1-5] ]]
	do
		read -r -p $'\e[1;34mSelect a Scenario [1-5] (Enter to select the default "static_collect_kube.scn"): \e[0m' scn_user_selected < /dev/tty 2> /dev/tty

		scn_user_selected=${scn_user_selected:-1}

		#check if we have a valid selection
		if [[ ! "$scn_user_selected" =~ ^[1-5]$ ]]; then
    		echo "Invalid selection. Exiting..."
    		exit 1
		fi

		if [[ ${scn_user_selected} == 1 ]]; then
			scenario="static_collect_kube.scn"
		fi
		if [[ ${scn_user_selected} == 2 ]]; then
			scenario="sql_perf_minimal_kube.scn"
		fi
		if [[ ${scn_user_selected} == 3 ]]; then
			scenario="sql_perf_light_kube.scn"
		fi
		if [[ ${scn_user_selected} == 4 ]]; then
			scenario="sql_perf_general_kube.scn"
		fi
		if [[ ${scn_user_selected} == 5 ]]; then
			scenario="sql_perf_detailed_kube.scn"
		fi
		echo ""

		#Check if scenario is set to one of the performance-impacting options
		if [[ "$scenario" == "sql_perf_detailed_kube.scn" ]]; then
	    echo -e "\033[0;31mAre you sure you want to use scenario: $scenario?\033[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
    	echo -e "\033[0;31mThis will collect performance data at the statement level, which may affect server performance.\033[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")

			read -p "Do you want to continue? (yes/no): " choice

			case "$choice" in
				yes|y|Y)
					echo "Proceeding with scenario: $scenario"
					echo ""
					;;
				no|n|N)
					echo "Exiting as requested."
					exit 1
					;;
				*)
					echo "Invalid input. Exiting."
					exit 1
					;;
			esac
		fi

		CONFIG_FILE="./${scenario}"
		#echo "Reading configuration values from config scenario file $CONFIG_FILE" 
		echo "Reading configuration values from config scenario file $CONFIG_FILE" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
		if [[ -f $CONFIG_FILE ]]; then
			. $CONFIG_FILE
			cp -f ./${scenario} ./pssdiag_collector.conf
		else
 			echo "" 
	 		echo "Error reading configuration file specified as input, make sure that $scenario exists" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			exit 1
		fi
	done 
fi

# ─────────────────────────────────────────────────────────────────────────────────────
# - Get user input for PerfStatsfilename                  
# - Check if PerfStatsfilename is valid, set to default if not
# - PSSDiag...               
# ─────────────────────────────────────────────────────────────────────────────────────
PerfStatsfilename_allowed_values=("sql_perf_stats_quickwaits.sql" "sql_perf_stats.sql")
if [[ ! " ${PerfStatsfilename_allowed_values[@]} " =~ " ${PerfStatsfilename} " ]]; then
    PerfStatsfilename="sql_perf_stats.sql"
fi

# Specify all the defaults here if not specified in config file.
####################################################
COLLECT_OS_CONFIG=${COLLECT_CONFIG:-"NO"}
COLLECT_OS_LOGS=${COLLECT_OS_LOGS:-"NO"}
COLLECT_OS_COUNTERS=${COLLECT_OS_COUNTERS:-"NO"}
OS_COUNTERS_INTERVAL=${OS_COUNTERS_INTERVAL:=-"15"}
COLLECT_PERFSTATS=${COLLECT_PERFSTATS:-"NO"}
COLLECT_EXTENDED_EVENTS=${COLLECT_EXTENDED_EVENTS:-"NO"}
EXTENDED_EVENT_TEMPLATE=${EXTENDED_EVENT_TEMPLATE:-"pssdiag_xevent_light"}
COLLECT_SQL_TRACE=${COLLECT_SQL_TRACE:-"NO"}
SQL_TRACE_TEMPLATE=${SQL_TRACE_TEMPLATE:-"pssdiag_trace_light"}
COLLECT_SQL_COUNTERS=${COLLECT_SQL_COUNTERS:-"NO"}
SQL_COUNTERS_INTERVAL=${SQL_COUNTERS_INTERVAL:-"15"}
COLLECT_SQL_MEM_STATS=${COLLECT_SQL_MEM_STATS:-"NO"}
COLLECT_SQL_LOGS=${COLLECT_SQL_LOGS:-"NO"}
COLLECT_SQL_SEC_AD_LOGS=${COLLECT_SQL_SEC_AD_LOGS:-"NO"}
CUSTOM_COLLECTOR=${CUSTOM_COLLECTOR:-"NO"}
COLLECT_HOST_SQL_INSTANCE=${COLLECT_HOST_SQL_INSTANCE:-"NO"}
COLLECT_CONTAINER=${COLLECT_CONTAINER:-"NO"}
if [[ ${authentication_mode} == "SQL" ]] || [[ ${authentication_mode} == "AD" ]] || [[ ${authentication_mode} == "NONE" ]]; then
	SQL_CONNECT_AUTH_MODE=${authentication_mode:-"SQL"}
fi

#by default we collect containers logs, many times there are no conatiners, it would be better to skip the logic for collect from containers
#Here we are checking if we have SQL container running on the host, if not we set COLLECT_CONTAINER to NO regardless of what is set in the config file, scn file.
COLLECT_CONTAINER="${COLLECT_CONTAINER^^}"
if [[ "$COLLECT_CONTAINER" != "NO" && "$is_docker_sql_containers" == "NO" ]] ; then
	COLLECT_CONTAINER="NO"
	sed -i 's/^COLLECT_CONTAINER=.*/COLLECT_CONTAINER=NO/' ./pssdiag_collector.conf
fi

# Determine if we need to collect SQL data at all
if [[ "$COLLECT_HOST_SQL_INSTANCE" == "NO" && "$COLLECT_CONTAINER" == "NO" ]] ; then
        COLLECT_SQL="NO"
else
        COLLECT_SQL="YES"
fi
##############################################################



echo -e "\x1B[2;34m========================================== Checking Prerequisites ==========================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")


# check if we have all pre-requisite to perform data collection
./check_pre_req.sh $COLLECT_SQL $COLLECT_OS_COUNTERS $scenario $authentication_mode
if [[ $? -ne 0 ]] ; then
	echo "Prerequisites for collecting all data are not met... exiting" | tee -a $pssdiag_log
	exit 1
else
	echo "All prerequisites for collecting data are met... proceeding" | tee -a $pssdiag_log
fi

#get copy of current config
cp pssdiag*.conf $working_dir/output

#get the user that started pssdiag and save it to log file in the current directory NOT the output directory
if [ "$EUID" -eq 0 ]; then
    echo "SUDO:YES" > "$outputdir/pssdiag_intiated_as_user.log"
	chown $(id -u "$SUDO_USER"):$(id -g "$SUDO_USER") "$outputdir/pssdiag_intiated_as_user.log"
	echo "SUDO_USER:$SUDO_USER" >> "$outputdir/pssdiag_intiated_as_user.log"
else
    echo "SUDO:NO" > "$outputdir/pssdiag_intiated_as_user.log"
	chown $(id -u):$(id -g) "$outputdir/pssdiag_intiated_as_user.log"
	echo "USER:$(id -un)" >> "$outputdir/pssdiag_intiated_as_user.log"
	echo "GROUP:$(id -gn)" >> "$outputdir/pssdiag_intiated_as_user.log"
fi

echo -e "\x1B[2;34m============================================================================================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
echo "$(date -u +"%T %D") PSSDiag Executed with sudo: $([ -n "$SUDO_USER" ] && echo "YES" || echo "NO")" >> $pssdiag_log
echo "$(date -u +"%T %D") PSSDiag version: ${script_version}" >> $pssdiag_log
echo "$(date -u +"%T %D") Executing PSSDiag on: ${HOSTNAME}"  >> $pssdiag_log
echo "$(date -u +"%T %D") Scenario file used: ${scenario}" >> $pssdiag_log
echo "$(date -u +"%T %D") Perf Stats file used: ${PerfStatsfilename}" >> $pssdiag_log
echo "$(date -u +"%T %D") Authentication mode used: ${authentication_mode}" >> $pssdiag_log
echo "$(date -u +"%T %D") Working Directory: ${working_dir}" >> $pssdiag_log 
echo "$(date -u +"%T %D") Output Directory: ${outputdir}" >> $pssdiag_log 
#get_host_instance_status
echo "$(date -u +"%T %D") Host instance service installed? ${is_host_instance_service_installed}" >> $pssdiag_log
echo "$(date -u +"%T %D") Host instance service enabled? ${is_host_instance_service_enabled}" >> $pssdiag_log
echo "$(date -u +"%T %D") Host instance service active? ${is_host_instance_service_active}" >> $pssdiag_log
echo "$(date -u +"%T %D") Host instance process running? ${is_host_instance_process_running}" >> $pssdiag_log
#get_container_instance_status
echo "$(date -u +"%T %D") Docker installed? ${is_container_runtime_service_installed}" >> $pssdiag_log
echo "$(date -u +"%T %D") Docker service enabled? ${is_container_runtime_service_enabled}" >> $pssdiag_log
echo "$(date -u +"%T %D") Docker service active? ${is_container_runtime_service_active}" >> $pssdiag_log
echo "$(date -u +"%T %D") Using sql docker containers? ${is_docker_sql_containers}" >> $pssdiag_log
echo "$(date -u +"%T %D") Using sql podman containers? ${is_podman_sql_containers}" >> $pssdiag_log
echo "$(date -u +"%T %D") Using sql podman containers without docker engine? ${is_podman_sql_containers_no_docker_runtime}" >> $pssdiag_log
#pssdiag_inside_container_get_instance_status
echo "$(date -u +"%T %D") Running inside container? ${is_instance_inside_container_active}" >> $pssdiag_log
echo "$(date -u +"%T %D") Running inside WSL? ${is_host_instance_inside_wsl}" >> $pssdiag_log

#Check OS build info
echo "$(date -u +"%T %D") Running on an Azure VM? $([ "$(cat /sys/devices/virtual/dmi/id/chassis_asset_tag 2>/dev/null)" = "7783-7084-3265-9085-8269-3286-77" ] && echo "YES" || echo "NO")" >> $pssdiag_log
echo "$(date -u +"%T %D") HOST Distribution: $(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"') $(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')" >> $pssdiag_log
echo "$(date -u +"%T %D") HOST Kernel: $(uname -r)" >> $pssdiag_log
echo "$(date -u +"%T %D") BASH_VERSION: ${BASH_VERSION}" >> $pssdiag_log

echo -e "\x1B[2;34m============================================= Starting PSSDiag =============================================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")


# if we just need a snapshot of logs, we do not need to invoke background collectors
# so we short circuit to stop_collector and just collect static logs
if [[ "$scenario" == "static_collect.scn" ]] || [[ "$scenario" == "static_collect_kube.scn" ]];then
	echo -e "$(date -u +"%T %D") Static scenario was selected; performance data collection is not required... " | tee -a $pssdiag_log
	echo -e "$(date -u +"%T %D") Proceeding to stop and execute static log collection..." | tee -a $pssdiag_log
	./stop_collector.sh $authentication_mode
	exit 0
fi 


if [[ $COLLECT_OS_COUNTERS == [Yy][eE][sS] ]] ; then
        #Collecting Linux Perf countners
	echo -e "$(date -u +"%T %D") Starting operating system collectors..."  | tee -a $pssdiag_log
        echo -e "$(date -u +"%T %D") Starting io stats collector as a background job..." | tee -a $pssdiag_log
        (
        bash ./collect_io_stats.sh $OS_COUNTERS_INTERVAL &
        )
        echo -e "$(date -u +"%T %D") Starting cpu stats collector as a background job..." | tee -a $pssdiag_log
        (
        bash ./collect_cpu_stats.sh $OS_COUNTERS_INTERVAL &
        )
        echo -e "$(date -u +"%T %D") Starting memory collector as a background job..." | tee -a $pssdiag_log
        (
        bash ./collect_mem_stats.sh $OS_COUNTERS_INTERVAL &
        )
        echo -e "$(date -u +"%T %D") Starting process collector as a background job..." | tee -a $pssdiag_log
        (
        bash  ./collect_process_stats.sh $OS_COUNTERS_INTERVAL & 
        )
        echo -e "$(date -u +"%T %D") Starting network stats collector as a background job..." | tee -a $pssdiag_log
        (
        bash  ./collect_network_stats.sh $OS_COUNTERS_INTERVAL &
        )
        #Collecting Timezone required to process some of the data
        date +%z > $outputdir/${HOSTNAME}_os_timezone.info &
fi

######################################################################################
# TSQL based collectors                                                              #
# - this section will connect to sql server instances and collect sql script outputs #
######################################################################################

# ────────────────────────────
# - Collect "host_instance"                   
# - SQL running on VM                
# - PSSDiag is running on host       
# ────────────────────────────


if [[ "$COLLECT_HOST_SQL_INSTANCE" == "YES" ]];then
	#we collect information from base host instance of SQL Server
	get_host_instance_status
	if [ "${is_host_instance_process_running}" == "YES" ]; then
		SQL_LISTEN_PORT=$(get_sql_listen_port "host_instance")
		#SQL_SERVER_NAME="$HOSTNAME,$SQL_LISTEN_PORT"
		#echo -e "" | tee -a $pssdiag_log
		echo -e "\x1B[7m$(date -u +"%T %D") Collecting startup information from host instance $HOSTNAME and port ${SQL_LISTEN_PORT}...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
		sql_connect "host_instance" "${HOSTNAME}" "${SQL_LISTEN_PORT}" "${authentication_mode}"
		sqlconnect=$?
		if [[ $sqlconnect -ne 1 ]]; then
			echo -e "\x1B[31mTesting the connection to host instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			echo -e "Please refer to the above lines for errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
		else
			sql_collect_perfstats "${HOSTNAME}" "host_instance"
			sql_collect_counters "${HOSTNAME}" "host_instance"
			sql_collect_memstats "${HOSTNAME}" "host_instance"
			sql_collect_sql_custom "${HOSTNAME}" "host_instance"
			sql_collect_xevent "${HOSTNAME}" "host_instance"
			sql_collect_trace "${HOSTNAME}" "host_instance"
			sql_collect_config "${HOSTNAME}" "host_instance"
			sql_collect_linux_snapshot "${HOSTNAME}" "host_instance"
			sql_collect_perfstats_snapshot "${HOSTNAME}" "host_instance"
		fi
	fi
fi

# ──────────────────────────────────────
# - Collect "instance"                   
# - SQL running inside container
# - PSSDiag is running inside container       
# ──────────────────────────────────────

if [[ "$COLLECT_HOST_SQL_INSTANCE" == "YES" ]];then
	pssdiag_inside_container_get_instance_status
	if [ "${is_instance_inside_container_active}" == "YES" ]; then
	    SQL_SERVER_NAME="$HOSTNAME,1433"
		#echo -e "" | tee -a $pssdiag_log
		echo -e "\x1B[7m$(date -u +"%T %D") Collecting startup information from instance $HOSTNAME and port 1433...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
		sql_connect "instance" "${HOSTNAME}" "1433" "${authentication_mode}"
		sqlconnect=$?
		if [[ $sqlconnect -ne 1 ]]; then
			echo -e "\x1B[31mTesting the connection to instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
			echo -e "Please refer to the above lines for errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
		else
			sql_collect_perfstats "${HOSTNAME}" "instance"
			sql_collect_counters "${HOSTNAME}" "instance"
			sql_collect_memstats "${HOSTNAME}" "instance"
			sql_collect_sql_custom "${HOSTNAME}" "instance"
			sql_collect_xevent "${HOSTNAME}" "instance"
			sql_collect_trace "${HOSTNAME}" "instance"
			sql_collect_config "${HOSTNAME}" "instance"
			sql_collect_linux_snapshot "${HOSTNAME}" "instance"
			sql_collect_perfstats_snapshot "${HOSTNAME}" "instance"
		fi
	fi

fi

# ──────────────────────────────────────
# - Collect "container_instance"                   
# - SQL running as docker container
# - PSSDiag is running on VM       
# ──────────────────────────────────────

if [[ "$COLLECT_CONTAINER" != "NO" ]]; then
# we need to collect logs from containers
	get_container_instance_status
	if [ "${is_container_runtime_service_active}" == "YES" ]; then
        if [[ "$COLLECT_CONTAINER" != "ALL" ]]; then
        # we need to process just the specific container
            dockerid=$(docker ps -q --filter name=$COLLECT_CONTAINER)
            get_docker_mapped_port "${dockerid}"
 	        #SQL_SERVER_NAME="$dockername,$dockerport"
			#echo -e "" | tee -a $pssdiag_log
			echo -e "\x1B[7m$(date -u +"%T %D") Collecting startup information from container instance ${dockername} and port ${dockerport}\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	        sql_connect "container_instance" "${dockername}" "${dockerport}" "${authentication_mode}"
        	sqlconnect=$?
	        if [[ $sqlconnect -ne 1 ]]; then
        	        echo -e "\x1B[31mTesting the connection to container instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
					echo -e "Please refer to the above lines for errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	        else
           	    sql_collect_perfstats "${dockername}" "container_instance"      
				sql_collect_counters "${dockername}" "container_instance"
	            sql_collect_memstats "${dockername}" "container_instance"
        	    sql_collect_sql_custom "${dockername}" "container_instance"
                sql_collect_xevent "${dockername}" "container_instance"
				sql_collect_trace "${dockername}" "container_instance"
				sql_collect_config "${dockername}" "container_instance"
				sql_collect_linux_snapshot "${dockername}" "container_instance"
				sql_collect_perfstats_snapshot "${dockername}" "container_instance"
	        fi
	# we finished processing the requested container
        else
        # we need to iterate through all containers
			    #dockerid_col=$(docker ps | grep 'mcr.microsoft.com/mssql/server' | awk '{ print $1 }')
				dockerid_col=$(docker ps --no-trunc | grep -e '/opt/mssql/bin/sqlservr' | awk '{ print $1 }')
                for dockerid in $dockerid_col;
                do
                	get_docker_mapped_port "${dockerid}"
	                #SQL_SERVER_NAME="$dockername,$dockerport"
					#echo -e ""  | tee -a $pssdiag_log
					echo -e "\x1B[7m$(date -u +"%T %D") Collecting startup information from container_instance ${dockername} and port ${dockerport}\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	                sql_connect "container_instance" "${dockername}" "${dockerport}" "${authentication_mode}"
        	        sqlconnect=$?
                	if [[ $sqlconnect -ne 1 ]]; then
                        	echo -e "\x1B[31mTesting the connection to container instance using $authentication_mode authentication failed." | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
							echo -e "Please refer to the above lines for connectivity and authentication errors...\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
	                else
						sql_collect_perfstats "${dockername}" "container_instance"
                	    sql_collect_counters "${dockername}" "container_instance"
	                    sql_collect_memstats "${dockername}" "container_instance"
        	            sql_collect_sql_custom "${dockername}" "container_instance"
                	    sql_collect_xevent "${dockername}" "container_instance"
						sql_collect_trace "${dockername}" "container_instance"
						sql_collect_config "${dockername}" "container_instance"
        	            sql_collect_linux_snapshot "${dockername}" "container_instance"
						sql_collect_perfstats_snapshot "${dockername}" "container_instance"
	                fi
                done;
			# we finished processing all the container
        fi
	fi
fi

# anchor
# at the end we will always launch an anchor script that we will use to detect if pssdiag is currently running
# if this anchor script is running already we will not allow another pssdiag run to proceed
bash ./pssdiag_anchor.sh &
anchorpid=$!
printf "%s\n" "$anchorpid" >> $outputdir/pssdiag_stoppids_os_collectors.log
pgrep -P $anchorpid  >> $outputdir/pssdiag_stoppids_os_collectors.log
# anchor

echo -e "\x1B[2;34m==============================  Startup Completed, Data Collection in Progress ==============================\x1B[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
echo -e "" | tee -a $pssdiag_log
echo -e "\033[0;33m############################################################################################################\033[0;31m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
echo -e "\033[0;33m#                 Please reproduce the problem now and then stop data collection afterwards                #\033[0;31m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
echo -e "\033[0;33m############################################################################################################\033[0;31m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
echo -e "" | tee -a $pssdiag_log
if [ "${is_instance_inside_container_active}" == "NO" ]; then
	echo -e "\033[1;33m    Performance collectors have started in the background. to stop them run 'sudo ./stop_collector.sh'...   \033[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
else
	echo -e "\033[1;33m    Performance collectors have started in the background. to stop them run './stop_collector.sh'...   \033[0m" | tee >(sed -e 's/\x1b\[[0-9;]*m//g' >> "$pssdiag_log")
fi
echo -e "" | tee -a $pssdiag_log
exit 0
