#!/usr/bin/env bash
# =============================================================================
# SQL on Linux best practice analyzer
# -----------------------------------------------------------------------------
# Read-only analyzer for SQL Server on Linux host configuration.
# Checks:
#   - Filesystem & mount options (XFS recommended, noatime)
#   - FUA path (TraceFlags 3979/3982 + control.writethrough/alternatewritethrough)
#   - Device DPOFUA via sg_modes (sg3_utils) on the actual mount device
#   - Open file limits (systemd LimitNOFILE & PAM limits.d)
#   - TuneD profile, CPU governor, energy_perf_bias, min_perf_pct, C-states
#   - sysctl tunings (swappiness=1, dirty ratios, NUMA auto-balancing, scheduler)
#   - Transparent Huge Pages (enabled/madvise)
#   - Disk readahead (target 4096 KB)
#
# Key references (Microsoft Learn):
#   - Performance best practices for SQL Server on Linux (ver. 17 / 2025)
#     https://learn.microsoft.com/sql/linux/sql-server-linux-performance-best-practices?view=sql-server-ver17
#   - Earlier guidance (ver. 16) for cross-checking kernel/CPU tunings
#     https://learn.microsoft.com/sql/linux/sql-server-linux-performance-best-practices?view=sql-server-ver16
#
# This script DOES NOT modify the system.
# VERSION="beta 1.5"
# =============================================================================

TITLE="SQL on Linux best practice analyzer"
VERSION="1.5 beta"
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"

pass(){ echo -e "${GREEN}PASS${NC}  - $*"; }
warn(){ echo -e "${YELLOW}WARN${NC}  - $*"; }
fail(){ echo -e "${RED}FAIL${NC}  - $*"; }

need_cmd() { command -v "$1" &>/dev/null; }

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------
EXPLAIN_ALL=0
for arg in "$@"; do
  case "$arg" in
    --explain-all) EXPLAIN_ALL=1 ;;
    *) ;;
  esac
done

# -----------------------------------------------------------------------------
# Recommendation WHY messages (printed on WARN/FAIL; on PASS if --explain-all)
# -----------------------------------------------------------------------------
declare -A WHY
WHY[fs_xfs]="XFS is the recommended filesystem for SQL Server data/log on Linux for consistent performance characteristics."
WHY[mount_noatime]="noatime avoids extra metadata writes on access, reducing I/O overhead for data/log volumes."
WHY[fua_expected]="With XFS on a distro supporting FUA, TF 3979 + writethrough=1 + alternatewritethrough=0 enables efficient, durable writes without extra flushes."
WHY[fua_nonfua]="When FUA path isn’t fully supported, use TF 3982/default + writethrough=1 + alternatewritethrough=1 to preserve durability and performance."
WHY[dpo_fua1]="Device reports DpoFua=1 so storage honors FUA writes; this aligns with the FUA path recommendation."
WHY[dpo_fua0]="Device reports DpoFua=0, so FUA isn’t honored at the device layer; stay on non-FUA path settings."
WHY[nofile]="High-connection/IO workloads can exhaust default open-file limits; raising to ~1,048,576 prevents resource exhaustion."
WHY[tuned_profile]="TuneD 'mssql' (RHEL 8+) or 'throughput-performance' applies kernel/CPU tunings suited for throughput workloads."
WHY[governor]="Governor 'performance' keeps CPUs at higher frequencies for latency-sensitive database workloads."
WHY[epb]="energy_perf_bias='performance' prioritizes performance over power savings for steadier query latency."
WHY[min_perf_pct]="intel_pstate min_perf_pct=100 keeps the minimum CPU performance floor high to avoid frequency dips."
WHY[cstates]="Capping to C1 reduces wake-up latency and jitter for CPU-bound OLTP workloads."
WHY[thp]="SQL Server on Linux benefits from THP=always/madvise for large pages and reduced TLB pressure."
WHY[swappiness]="swappiness=1 minimizes swapping of SQL Server memory; swapping DB pages severely degrades performance."
WHY[dirty_ratio]="A balanced dirty_ratio prevents excessive dirty pages that stall I/O under bursty write workloads."
WHY[dirty_background_ratio]="A lower background ratio kicks off writeback earlier to smooth I/O and avoid large flush spikes."
WHY[sched_gran]="Scheduler granularity tweaks can help reduce context switch overhead on throughput profiles."
WHY[sched_wakeup]="Wakeup granularity tuning helps reduce wake storming for many runnable threads."
WHY[numa_bal]="Auto NUMA balancing can migrate pages across nodes; disabling reduces cross-node latency for pinned workloads."
WHY[max_map_count]="Higher vm.max_map_count reduces risk of VAS fragmentation issues on large hosts."
WHY[readahead]="Setting readahead to ~4096 KB can improve sequential read throughput for database file scans."

explain(){ # explain <key>
  local k="$1"; local msg="${WHY[$k]:-}"
  [[ -n "$msg" ]] && echo "        WHY: $msg"
}

# -----------------------------------------------------------------------------
# Environment discovery
# -----------------------------------------------------------------------------
echo "=== $TITLE v$VERSION ==="
date

OS_ID="$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")"
OS_VER_ID="$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-unknown}")"
KERNEL="$(uname -sr)"
echo "OS: $OS_ID $OS_VER_ID | Kernel: $KERNEL"

MSSQL_CONF="/var/opt/mssql/mssql.conf"
MSSQL_SVC="mssql-server"

# Default SQL paths (may be overridden in mssql.conf)
SQL_DATA_DIR="/var/opt/mssql/data"
SQL_LOG_DIR="/var/opt/mssql/data"

if [ -f "$MSSQL_CONF" ]; then
  DATA_OVERRIDE="$(awk -F'=' '/^\s*defaultdatadir\s*=/{gsub(/ /,"",$2); print $2}' "$MSSQL_CONF" 2>/dev/null || true)"
  LOG_OVERRIDE="$(awk -F'=' '/^\s*defaultlogdir\s*=/{gsub(/ /,"",$2); print $2}' "$MSSQL_CONF" 2>/dev/null || true)"
  [ -n "${DATA_OVERRIDE:-}" ] && SQL_DATA_DIR="$DATA_OVERRIDE"
  [ -n "${LOG_OVERRIDE:-}" ] && SQL_LOG_DIR="$LOG_OVERRIDE"
fi

# Map a path -> mount source device
blk_for_path() {
  local p="$1"
  findmnt -T "$p" -o SOURCE -n 2>/dev/null || true
}

# Get config value from mssql.conf (case-insensitive)
get_conf_val() {
  local key="$1"
  [ -f "$MSSQL_CONF" ] || { echo ""; return; }
  awk -F'=' -v k="$key" '
    BEGIN{ IGNORECASE=1 }
    /^\s*\[/{sect=$0}
    $1 ~ k { gsub(/ /,"",$2); print tolower($2) }
  ' "$MSSQL_CONF" 2>/dev/null | tail -1
}

ver_ge() { printf '%s\n%s\n' "$1" "$2" | sort -V | head -1 | grep -qx "$2"; }

# -----------------------------------------------------------------------------
# Service presence
# -----------------------------------------------------------------------------
echo -e "\n--- SQL Server service ---"
if systemctl is-active --quiet "$MSSQL_SVC"; then
  pass "Service '$MSSQL_SVC' is active"; [[ $EXPLAIN_ALL -eq 1 ]] && echo "        WHY: Service should be running to validate runtime-affected settings."
else
  warn "Service '$MSSQL_SVC' not active (checks continue)"
fi

# -----------------------------------------------------------------------------
# Filesystem & mounts (XFS recommended, noatime)
# -----------------------------------------------------------------------------
echo -e "\n--- Filesystem & mount options (XFS recommended, use noatime) ---"
for PTH in "$SQL_DATA_DIR" "$SQL_LOG_DIR"; do
  [ -e "$PTH" ] || { warn "Path not found: $PTH (skipping)"; continue; }

  SRC="$(findmnt -T "$PTH" -o SOURCE -n 2>/dev/null || true)"
  FST="$(findmnt -T "$PTH" -o FSTYPE -n 2>/dev/null || true)"
  OPTS="$(findmnt -T "$PTH" -o OPTIONS -n 2>/dev/null || true)"
  echo "findmnt: $PTH -> dev=$SRC fstype=$FST opts=$OPTS"

  if [[ "$FST" == "xfs" ]]; then
    pass "Filesystem for $PTH is XFS (recommended)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain fs_xfs
  elif [[ "$FST" == "ext4" ]]; then
    warn "Filesystem for $PTH is ext4 (supported; XFS generally recommended)"; explain fs_xfs
  else
    warn "Filesystem for $PTH is '$FST' (verify support for SQL data/log)"; explain fs_xfs
  fi

  if grep -qw noatime <<<"$OPTS"; then
    pass "$PTH mount has 'noatime'"; [[ $EXPLAIN_ALL -eq 1 ]] && explain mount_noatime
  else
    warn "$PTH mount missing 'noatime' (recommend adding to /etc/fstab)"; explain mount_noatime
  fi
done

# -----------------------------------------------------------------------------
# FUA configuration (TFs + writethrough)
# -----------------------------------------------------------------------------
echo -e "\n--- FUA (durable I/O) configuration ---"
SUPPORTS_FUA="unknown"
case "$OS_ID" in
  rhel|redhat) [[ "$OS_VER_ID" =~ ^[0-9]+ ]] && ver_ge "$OS_VER_ID" "8" && SUPPORTS_FUA="yes" ;;
  sles|suse)   if [[ "$OS_VER_ID" == 12* ]]; then SUPPORTS_FUA="maybe"; else ver_ge "$OS_VER_ID" "15" && SUPPORTS_FUA="yes"; fi ;;
  ubuntu)      ver_ge "$OS_VER_ID" "18.04" && SUPPORTS_FUA="yes" ;;
esac

is_xfs_sql=0
for PTH in "$SQL_DATA_DIR" "$SQL_LOG_DIR"; do
  [ -e "$PTH" ] || continue
  FST="$(findmnt -T "$PTH" -o FSTYPE -n 2>/dev/null || true)"
  [[ "$FST" == "xfs" ]] && is_xfs_sql=1
done

TF3979="no"; TF3982="no"
if [ -f "$MSSQL_CONF" ]; then
  if grep -qiE '^\s*\[traceflag\]' "$MSSQL_CONF"; then
    grep -qiE '^\s*traceflag[0-9]+\s*=\s*3979' "$MSSQL_CONF" && TF3979="yes"
    grep -qiE '^\s*traceflag[0-9]+\s*=\s*3982' "$MSSQL_CONF" && TF3982="yes"
  fi
fi
WT="$(get_conf_val 'writethrough')";   WT="${WT:-1}"
ALTWT="$(get_conf_val 'alternatewritethrough')"; ALTWT="${ALTWT:-1}"

if [[ "$is_xfs_sql" -eq 1 && "$SUPPORTS_FUA" == "yes" ]]; then
  if [[ "$TF3979" == "yes" && "$WT" == "1" && "$ALTWT" == "0" ]]; then
    pass "FUA path OK (XFS + supported distro + TF3979 + writethrough=1 + alternatewritethrough=0)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain fua_expected
  else
    fail "FUA path expected. Set: TF 3979; control.writethrough=1; control.alternatewritethrough=0 in $MSSQL_CONF"; explain fua_expected
  fi
else
  if [[ "$WT" == "1" && "$ALTWT" == "1" && ( "$TF3982" == "yes" || "$TF3979" == "no" ) ]]; then
    pass "Non-FUA path OK (writethrough=1 & alternatewritethrough=1; TF3982 default)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain fua_nonfua
  else
    warn "Non-FUA path detected. Recommend writethrough=1 & alternatewritethrough=1 and do NOT set TF3979"; explain fua_nonfua
  fi
fi

# -----------------------------------------------------------------------------
# Device-level DPOFUA using sg_modes (actual mount device)
# -----------------------------------------------------------------------------
echo -e "\n--- Device-level DPOFUA check using sg_modes (sg3_utils) ---"
if need_cmd sg_modes; then
  for PTH in "$SQL_DATA_DIR" "$SQL_LOG_DIR"; do
    SRC="$(blk_for_path "$PTH")"
    [[ -z "$SRC" ]] && continue
    DEV="$SRC"
    echo "Checking $DEV ..."
    OUT="$(sg_modes "$DEV" 2>/dev/null || true)"
    if [[ -z "$OUT" ]]; then
      warn "sg_modes failed for $DEV (may be NVMe or unsupported)"; continue
    fi
    if echo "$OUT" | grep -qi 'DpoFua'; then
      VAL="$(echo "$OUT" | awk '/DpoFua/{print $2}' | head -1)"
      if [[ "$VAL" == "1" ]]; then
        pass "$DEV reports DpoFua=1 (FUA supported)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain dpo_fua1
      else
        warn "$DEV reports DpoFua=0 (device may not support FUA)"; explain dpo_fua0
      fi
    else
      warn "Could not parse DpoFua from sg_modes output for $DEV"
    fi
  done
else
  warn "'sg_modes' not found. Install sg3_utils to enable DPOFUA checks."
fi

# -----------------------------------------------------------------------------
# Open file limits
# -----------------------------------------------------------------------------
echo -e "\n--- Open file limits (nofile) ---"
if systemctl show "$MSSQL_SVC" &>/dev/null; then
  NOFILE_RAW="$(systemctl show "$MSSQL_SVC" -p LimitNOFILE --value 2>/dev/null || echo "")"
  NOFILE_LC="${NOFILE_RAW,,}"

  if [[ -z "$NOFILE_RAW" ]]; then
    warn "systemd LimitNOFILE is empty/unavailable for $MSSQL_SVC"; explain nofile

  elif [[ "$NOFILE_LC" == "infinity" || "$NOFILE_LC" == "unlimited" ]]; then
    pass "systemd LimitNOFILE=$NOFILE_RAW for $MSSQL_SVC (unlimited)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain nofile

  elif [[ "$NOFILE_RAW" =~ ^[0-9]+$ ]]; then
    if (( NOFILE_RAW >= 1048576 )); then
      pass "systemd LimitNOFILE=$NOFILE_RAW for $MSSQL_SVC"; [[ $EXPLAIN_ALL -eq 1 ]] && explain nofile
    else
      warn "systemd LimitNOFILE=$NOFILE_RAW for $MSSQL_SVC (recommend >= 1048576 or unlimited)"; explain nofile
    fi
  else
    warn "systemd LimitNOFILE=$NOFILE_RAW for $MSSQL_SVC (unrecognized format)"; explain nofile
  fi
else
  warn "systemd not available or $MSSQL_SVC not managed by systemd"
fi

# PAM /etc/security/limits.d check
if [ -f /etc/security/limits.d/99-mssql-server.conf ]; then
  if grep -Eq '^\s*mssql\s+.*\bnofile\b\s+(1048576|unlimited)\b' /etc/security/limits.d/99-mssql-server.conf; then
    pass "PAM limits.d sets nofile to 1048576 or unlimited for mssql"; [[ $EXPLAIN_ALL -eq 1 ]] && explain nofile
  else
    warn "Review /etc/security/limits.d/99-mssql-server.conf (recommend 'mssql - nofile 1048576' or 'unlimited')"; explain nofile
  fi
else
  warn "Missing /etc/security/limits.d/99-mssql-server.conf (open-files limit)"
fi

# -----------------------------------------------------------------------------
# TuneD / CPU performance states
# -----------------------------------------------------------------------------
echo -e "\n--- CPU governor, energy policy, C-states, TuneD ---"
if need_cmd tuned-adm; then
  ACTIVE_PROFILE="$(tuned-adm active 2>/dev/null | awk -F': ' '/Current active profile:/{print $2}')"
  if [[ "$ACTIVE_PROFILE" == "mssql" || "$ACTIVE_PROFILE" == "throughput-performance" ]]; then
    pass "TuneD active profile: $ACTIVE_PROFILE"; [[ $EXPLAIN_ALL -eq 1 ]] && explain tuned_profile
  else
    warn "TuneD active profile: ${ACTIVE_PROFILE:-none} (recommend 'mssql' on RHEL 8+ or 'throughput-performance')"; explain tuned_profile
  fi
else
  warn "tuned-adm not found (cannot verify TuneD profile)"
fi

# CPU governor
if ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null; then
  GOV_ISSUE=0
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    g=$(cat "$f" 2>/dev/null || echo "")
    [[ "$g" == "performance" ]] || GOV_ISSUE=1
  done
  (( GOV_ISSUE==0 )) && { pass "CPU governor is 'performance' on all CPUs"; [[ $EXPLAIN_ALL -eq 1 ]] && explain governor; } \
                      || { warn "CPU governor not 'performance' on all CPUs (set via cpupower/TuneD)"; explain governor; }
else
  warn "CPU freq governor files not present (skip)"
fi

# energy_perf_bias
if need_cmd x86_energy_perf_policy; then
  if x86_energy_perf_policy -r 2>/dev/null | grep -qi 'performance'; then
    pass "energy_perf_bias is 'performance'"; [[ $EXPLAIN_ALL -eq 1 ]] && explain epb
  else
    warn "energy_perf_bias not 'performance' (set via x86_energy_perf_policy)"; explain epb
  fi
else
  SYS_BIAS=$(cat /sys/devices/system/cpu/cpu0/power/energy_perf_bias 2>/dev/null || echo "")
  if [[ "$SYS_BIAS" == "0" || "$SYS_BIAS" == "" ]]; then
    pass "energy_perf_bias appears to be performance (0)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain epb
  else
    warn "energy_perf_bias not set to performance (0)"; explain epb
  fi
fi

# intel_pstate min_perf_pct
if [ -r /sys/devices/system/cpu/intel_pstate/min_perf_pct ]; then
  MINP=$(cat /sys/devices/system/cpu/intel_pstate/min_perf_pct)
  if [[ "$MINP" -ge 100 ]]; then
    pass "intel_pstate min_perf_pct=$MINP"; [[ $EXPLAIN_ALL -eq 1 ]] && explain min_perf_pct
  else
    warn "intel_pstate min_perf_pct=$MINP (recommend 100)"; explain min_perf_pct
  fi
fi

# C-states
if [ -r /sys/module/intel_idle/parameters/max_cstate ]; then
  CSTATE=$(cat /sys/module/intel_idle/parameters/max_cstate)
  if [[ "$CSTATE" -le 1 ]]; then
    pass "Max C-state is C$CSTATE (C1 or lower)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain cstates
  else
    warn "Max C-state is C$CSTATE (recommend C1)"; explain cstates
  fi
fi

# -----------------------------------------------------------------------------
# THP & sysctl tunings
# -----------------------------------------------------------------------------
echo -e "\n--- Transparent Huge Pages (THP) & sysctl tunings ---"
if [ -r /sys/kernel/mm/transparent_hugepage/enabled ]; then
  THP_STATE="$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
  if grep -q '\[always\]' <<<"$THP_STATE" || grep -q '\[madvise\]' <<<"$THP_STATE"; then
    pass "THP enabled ($THP_STATE)"; [[ $EXPLAIN_ALL -eq 1 ]] && explain thp
  else
    warn "THP is disabled ($THP_STATE) — SQL Server on Linux guidance expects THP enabled"; explain thp
  fi
fi

# sysctl checker with reason
sysctl_chk(){
  # sysctl_chk <key> <want> <cmp> <reasonKey>
  local key="$1" want="$2" cmp="$3" rkey="$4"
  local cur
  cur="$(sysctl -n "$key" 2>/dev/null || echo "")"
  case "$cmp" in
    eq)
      if [[ "$cur" == "$want" ]]; then
        pass "$key=$cur"; [[ $EXPLAIN_ALL -eq 1 ]] && explain "$rkey"
      else
        warn "$key=$cur (recommend $want)"; explain "$rkey"
      fi
      ;;
    ge)
      if [[ -n "$cur" && "$cur" -ge "$want" ]]; then
        pass "$key=$cur"; [[ $EXPLAIN_ALL -eq 1 ]] && explain "$rkey"
      else
        warn "$key=$cur (recommend >= $want)"; explain "$rkey"
      fi
      ;;
    le)
      if [[ -n "$cur" && "$cur" -le "$want" ]]; then
        pass "$key=$cur"; [[ $EXPLAIN_ALL -eq 1 ]] && explain "$rkey"
      else
        warn "$key=$cur (recommend <= $want)"; explain "$rkey"
      fi
      ;;
  esac
}

# Updated swappiness per latest guidance: 1
sysctl_chk vm.swappiness 1 eq swappiness
sysctl_chk vm.dirty_ratio 40 eq dirty_ratio
sysctl_chk vm.dirty_background_ratio 10 eq dirty_background_ratio
# Optional scheduler knobs
sysctl_chk kernel.sched_min_granularity_ns 10000000 eq sched_gran
sysctl_chk kernel.sched_wakeup_granularity_ns 15000000 eq sched_wakeup
# NUMA auto-balancing
sysctl_chk kernel.numa_balancing 0 eq numa_bal
# Optional VAS fragmentation guard (large hosts)
if sysctl -a 2>/dev/null | grep -q '^vm.max_map_count'; then
  sysctl_chk vm.max_map_count 1600000 ge max_map_count
fi

# -----------------------------------------------------------------------------
# Disk readahead
# -----------------------------------------------------------------------------
echo -e "\n--- Disk readahead (target 4096 KB) ---"
show_readahead() {
  local base="$1"
  local ra_kb=""
  if [ -r "/sys/block/$base/queue/read_ahead_kb" ]; then
    ra_kb="$(cat /sys/block/$base/queue/read_ahead_kb 2>/dev/null || echo "")"
  elif need_cmd blockdev; then
    local ra_sectors
    ra_sectors="$(blockdev --getra "/dev/$base" 2>/dev/null || echo "")" # sectors (512B)
    [[ -n "$ra_sectors" ]] && ra_kb=$(( ra_sectors / 2 ))
  fi
  echo "$ra_kb"
}

declare -A seen
for PTH in "$SQL_DATA_DIR" "$SQL_LOG_DIR"; do
  SRC="$(blk_for_path "$PTH")"
  [[ -z "$SRC" ]] && continue
  BASE="$(lsblk -no PKNAME "$SRC" 2>/dev/null || true)"
  [[ -z "$BASE" ]] && BASE="$(basename "$SRC")"
  BASE="${BASE#/dev/}"
  if [[ "$BASE" == dm-* || "$BASE" == md* || "$BASE" == mapper/* ]]; then
    for D in $(lsblk -ndo NAME,TYPE "$SRC" | awk '$2=="disk"{print $1}'); do
      seen["$D"]=1
    done
  else
    seen["$BASE"]=1
  fi
done

for base in "${!seen[@]}"; do
  ra="$(show_readahead "$base")"
  if [[ -n "$ra" && "$ra" -ge 4096 ]]; then
    pass "/dev/$base readahead=${ra} KB"; [[ $EXPLAIN_ALL -eq 1 ]] && explain readahead
  else
    warn "/dev/$base readahead=${ra:-unknown} KB (recommend 4096 KB)"; explain readahead
  fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "\n=== Analysis complete ==="
echo -e "For more details, visit: https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-performance-best-practices?view=sql-server-ver17"