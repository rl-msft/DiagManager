#!/bin/bash

SQL_SERVER_NAME=${1}
CONN_AUTH_OPTIONS=${2}
        
QUERY=$'SET NOCOUNT ON;
SELECT d.name AS db_name, mf.physical_name
FROM sys.master_files AS mf
JOIN sys.databases AS d ON d.database_id = mf.database_id
ORDER BY d.name, mf.file_id;'

# Collect data into an array
data=()
while IFS='|' read -r db_name physical_name; do
        db_name=$(echo "$db_name" | sed 's/^ *//;s/ *$//')
        physical_name=$(echo "$physical_name" | sed 's/^ *//;s/ *$//')

        lower_path=$(echo "$physical_name" | tr '[:upper:]' '[:lower:]')

        if [[ -e "$physical_name" ]]; then
                actual_path="$physical_name"
        elif [[ -e "$lower_path" ]]; then
                actual_path="$lower_path"
        else
                actual_path="$physical_name (missing)"
        fi

        resolved=$(readlink -f -- "$actual_path" 2>/dev/null || echo "$actual_path")
        actual_path="$resolved"

        df_output=$(df -T -- "$actual_path" | awk 'NR==2')
        fs_type=$(echo "$df_output" | awk '{print $2}')
        fs=$(echo "$df_output" | awk '{print $1}')
        mount_point=$(echo "$df_output" | awk '{print $7}')

        dpofua=$(sg_modes "$fs" 2>/dev/null | grep -oE 'DpoFua=[01]' | sed 's/.*=//')
        [[ -z "${dpofua:-}" ]] && dpofua="-"

        block_info=$(lsblk -no NAME,TYPE "$fs" 2>/dev/null | head -n 1)
        block_device=$(echo "$block_info" | awk '{print $1}')
        device_type=$(echo "$block_info" | awk '{print $2}')
        [[ -z "$block_device" ]] && block_device="-"
        [[ -z "$device_type" ]] && device_type="-"

        disk=$(lvdisplay -m "$fs" 2>/dev/null | awk '/Physical volume/ {print $3}')
        [[ -z "$disk" ]] && disk="-"

        data+=("$db_name|$actual_path|$mount_point|$fs_type|$dpofua|$fs|$device_type|$block_device|$disk")
done < <($(ls -1 /opt/mssql-tools*/bin/sqlcmd | tail -n -1) -S$SQL_SERVER_NAME $CONN_AUTH_OPTIONS -C -h -1 -W -s '|' -Q "$QUERY" | grep -v '^$')

# Determine max widths
max_db=8; max_path=13; max_mount=5; max_fs=10; max_dpofua=6; max_device=6; max_devtype=7; max_block=8; max_disk=4
for row in "${data[@]}"; do
IFS='|' read -r db path mount fs dpofua device devtype block disk <<< "$row"
(( ${#db} > max_db )) && max_db=${#db}
(( ${#path} > max_path )) && max_path=${#path}
(( ${#mount} > max_mount )) && max_mount=${#mount}
(( ${#fs} > max_fs )) && max_fs=${#fs}
(( ${#dpofua} > max_dpofua )) && max_dpofua=${#dpofua}
(( ${#device} > max_device )) && max_device=${#device}
(( ${#devtype} > max_devtype )) && max_devtype=${#devtype}
(( ${#block} > max_block )) && max_block=${#block}
(( ${#disk} > max_disk )) && max_disk=${#disk}
done

# Print header
printf "%-${max_db}s %-${max_path}s %-${max_mount}s %-${max_fs}s %-${max_dpofua}s %-${max_device}s %-${max_devtype}s %-${max_block}s %-${max_disk}s\n" \
"Database" "Physical_Name" "Mount" "Filesystem" "dpofua" "device" "DevType" "BlockDev" "Disk"
printf "%s\n" "$(printf '%0.s-' $(seq 1 $((max_db + max_path + max_mount + max_fs + max_dpofua + max_device + max_devtype + max_block + max_disk + 9))))"

# Print rows
for row in "${data[@]}"; do
IFS='|' read -r db path mount fs dpofua device devtype block disk <<< "$row"
printf "%-${max_db}s %-${max_path}s %-${max_mount}s %-${max_fs}s %-${max_dpofua}s %-${max_device}s %-${max_devtype}s %-${max_block}s %-${max_disk}s\n" \
"$db" "$path" "$mount" "$fs" "$dpofua" "$device" "$devtype" "$block" "$disk"
done        