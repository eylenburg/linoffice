#!/usr/bin/env bash

### This is a fork of Winapps (https://github.com/winapps-org/winapps/) with some things stripped out that are not required. Focus is only on connecting to a Windows VM running in a Podman container and mainly running (preconfigured) MS Office applications.

### 'WinApps' was renamed to 'LinOffice' to avoid conflicts and confusion if the normal WinApps is also installed.

### GLOBAL CONSTANTS ###
# ERROR CODES
readonly EC_MISSING_CONFIG=1
readonly EC_MISSING_FREERDP=2
readonly EC_FAIL_START=4
readonly EC_RESTART_TIMEOUT=9
readonly EC_UNKNOWN=11
readonly EC_NO_IP=12
readonly EC_UNSUPPORTED_APP=14
readonly EC_INVALID_FLAVOR=15

# PATHS
readonly SCRIPT_DIR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly APPDATA_PATH="${HOME}/.local/share/linoffice" # make sure this is the same as in the setup.sh
readonly LASTRUN_PATH="${APPDATA_PATH}/lastrun"
readonly SLEEP_DETECT_PATH="${APPDATA_PATH}/last_activity"
readonly SLEEP_MARKER="${APPDATA_PATH}/sleep_marker"
readonly LOG_PATH="${APPDATA_PATH}/linoffice.log"
readonly CONFIG_PATH="$(realpath "${SCRIPT_DIR_PATH}/config/linoffice.conf")"
readonly COMPOSE_PATH="$(realpath "${SCRIPT_DIR_PATH}/config/compose.yaml")"

# MULTI-INSTANCE COORDINATION - NEW
readonly INSTANCE_ID="${RANDOM}_$$"
readonly INSTANCES_DIR="${APPDATA_PATH}/instances"
readonly INSTANCE_FILE="${INSTANCES_DIR}/${INSTANCE_ID}"
readonly MASTER_LOCK="${APPDATA_PATH}/cleanup.lock"

# OTHER
readonly CONTAINER_NAME="LinOffice"
readonly RDP_IP="127.0.0.1"
readonly RDP_PORT="3388"
readonly RUNID="${RANDOM}"
readonly WAFLAVOR="podman"
readonly COMPOSE_COMMAND="podman-compose"

### GLOBAL VARIABLES ###
# WINAPPS CONFIGURATION FILE
RDP_USER="MyWindowsUser"
RDP_PASS="MyWindowsPassword"
RDP_FLAGS=""
RDP_KBD=""
FREERDP_COMMAND=""
REMOVABLE_MEDIA=""
RDP_SCALE=100
AUTOPAUSE="on"
AUTOPAUSE_TIME="300"
DEBUG="true"
CLEANUP_TIME_WINDOW=86400  # Default: 24 hours. Do not delete Office lock files older than 24 hours, to avoid deleting pre-existing files.

# OTHER
FREERDP_PID=-1
NEEDED_BOOT=false
IS_OFFICE_WXP_APP=false  
SCRIPT_START_TIME=0      

### TRAPS ###
# Catch SIGINT (CTRL+C) to call 'waCleanUp'.
trap waCleanupInstance SIGINT SIGTERM SIGHUP EXIT

### FUNCTIONS ###

# Name: 'waThrowExit'
# Role: Throw an error message and exit the script.
waThrowExit() {
    # Declare variables.
    local ERR_CODE="$1"

    # Throw error.
    case "$ERR_CODE" in
    "$EC_MISSING_CONFIG")
        # Missing LinOffice configuration file.
        dprint "ERROR: MISSING LINOFFICE CONFIGURATION FILE. EXITING."
        echo -e "The LinOffice configuration file is missing.\nPlease create a LinOffice configuration file at '${CONFIG_PATH}'."
        ;;
    "$EC_MISSING_FREERDP")
        dprint "ERROR: FREERDP VERSION 3 IS NOT INSTALLED. EXITING."
        echo -e "FreeRDP version 3 is not installed."
        ;;
    "$EC_FAIL_START")
        dprint "ERROR: WINDOWS FAILED TO START. EXITING."
        echo -e "Windows failed to start."
        ;;
    "$EC_RESTART_TIMEOUT")
        dprint "ERROR: WINDOWS TOOK TOO LONG TO RESTART. EXITING."
        echo -e "Windows took too long to restart."
        ;;
    "$EC_UNKNOWN")
        dprint "ERROR: UNKNOWN CONTAINER ERROR. EXITING."
        echo -e "Unknown Windows container error."
        ;;
    "$EC_NO_IP")
        dprint "ERROR: WINDOWS UNREACHABLE. EXITING."
        echo -e "Windows is unreachable.\nPlease ensure Windows is assigned an IP address."
        ;;
    "$EC_UNSUPPORTED_APP")
        dprint "ERROR: APPLICATION NOT FOUND. EXITING."
        echo -e "Application not found.\nPlease ensure the program is correctly configured as an officially supported application."
        ;;
    "$EC_INVALID_FLAVOR")
        dprint "ERROR: INVALID FLAVOR. EXITING."
        echo -e "Invalid LinOffice flavor.\nPlease ensure 'docker', 'podman' or 'libvirt' are specified as the flavor in the LinOffice configuration file."
        ;;
    esac

    # Terminate the script.
    exit "$ERR_CODE"
}

# Name: 'dprint'
# Role: Conditionally print debug messages to a log file, creating it if it does not exist.
function dprint() {
    [ "$DEBUG" = "true" ] && echo "[$(date)-$RUNID] $1" >>"$LOG_PATH"
}
# Name: 'waFixRemovableMedia'
# Role: If user left REMOVABLE_MEDIA config null,fallback to /run/media for udisks defaults ,warning.
function waFixRemovableMedia() {
    if [ -z "$REMOVABLE_MEDIA" ]; then
        REMOVABLE_MEDIA="/run/media"  # Default for udisks
        dprint "NOTICE: Using default REMOVABLE_MEDIA: $REMOVABLE_MEDIA"
        echo -e "Using default removable media path: $REMOVABLE_MEDIA"
    fi
}

# Name: 'waAcquireLock'
# Role: Acquire lock with timeout, used for Office lock file cleanup
waAcquireLock() {
    local lock_file="$1"
    local timeout="${2:-5}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            return 0
        fi
        
        # Check if lock holder is still alive
        if [ -f "$lock_file" ]; then
            local lock_pid=$(cat "$lock_file" 2>/dev/null)
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                # Stale lock, remove it
                rm -f "$lock_file" 2>/dev/null
                continue
            fi
        fi
        
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    return 1
}

# Name: 'waReleaseLock'
# Role: Release previously acquired lock, used for Office lock file cleanup
waReleaseLock() {
    local lock_file="$1"
    local lock_pid=$(cat "$lock_file" 2>/dev/null)
    
    # Only remove if we own the lock
    if [ "$lock_pid" = "$$" ]; then
        rm -f "$lock_file" 2>/dev/null
    fi
}

# Name: 'waRegisterInstance'
# Role: Register this script instance, used for Office lock file cleanup
waRegisterInstance() {
    mkdir -p "$INSTANCES_DIR"
    
    # Create instance file with metadata
    cat > "$INSTANCE_FILE" << EOF
PID=$$
START_TIME=$SCRIPT_START_TIME
SCRIPT_ARGS=$*
OFFICE_APP=$IS_OFFICE_WXP_APP
FREERDP_PID=$FREERDP_PID
EOF
    
    dprint "REGISTERED INSTANCE: $INSTANCE_ID"
}

# Name: 'waUnregisterInstance'
# Role: Unregister this script instance, used for Office lock file cleanup
waUnregisterInstance() {
    rm -f "$INSTANCE_FILE" 2>/dev/null
    dprint "UNREGISTERED INSTANCE: $INSTANCE_ID"
}

# Name: 'waCheckMasterCleanup'
# Role: Check if master cleanup should run, used for Office lock file cleanup
waCheckMasterCleanup() {
    local force_cleanup="$1"
    
    if waAcquireLock "$MASTER_LOCK" 10; then
        dprint "ACQUIRED MASTER CLEANUP LOCK"
        
        local active_instances=0
        local office_instances=0
        
        if [ -d "$INSTANCES_DIR" ]; then
            for instance_file in "$INSTANCES_DIR"/*; do
                [ -f "$instance_file" ] || continue
                local instance_pid=$(grep "^PID=" "$instance_file" 2>/dev/null | cut -d= -f2)
                if [ -n "$instance_pid" ] && kill -0 "$instance_pid" 2>/dev/null; then
                    active_instances=$((active_instances + 1))
                    if grep -q "^OFFICE_APP=true" "$instance_file" 2>/dev/null; then
                        office_instances=$((office_instances + 1))
                    fi
                else
                    rm -f "$instance_file" 2>/dev/null
                fi
            done
        fi
        
        dprint "ACTIVE INSTANCES: $active_instances, OFFICE INSTANCES: $office_instances"
        
        # Run master cleanup if no active instances or forced (but only office cleanup if forced)
        if [ "$active_instances" -eq 0 ] || [ "$force_cleanup" = "true" ]; then
            if [ "$force_cleanup" = "true" ]; then
                dprint "FORCED CLEANUP REQUESTED"
                waMasterCleanup "$office_instances" "$force_cleanup"
            else
                waMasterCleanup "$office_instances" "false"
            fi
        fi
        
        waReleaseLock "$MASTER_LOCK"
    else
        dprint "COULD NOT ACQUIRE MASTER CLEANUP LOCK - ANOTHER INSTANCE CLEANING UP"
    fi
}

# Name: 'waMasterCleanup'
# Role: Master cleanup (runs only when needed), used for Office lock file cleanup
waMasterCleanup() {
    local office_instances="$1"
    local force_cleanup="$2"
    
    dprint "RUNNING MASTER CLEANUP (Force: $force_cleanup)"
    
    rm -f "${APPDATA_PATH}"/FreeRDP_Process_*.cproc 2>/dev/null
    
    if [ "$office_instances" -gt 0 ] || [ "$force_cleanup" = "true" ]; then
        dprint "RUNNING OFFICE CLEANUP"
        if [ "$force_cleanup" = "true" ]; then
            waOfficeCleanup 0  # No time restriction for full cleanup
        else
            waOfficeCleanup
        fi
    fi
    
    rmdir "$INSTANCES_DIR" 2>/dev/null
    
    dprint "MASTER CLEANUP COMPLETED"
}

# Name: 'waOfficeCleanup'
# Role: Office cleanup function, used for Office lock file cleanup
waOfficeCleanup() {
    local current_time=$(date +%s)
    local cleanup_start_time
    local LAST_CLEANUP_FILE="${APPDATA_PATH}/last_cleanup"

    if [ "$CLEANUP_TIME_WINDOW" = "unlimited" ]; then
        cleanup_start_time=0  # No time restriction
    elif [ -n "$CLEANUP_TIME_WINDOW" ]; then
        cleanup_start_time=$((current_time - CLEANUP_TIME_WINDOW))
    else
        cleanup_start_time=$(stat -t -c %Y "$LAST_CLEANUP_FILE" 2>/dev/null || echo $SCRIPT_START_TIME)
    fi
    
    dprint "OFFICE CLEANUP STARTED (Using cleanup_start_time: $cleanup_start_time)"
    
    local trash_cmd=""
    if command -v gio &> /dev/null; then
        trash_cmd="gio trash"
    elif command -v trash-put &> /dev/null; then
        trash_cmd="trash-put"
    else
        trash_cmd="rm"
        dprint "WARNING: No trash command found, files will be deleted permanently"
    fi
    
    local files_cleaned=0
    local files_skipped=0
    local find_paths=(~)
    [ -n "$REMOVABLE_MEDIA" ] && [ -d "$REMOVABLE_MEDIA" ] && find_paths+=("$REMOVABLE_MEDIA")
    while IFS= read -r -d '' lockfile; do
        local file_mtime=$(stat -c %Y "$lockfile" 2>/dev/null)
        if [ -n "$file_mtime" ]; then
            if [ "$cleanup_start_time" -eq 0 ] || [ "$file_mtime" -ge "$cleanup_start_time" ]; then
                dprint "CLEANING OFFICE FILE: $lockfile"
                if [ "$trash_cmd" = "rm" ]; then
                    rm "$lockfile" 2>/dev/null
                else
                    $trash_cmd "$lockfile" 2>/dev/null || rm "$lockfile" 2>/dev/null
                fi
                files_cleaned=$((files_cleaned + 1))
            else
                dprint "SKIPPING OLD OFFICE FILE: $lockfile (mtime: $file_mtime < $cleanup_start_time)"
                files_skipped=$((files_skipped + 1))
            fi
        fi
    done < <(find "${find_paths[@]}" -type f \( -name '~$*.xlsx' -o -name '~$*.docx' -o -name '~$*.pptx' -o -name '~$*.xlsm' -o -name '~$*.docm' -o -name '~$*.pptm' \) -not -path '*/.*' -print0 2>/dev/null)
    
    dprint "OFFICE CLEANUP COMPLETED - $files_cleaned files cleaned, $files_skipped files skipped"
    echo -e "Office cleanup completed: $files_cleaned files cleaned, $files_skipped files skipped"

    # Update last cleanup timestamp
    touch "$LAST_CLEANUP_FILE"
    dprint "UPDATED LAST CLEANUP TIMESTAMP: $LAST_CLEANUP_FILE"
}

# Name: 'waWaitForAllProcesses'
# Role: Wait function with coordination between multiple Winoffice processes, used for Office lock file cleanup
waWaitForAllProcesses() {
    local max_wait_time=30
    local wait_elapsed=0
    local check_interval=2
    
    dprint "WAITING FOR ALL FREERDP PROCESSES TO CLOSE"
    
    # First, try to find and kill any remaining FreeRDP processes
    for proc_file in "${APPDATA_PATH}"/FreeRDP_Process_*.cproc; do
        [ -f "$proc_file" ] || continue
        local pid="$(basename "$proc_file" | sed 's/FreeRDP_Process_\(.*\)\.cproc/\1/')"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            dprint "Found lingering FreeRDP process $pid, attempting to kill"
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                dprint "Process $pid still running, force killing"
                kill -KILL "$pid" 2>/dev/null
            fi
        fi
        rm -f "$proc_file" 2>/dev/null
    done 2>/dev/null
    
    # Then wait for any remaining processes to finish
    while ls "${APPDATA_PATH}"/FreeRDP_Process_*.cproc &>/dev/null; do
        if [ $wait_elapsed -ge $max_wait_time ]; then
            dprint "TIMEOUT WAITING FOR PROCESSES - FORCING CLEANUP"
            # Force remove any remaining process files
            rm -f "${APPDATA_PATH}"/FreeRDP_Process_*.cproc 2>/dev/null
            break
        fi
        
        sleep $check_interval
        wait_elapsed=$((wait_elapsed + check_interval))
        dprint "Still waiting for processes to close... ($wait_elapsed seconds elapsed)"
    done
    
    dprint "PROCESS CLEANUP COMPLETED"
    
    # Run cleanup after all processes are handled
    waCheckMasterCleanup "true"
}

# Name: 'waCleanupInstance'
# Role: Cleanup this script instance
waCleanupInstance() {
    dprint "CLEANUP INSTANCE: $INSTANCE_ID"
    
    # Unregister this instance
    waUnregisterInstance
    
    # Check if master cleanup should run
    waCheckMasterCleanup "false"
}

# Name: 'waLastRun'
# Role: Determine the last time this script was run.
waLastRun() {
    # Declare variables.
    local LAST_RUN_UNIX_TIME=0
    local CURR_RUN_UNIX_TIME=0

    # Store the time this script was run last as a unix timestamp.
    if [ -f "$LASTRUN_PATH" ]; then
        LAST_RUN_UNIX_TIME=$(stat -t -c %Y "$LASTRUN_PATH")
        dprint "LAST_RUN: ${LAST_RUN_UNIX_TIME}"
    fi

    # Update the file modification time with the current time.
    touch "$LASTRUN_PATH"
    CURR_RUN_UNIX_TIME=$(stat -t -c %Y "$LASTRUN_PATH")
    dprint "THIS_RUN: ${CURR_RUN_UNIX_TIME}"
}

# Name: 'waResetSystem'
# Role: Reset the system by killing all FreeRDP processes, running cleanup, and rebooting the Windows VM
waResetSystem() {
    dprint "STARTING SYSTEM RESET"
    
    # 1. Kill all FreeRDP processes
    dprint "KILLING ALL FREERDP PROCESSES"
    for proc_file in "${APPDATA_PATH}"/FreeRDP_Process_*.cproc; do
        [ -f "$proc_file" ] || continue
        local pid="$(basename "$proc_file" | sed 's/FreeRDP_Process_\(.*\)\.cproc/\1/')"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            dprint "Terminating FreeRDP process $pid"
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                dprint "Force killing FreeRDP process $pid"
                kill -KILL "$pid" 2>/dev/null
            fi
        fi
        rm -f "$proc_file" 2>/dev/null
    done
    
    # 2. Run cleanup
    dprint "RUNNING FULL CLEANUP"
    waCheckMasterCleanup "true"
    
    # 3. Reboot Windows VM
    dprint "REBOOTING WINDOWS VM"
    echo -e "Rebooting Windows VM..."
    "$COMPOSE_COMMAND" --file "$COMPOSE_PATH" restart &>/dev/null
    
    # Wait for container to restart
    local max_wait_time=120
    local wait_elapsed=0
    local check_interval=5
    
    dprint "WAITING FOR WINDOWS VM TO RESTART..."
    while (( wait_elapsed < max_wait_time )); do
        if [[ $("$WAFLAVOR" inspect --format='{{.State.Status}}' "$CONTAINER_NAME") == "running" ]]; then
            if timeout 1 bash -c ">/dev/tcp/$RDP_IP/$RDP_PORT" 2>/dev/null; then
                dprint "WINDOWS VM RESTARTED SUCCESSFULLY"
                echo -e "Windows VM restarted successfully."
                break
            fi
        fi
        sleep $check_interval
        wait_elapsed=$((wait_elapsed + check_interval))
        if (( wait_elapsed % 30 == 0 )); then
            echo -e "Still waiting for Windows VM to restart... ($((wait_elapsed/60)) minutes elapsed)"
        fi
    done
    
    if (( wait_elapsed >= max_wait_time )); then
        dprint "TIMEOUT WAITING FOR WINDOWS VM TO RESTART"
        echo -e "Timeout waiting for Windows VM to restart. Please check the container status."
        waThrowExit $EC_FAIL_START
    fi
    
    dprint "SYSTEM RESET COMPLETED"
}

# Name: 'waFixScale'
# Role: Since FreeRDP only supports '/scale' values of 100, 140 or 180, find the closest supported argument to the user's configuration.
function waFixScale() {
    # Define variables.
    local OLD_SCALE=100
    local VALID_SCALE_1=100
    local VALID_SCALE_2=140
    local VALID_SCALE_3=180

    # Check for an unsupported value.
    if [ "$RDP_SCALE" != "$VALID_SCALE_1" ] && [ "$RDP_SCALE" != "$VALID_SCALE_2" ] && [ "$RDP_SCALE" != "$VALID_SCALE_3" ]; then
        # Save the unsupported scale.
        OLD_SCALE="$RDP_SCALE"

        # Calculate the absolute differences.
        local DIFF_1=$(( RDP_SCALE > VALID_SCALE_1 ? RDP_SCALE - VALID_SCALE_1 : VALID_SCALE_1 - RDP_SCALE ))
        local DIFF_2=$(( RDP_SCALE > VALID_SCALE_2 ? RDP_SCALE - VALID_SCALE_2 : VALID_SCALE_2 - RDP_SCALE ))
        local DIFF_3=$(( RDP_SCALE > VALID_SCALE_3 ? RDP_SCALE - VALID_SCALE_3 : VALID_SCALE_3 - RDP_SCALE ))

        # Set the final scale to the valid scale value with the smallest absolute difference.
        if (( DIFF_1 <= DIFF_2 && DIFF_1 <= DIFF_3 )); then
            RDP_SCALE="$VALID_SCALE_1"
        elif (( DIFF_2 <= DIFF_1 && DIFF_2 <= DIFF_3 )); then
            RDP_SCALE="$VALID_SCALE_2"
        else
            RDP_SCALE="$VALID_SCALE_3"
        fi

        # Print feedback.
        dprint "WARNING: Unsupported RDP_SCALE value '${OLD_SCALE}'. Defaulting to '${RDP_SCALE}'."
        echo -e "Unsupported RDP_SCALE value '${OLD_SCALE}'.\nDefaulting to '${RDP_SCALE}'."
    fi
}

# Name: 'waLoadConfig'
# Role: Load the variables within the LinOffice configuration file.
function waLoadConfig() {
    # Load LinOffice configuration file.
    if [ -f "$CONFIG_PATH" ]; then
        source "$CONFIG_PATH"
    else
        waThrowExit $EC_MISSING_CONFIG
    fi

    # Update $RDP_SCALE.
    waFixScale
    # Update when $REMOVABLE_MEDIA is null
    waFixRemovableMedia
    # Update $AUTOPAUSE_TIME.
    # RemoteApp RDP sessions take, at minimum, 20 seconds to be terminated by the Windows server.
    # Hence, subtract 20 from the timeout specified by the user, as a 'built in' timeout of 20 seconds will occur.
    # Source: https://techcommunity.microsoft.com/t5/security-compliance-and-identity/terminal-services-remoteapp-8482-session-termination-logic/ba-p/246566
    AUTOPAUSE_TIME=$((AUTOPAUSE_TIME - 20))
    AUTOPAUSE_TIME=$((AUTOPAUSE_TIME < 0 ? 0 : AUTOPAUSE_TIME))
    # Validate CLEANUP_TIME_WINDOW
    if [[ ! "$CLEANUP_TIME_WINDOW" =~ ^[0-9]+$ ]] && [ "$CLEANUP_TIME_WINDOW" != "unlimited" ]; then
        dprint "WARNING: Invalid CLEANUP_TIME_WINDOW '$CLEANUP_TIME_WINDOW'. Defaulting to 24 hours = 86400 seconds."
        CLEANUP_TIME_WINDOW=86400 # 24 hours
    fi
}

# Name: 'waGetFreeRDPCommand'
# Role: Determine the correct FreeRDP command to use.
function waGetFreeRDPCommand() {
    # Declare variables.
    local FREERDP_MAJOR_VERSION="" # Stores the major version of the installed copy of FreeRDP.

    # Attempt to set a FreeRDP command if the command variable is empty.
    if [ -z "$FREERDP_COMMAND" ]; then
        # Check for 'xfreerdp'.
        if command -v xfreerdp &>/dev/null; then
            # Check FreeRDP major version is 3 or greater.
            FREERDP_MAJOR_VERSION=$(xfreerdp --version | head -n 1 | grep -o -m 1 '\b[0-9]\S*' | head -n 1 | cut -d'.' -f1)
            if [[ $FREERDP_MAJOR_VERSION =~ ^[0-9]+$ ]] && ((FREERDP_MAJOR_VERSION >= 3)); then
                FREERDP_COMMAND="xfreerdp"
            fi
        fi

        # Check for 'xfreerdp3' command as a fallback option.
        if [ -z "$FREERDP_COMMAND" ]; then
            if command -v xfreerdp3 &>/dev/null; then
                # Check FreeRDP major version is 3 or greater.
                FREERDP_MAJOR_VERSION=$(xfreerdp3 --version | head -n 1 | grep -o -m 1 '\b[0-9]\S*' | head -n 1 | cut -d'.' -f1)
                if [[ $FREERDP_MAJOR_VERSION =~ ^[0-9]+$ ]] && ((FREERDP_MAJOR_VERSION >= 3)); then
                    FREERDP_COMMAND="xfreerdp3"
                fi
            fi
        fi

        # Check for FreeRDP Flatpak (fallback option).
        if [ -z "$FREERDP_COMMAND" ]; then
            if command -v flatpak &>/dev/null; then
                if flatpak list --columns=application | grep -q "^com.freerdp.FreeRDP$"; then
                    # Check FreeRDP major version is 3 or greater.
                    FREERDP_MAJOR_VERSION=$(flatpak list --columns=application,version | grep "^com.freerdp.FreeRDP" | awk '{print $2}' | cut -d'.' -f1)
                    if [[ $FREERDP_MAJOR_VERSION =~ ^[0-9]+$ ]] && ((FREERDP_MAJOR_VERSION >= 3)); then
                        FREERDP_COMMAND="flatpak run --command=xfreerdp com.freerdp.FreeRDP"
                    fi
                fi
            fi
        fi
    fi

    if command -v "$FREERDP_COMMAND" &>/dev/null || [ "$FREERDP_COMMAND" = "flatpak run --command=xfreerdp com.freerdp.FreeRDP" ]; then
        dprint "Using FreeRDP command '${FREERDP_COMMAND}'."

    else
        waThrowExit "$EC_MISSING_FREERDP"
    fi
}

# Name: 'waCheckContainerRunning'
# Role: Throw an error if the Docker container is not running.
function waCheckContainerRunning() {
    # Declare variables.
    local EXIT_STATUS=0
    local CONTAINER_STATE=""
    local TIME_ELAPSED=0
    local TIME_LIMIT=60
    local TIME_INTERVAL=5
    local MAX_WAIT_TIME=120  # Maximum time to wait for container to be ready

    # Determine the state of the container.
    CONTAINER_STATE=$("$WAFLAVOR" inspect --format='{{.State.Status}}' "$CONTAINER_NAME")

    # Check container state.
    # Note: Errors DO NOT result in non-zero exit statuses.
    # Docker: 'created', 'restarting', 'running', 'removing', 'paused', 'exited' or 'dead'.
    # Podman: 'created', 'running', 'paused', 'exited' or 'unknown'.
    case "$CONTAINER_STATE" in
        "created")
            dprint "WINDOWS CREATED. BOOTING WINDOWS."
            echo -e "Booting Windows."
            $COMPOSE_COMMAND --file "$COMPOSE_PATH" start &>/dev/null
            NEEDED_BOOT=true
            ;;
        "restarting")
            dprint "WINDOWS RESTARTING. WAITING."
            echo -e "Windows is currently restarting. Please wait."
            EXIT_STATUS=$EC_RESTART_TIMEOUT
            while (( TIME_ELAPSED < TIME_LIMIT )); do
                if [[ $("$WAFLAVOR" inspect --format='{{.State.Status}}' "$CONTAINER_NAME") == "running" ]]; then
                    EXIT_STATUS=0
                    dprint "WINDOWS RESTARTED."
                    echo -e "Restarted Windows."
                    NEEDED_BOOT=true
                    break
                fi
                sleep $TIME_INTERVAL
                TIME_ELAPSED=$((TIME_ELAPSED + TIME_INTERVAL))
            done
            ;;
        "paused")
            dprint "WINDOWS PAUSED. RESUMING WINDOWS."
            echo -e "Resuming Windows."
            $COMPOSE_COMMAND --file "$COMPOSE_PATH" unpause &>/dev/null
            ;;
        "exited")
            dprint "WINDOWS SHUT OFF. BOOTING WINDOWS."
            echo -e "Booting Windows."
            $COMPOSE_COMMAND --file "$COMPOSE_PATH" start &>/dev/null
            NEEDED_BOOT=true
            ;;
        "dead")
            dprint "WINDOWS DEAD. RECREATING WINDOWS CONTAINER."
            echo -e "Re-creating and booting Windows."
            $COMPOSE_COMMAND --file "$COMPOSE_PATH" down &>/dev/null && $COMPOSE_COMMAND --file "$COMPOSE_PATH" up -d &>/dev/null
            NEEDED_BOOT=true
            ;;
        "unknown")
            EXIT_STATUS=$EC_UNKNOWN
            ;;
    esac

    # Handle non-zero exit statuses.
    [ "$EXIT_STATUS" -ne 0 ] && waThrowExit "$EXIT_STATUS"

    # Wait for container to be fully ready
    if [[ "$CONTAINER_STATE" == "created" || "$CONTAINER_STATE" == "exited" || "$CONTAINER_STATE" == "dead" || "$CONTAINER_STATE" == "restarting" ]]; then
        dprint "WAITING FOR CONTAINER TO BE FULLY READY..."
        echo -e "Waiting for Windows to be ready..."

        TIME_ELAPSED=0
        
        while (( TIME_ELAPSED < MAX_WAIT_TIME )); do
            # Check if container is running
            if [[ $("$WAFLAVOR" inspect --format='{{.State.Status}}' "$CONTAINER_NAME") == "running" ]]; then
                # Try to connect to RDP port to verify it's ready
                if timeout 1 bash -c ">/dev/tcp/$RDP_IP/$RDP_PORT" 2>/dev/null; then
                    dprint "CONTAINER IS READY"
                    echo -e "Windows is ready."
                    # Add a delay after Windows is ready
                    if [ "$NEEDED_BOOT" = "true" ]; then
                        echo -e "Waiting for Windows services to initialize..."
                        sleep 10
                    fi
                    break
                fi
            fi
            
            sleep 5
            TIME_ELAPSED=$((TIME_ELAPSED + 5))
            
            # Show progress every 30 seconds
            if (( TIME_ELAPSED % 30 == 0 )); then
                echo -e "Still waiting for Windows to be ready... ($TIME_ELAPSED seconds elapsed)"
            fi
        done
        
        # If we timed out waiting for the container
        if (( TIME_ELAPSED >= MAX_WAIT_TIME )); then
            dprint "TIMEOUT WAITING FOR CONTAINER TO BE READY"
            echo -e "Timeout waiting for Windows to be ready. Please try again."
            waThrowExit $EC_FAIL_START
        fi
    fi
}

# Name: 'waTimeSync'  
# Role: Detect if system went to sleep by comparing uptime progression, then sync time in Windows VM
function waTimeSync() {
    local CURRENT_TIME=$(date +%s)
    local CURRENT_UPTIME="$(awk '{print int($1)}' "/proc/uptime")"
    local STORED_TIME=0
    local STORED_UPTIME=0
    local EXPECTED_UPTIME=0
    local UPTIME_DIFF=0
    
    # Read stored values if file exists
    if [ -f "$SLEEP_DETECT_PATH" ]; then
        STORED_TIME=$(head -n1 "$SLEEP_DETECT_PATH" 2>/dev/null || echo 0)
        STORED_UPTIME=$(tail -n1 "$SLEEP_DETECT_PATH" 2>/dev/null || echo 0)
    fi
    
    if [ "$STORED_TIME" -gt 0 ] && [ "$STORED_UPTIME" -gt 0 ]; then
        # Calculate what uptime should be now
        EXPECTED_UPTIME=$((STORED_UPTIME + CURRENT_TIME - STORED_TIME))
        UPTIME_DIFF=$((EXPECTED_UPTIME - CURRENT_UPTIME))
        
        dprint "UPTIME_DIFF: ${UPTIME_DIFF} seconds"
        
        # If uptime is significantly less than expected, system likely slept
        if [[ "$UPTIME_DIFF" -gt 30 && ! -f "$SLEEP_MARKER" ]]; then
            dprint "DETECTED SLEEP/WAKE CYCLE (uptime gap: ${UPTIME_DIFF}s). CREATING SLEEP MARKER TO SYNC WINDOWS TIME."
            echo -e "Detected system sleep/wake cycle. Creating sleep marker to sync Windows time..."
            
            # Create sleep marker which will be monitored by Windows VM to trigger time sync
            touch "$SLEEP_MARKER"
            
            dprint "CREATED SLEEP MARKER"
        fi
    fi
    
    # Store current values
    {
        echo "$CURRENT_TIME"
        echo "$CURRENT_UPTIME"
    } > "$SLEEP_DETECT_PATH"
}

# Name: 'waRunCommand'
# Role: Run the requested LinOffice command.
function waRunCommand() {
    # Declare variables.
    local ICON=""
    local FILE_PATH=""
    local FILE_DIR="" # Store the directory of the opened file
    declare -a FILE_DIRS=() # Array to store multiple directories

    # Run option.
    if [ -z "$1" ]; then
        printf "Possible commands:\n"
        printf "\033[1m./linoffice.sh [excel|word|powerpoint|onenote|outlook]\033[0m -> runs one of the predefined Office applications\n"
        printf "\033[1m./linoffice.sh manual [msaccess.exe|mspub.exe]\033[0m -> run Microsoft Access or Microsoft Publisher, if installed (they are not part of the default Office version installed by LinOffice)\n"
        printf "\033[1m./linoffice.sh manual [explorer.exe|regedit.exe|powershell.exe|cmd.exe]\033[0m -> runs a specific Windows app in the Windows PATH\n"
        printf "\033[1m./linoffice.sh manual \"C:\\\\Program Files\\\\Microsoft Office\\\\root\\\\Office16\\\\SETLANG.EXE\"\033[0m -> like above, but for any application (here: Microsoft Office Language Preferences tool)\n"
        printf "\033[1m./linoffice.sh windows\033[0m -> shows the whole Windows desktop in an RDP session\n"
        printf "\033[1m./linoffice.sh update\033[0m -> runs an update script for Windows in Powershell\n"
        printf "\033[1m./linoffice.sh reset\033[0m -> kills all FreeRDP processes, cleans up Office lock files, and reboots the Windows VM\n"
        printf "\033[1m./linoffice.sh cleanup [--full|--reset]\033[0m -> cleans up Office lock files (such as ~\$file.xlsx) in the home folder and removable media; --full cleans all files regardless of creation date, --reset resets the last cleanup timestamp\n"
        printf "\033[1m./linoffice.sh --startcontainer\033[0m -> will start the Windows container if it is not running and not execute anything else\n"
        printf "\033[1m./linoffice.sh --stopcontainer\033[0m -> shuts down the Windows container completely\n"
        exit 0
    fi

    if [ "$1" = "cleanup" ]; then
        dprint "CLEANUP COMMAND"
        if [ "$2" = "--full" ]; then
            dprint "FULL CLEANUP REQUESTED"
            waCheckMasterCleanup "true"
        elif [ "$2" = "--reset" ]; then
            dprint "RESETTING LAST CLEANUP TIMESTAMP"
            rm -f "${APPDATA_PATH}/last_cleanup" 2>/dev/null
            touch "${APPDATA_PATH}/last_cleanup"
            dprint "CREATED NEW LAST CLEANUP TIMESTAMP: ${APPDATA_PATH}/last_cleanup"
            waCheckMasterCleanup "false"
        else
            dprint "STANDARD CLEANUP REQUESTED"
            waCheckMasterCleanup "false"
        fi
        exit 0

    elif [ "$1" = "reset" ]; then
        dprint "SYSTEM RESET REQUESTED"
        waResetSystem
        exit 0

    elif [ "$1" = "windows" ]; then
        # Update timeout (since there is no 'in-built' 20 second delay for full RDP sessions post-logout).
        AUTOPAUSE_TIME=$((AUTOPAUSE_TIME + 20))

        # Open Windows RDP session.
        dprint "WINDOWS"
        podman unshare --rootless-netns "$FREERDP_COMMAND" \
            /u:$RDP_USER \
            /p:$RDP_PASS \
            /scale:$RDP_SCALE \
            +dynamic-resolution \
            +auto-reconnect \
            +home-drive \
            +clipboard \
            -wallpaper \
            $RDP_KBD \
            /wm-class:"Microsoft Windows" \
            /t:"Windows RDP Session [$RDP_IP]" \
            $RDP_FLAGS \
            /v:"$RDP_IP:$RDP_PORT" &>/dev/null &

        # Capture the process ID.
        FREERDP_PID=$!

    elif [ "$1" = "manual" ]; then
        # Open specified application.
        dprint "MANUAL: ${2}"
        podman unshare --rootless-netns "$FREERDP_COMMAND" \
            /u:$RDP_USER \
            /p:$RDP_PASS \
            /scale:$RDP_SCALE \
            +auto-reconnect \
            +home-drive \
            +clipboard \
            -wallpaper \
            $RDP_KBD \
            $RDP_FLAGS \
            /app:program:"$2" \
            /v:"$RDP_IP:$RDP_PORT" &>/dev/null &

        # Capture the process ID.
        FREERDP_PID=$!   

    elif [ "$1" = "update" ]; then
        # Run the script
        dprint "UPDATE"
        podman unshare --rootless-netns "$FREERDP_COMMAND" \
            /u:$RDP_USER \
            /p:$RDP_PASS \
            /scale:$RDP_SCALE \
            +auto-reconnect \
            +home-drive \
            +clipboard \
            -wallpaper \
            $RDP_KBD \
            $RDP_FLAGS \
            /app:program:powershell.exe,cmd:'-ExecutionPolicy Bypass -File C:\\OEM\\UpdateWindows.ps1' \
            /v:"$RDP_IP:$RDP_PORT" &>/dev/null &
    
        # Capture the process ID.
        FREERDP_PID=$!  

    # This function is not meant to be used by the user. It executes a script to update the registry for international settings if the settings have been changed in the LinOffice GUI
    elif [ "$1" = "registry_override" ]; then
        # Run the script
        dprint "UPDATE"
        podman unshare --rootless-netns "$FREERDP_COMMAND" \
            /u:$RDP_USER \
            /p:$RDP_PASS \
            /scale:$RDP_SCALE \
            +auto-reconnect \
            +home-drive \
            +clipboard \
            -wallpaper \
            $RDP_KBD \
            $RDP_FLAGS \
            /app:program:powershell.exe,cmd:'-ExecutionPolicy Bypass -File C:\\OEM\\RegistryOverride.ps1' \
            /v:"$RDP_IP:$RDP_PORT" &>/dev/null &
    
        # Capture the process ID.
        FREERDP_PID=$!  

    # This function is not meant to be used by the user. It executes a script to turn of Internet in the VM (via invalid DNS) if the settings have been changed in the LinOffice GUI
    elif [ "$1" = "internet_off" ]; then
        # Run the script
        dprint "UPDATE"
        podman unshare --rootless-netns "$FREERDP_COMMAND" \
            /u:$RDP_USER \
            /p:$RDP_PASS \
            /scale:$RDP_SCALE \
            +auto-reconnect \
            +home-drive \
            +clipboard \
            -wallpaper \
            $RDP_KBD \
            $RDP_FLAGS \
            /app:program:cmd.exe,cmd:'/c C:\\OEM\\dns_off.bat' \
            /v:"$RDP_IP:$RDP_PORT" &>/dev/null &
    
        # Capture the process ID.
        FREERDP_PID=$!  

    # This function is not meant to be used by the user. It executes a script to re-enable automatic DNS if the settings have been changed in the LinOffice GUI
    elif [ "$1" = "internet_on" ]; then
        # Run the script
        dprint "UPDATE"
        podman unshare --rootless-netns "$FREERDP_COMMAND" \
            /u:$RDP_USER \
            /p:$RDP_PASS \
            /scale:$RDP_SCALE \
            +auto-reconnect \
            +home-drive \
            +clipboard \
            -wallpaper \
            $RDP_KBD \
            $RDP_FLAGS \
            /app:program:cmd.exe,cmd:'/c C:\\OEM\\dns_on.bat' \
            /v:"$RDP_IP:$RDP_PORT" &>/dev/null &
    
        # Capture the process ID.
        FREERDP_PID=$!  

    else
        # Script summoned from right-click menu or application icon (plus/minus a file path).
        if [ -e "${SCRIPT_DIR_PATH}/apps/${1}/info.txt" ]; then
            source "${SCRIPT_DIR_PATH}/apps/${1}/info.txt"
            ICON="${SCRIPT_DIR_PATH}/apps/${1}/icon.svg"
        elif [ -e "${APPDATA_PATH}/apps/${1}/info.txt" ]; then
            source "${APPDATA_PATH}/apps/${1}/info.txt"
            ICON="${APPDATA_PATH}/apps/${1}/icon.svg"
        else
            waThrowExit "$EC_UNSUPPORTED_APP"
        fi

        # Check if the application is Excel, Word, or PowerPoint
        case "$1" in
            "excel"|"word"|"powerpoint")
                IS_OFFICE_WXP_APP=true
                waRegisterInstance "$@"
                ;;
        esac

        # Check if a file path was specified, and pass this to the application.
        if [ -z "$2" ]; then
            # No file path specified.
            dprint "LAUNCHING OFFICE APP: $FULL_NAME"
            podman unshare --rootless-netns "$FREERDP_COMMAND" \
                /u:$RDP_USER \
                /p:$RDP_PASS \
                /scale:$RDP_SCALE \
                +auto-reconnect \
                +home-drive \
                +clipboard \
                -wallpaper \
                $RDP_KBD \
                $RDP_FLAGS \
                /wm-class:"$FULL_NAME" \
                /app:program:"$EXE",icon:"$ICON",name:"$FULL_NAME" \
                /v:"$RDP_IP:$RDP_PORT" &>/dev/null &

            # Capture the process ID.
            FREERDP_PID=$!
        else
            # Get the directory of the file
            FILE_DIR=$(dirname "$2")
            dprint "FILE_DIR: ${FILE_DIR}"    
            FILE_DIRS+=("$FILE_DIR") # Add directory to array

            # Convert path from UNIX to Windows style.
            FILE_PATH="$(echo "$2" | sed \
                -e 's|^'"${HOME}"'|\\\\tsclient\\home|' \
                -e 's|^\('"${REMOVABLE_MEDIA//|/\\|}"'\)/[^/]*|\\\\tsclient\\media|' \
                -e 's|/|\\|g')"
            dprint "UNIX_FILE_PATH: ${2}"
            dprint "WINDOWS_FILE_PATH: ${FILE_PATH}"

            dprint "LAUNCHING OFFICE APP WITH FILE: $FULL_NAME"
            podman unshare --rootless-netns "$FREERDP_COMMAND" \
                /u:$RDP_USER \
                /p:$RDP_PASS \
                /scale:$RDP_SCALE \
                +auto-reconnect \
                +home-drive \
                +clipboard \
                /drive:media,"$REMOVABLE_MEDIA" \
                -wallpaper \
                $RDP_KBD \
                $RDP_FLAGS \
                /wm-class:"$FULL_NAME" \
                /app:program:"$EXE",icon:"$ICON",name:"$FULL_NAME",cmd:\""$FILE_PATH"\" \
                /v:"$RDP_IP:$RDP_PORT" &>/dev/null &

            # Capture the process ID.
            FREERDP_PID=$!
        fi
    fi

    # Handle process cleanup (unified for all commands)
    if [ "$FREERDP_PID" -ne -1 ]; then
        # Create a file with the process ID and update instance file
        touch "${APPDATA_PATH}/FreeRDP_Process_${FREERDP_PID}.cproc"
        sed -i "s/^FREERDP_PID=.*/FREERDP_PID=$FREERDP_PID/" "$INSTANCE_FILE" 2>/dev/null

        # Wait for the process to start
        local start_timeout=30
        local start_elapsed=0
        local start_interval=1

        dprint "WAITING FOR FREERDP PROCESS TO START..."
        while [ $start_elapsed -lt $start_timeout ]; do
            if kill -0 "$FREERDP_PID" 2>/dev/null; then
                dprint "FREERDP PROCESS STARTED SUCCESSFULLY"
                break
            fi
            sleep $start_interval
            start_elapsed=$((start_elapsed + start_interval))
        done

        if [ $start_elapsed -ge $start_timeout ]; then
            dprint "FREERDP PROCESS FAILED TO START"
            echo -e "Failed to start application. Please try again."
            rm -f "${APPDATA_PATH}/FreeRDP_Process_${FREERDP_PID}.cproc" &>/dev/null
            exit 1
        fi

        # Wait for the process to terminate with timeout
        local wait_timeout=30
        local wait_elapsed=0
        local wait_interval=1

        while kill -0 "$FREERDP_PID" 2>/dev/null && [ $wait_elapsed -lt $wait_timeout ]; do
            sleep $wait_interval
            wait_elapsed=$((wait_elapsed + wait_interval))
        done

        # If process is still running after timeout, force kill it
        if kill -0 "$FREERDP_PID" 2>/dev/null; then
            dprint "FreeRDP process $FREERDP_PID still running after timeout, force killing"
            kill -TERM "$FREERDP_PID" 2>/dev/null
            sleep 2
            kill -KILL "$FREERDP_PID" 2>/dev/null
        fi

        # Remove the file with the process ID
        rm "${APPDATA_PATH}/FreeRDP_Process_${FREERDP_PID}.cproc" &>/dev/null

        # Run cleanup immediately after process termination
        waCheckMasterCleanup "true"
        
        # Exit the script
        exit 0
    fi
}

# Name: 'waCheckIdle'
# Role: Suspend Windows if idle.
function waCheckIdle() {
    # Declare variables
    local TIME_INTERVAL=10
    local TIME_ELAPSED=0
    local SUSPEND_WINDOWS=0

    # Check if there are no LinOffice-related FreeRDP processes running.
    if ! ls "$APPDATA_PATH"/FreeRDP_Process_*.cproc &>/dev/null; then
        SUSPEND_WINDOWS=1
        while (( TIME_ELAPSED < AUTOPAUSE_TIME )); do
            if ls "$APPDATA_PATH"/FreeRDP_Process_*.cproc &>/dev/null; then
                SUSPEND_WINDOWS=0
                break
            fi
            sleep $TIME_INTERVAL
            TIME_ELAPSED=$((TIME_ELAPSED + TIME_INTERVAL))
        done
    fi

    # Hibernate/Pause Windows.
    if [ "$SUSPEND_WINDOWS" -eq 1 ]; then
        dprint "IDLE FOR ${AUTOPAUSE_TIME} SECONDS. SUSPENDING WINDOWS."
        echo -e "Pausing Windows due to inactivity."
        "$COMPOSE_COMMAND" --file "$COMPOSE_PATH" pause &>/dev/null
    fi
}

### MAIN LOGIC ###

# Handle --stopcontainer command first and exit
if [[ "$1" == "--stopcontainer" ]]; then
    dprint "SHUTTING DOWN CONTAINER"
    echo "Attempting graceful shutdown of LinOffice container..."

    # Check the current status of the container
    CONTAINER_STATUS=$(podman inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)

    # If the container is paused, it must be un-paused first to shut down cleanly
    if [[ "$CONTAINER_STATUS" == "paused" ]]; then
        echo "Container is paused, unpausing to allow clean shutdown..."
        "$COMPOSE_COMMAND" --file "$COMPOSE_PATH" unpause &>/dev/null
        sleep 2 # Give it a moment to wake up before stopping
    fi

    # Now, if the container is running (or was just un-paused), stop it
    if [[ "$CONTAINER_STATUS" == "running" || "$CONTAINER_STATUS" == "paused" ]]; then
        echo "Sending stop command... (this may take up to 2 minutes)"
        # Use podman-compose stop, which respects the grace period in the yaml
        "$COMPOSE_COMMAND" --file "$COMPOSE_PATH" stop &>/dev/null
    else
        echo "Container is not running."
    fi

    echo "Cleaning up all resources..."
    # Finally, run 'down' to ensure the stopped container is fully removed.
    "$COMPOSE_COMMAND" --file "$COMPOSE_PATH" down --remove-orphans &>/dev/null

    echo "LinOffice has been shut down."
    exit 0
fi

dprint "START"
dprint "SCRIPT_DIR: ${SCRIPT_DIR_PATH}"
dprint "SCRIPT_ARGS: ${*}"
dprint "HOME_DIR: ${HOME}"
mkdir -p "$APPDATA_PATH"
SCRIPT_START_TIME=$(date +%s)
waLastRun
waLoadConfig
waGetFreeRDPCommand
waCheckContainerRunning

# Check if --startcontainer flag is present
START_CONTAINER=false
for arg in "$@"; do
    if [[ "$arg" == "--startcontainer" ]]; then
        START_CONTAINER=true
        break
    fi
done

# Skip waTimeSync and waRunCommand if --startcontainer is used
if [[ "$START_CONTAINER" != "true" ]]; then
    waTimeSync
    waRunCommand "$@"
fi

if [[ "$AUTOPAUSE" == "on" ]]; then
    waCheckIdle
fi

dprint "END"
