#!/bin/bash

#======
# FUNCTION fatal($MGS, $LOG)
# outputs message to stderr and exits, if LOG is set, also append message to logfile
#
# - MSG: message (optional)
# - LOG: logfile (optional)
#======
fatal() {
        local MSG=$1
        local LOG=$2

        if [ "$MSG" != "" ]; then
                echo "$MSG" 1>&2
                [ "$LOG" != "" ] && echo "$(date +'%Y-%m-%d %H:%M:%S') [$$] $MSG" >> "$LOG"
        fi
        exit 64
}

#======
# FUNCTION err($MGS, $LOG)
# outputs message to stderr
# if LOG is set, also append message to logfile
#
# - MSG: message
# - LOG: logfile
#======
err() {
        local MSG=$1
        local LOG=$2

        echo "$MSG" 1>&2
        [ "$LOG" != "" ] && echo "$(date +'%Y-%m-%d %H:%M:%S') [$$] $MSG" >> "$LOG"
}

#======
# FUNCTION msg($MGS, $LOG)
# outputs message to stdout
# if LOG is set, also append message to logfile
#
# - MSG: message
# - LOG: logfile
#======
msg() {
        local MSG=$1
        local LOG=$2

        echo "$MSG"
        [ "$LOG" != "" ] && echo "$(date +'%Y-%m-%d %H:%M:%S') [$$] $MSG" >> "$LOG"
}

#======
# FUNCTION log($MGS, $LOG)
# outputs message to stdout if interactive
# if LOG is set, also append message to logfile
#
# - MSG: message
# - LOG: logfile
#======
log() {
        local MSG=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG=$1; shift || fatal "${FUNCNAME} usage error"

        echo "$(date +'%Y-%m-%d %H:%M:%S') [$$] $MSG" >> "$LOG"
        return 0
}

#======
# FUNCTION log_noninteractive_to_file_and_mail($LOG, $MAIL_ON_ERROR_ONLY, $MAIL, $SUBJECT, $PURGE=0)
# outputs message to file & email if non-interactive
#
# - LOG: full logfile path
# - MAIL_ON_ERROR_ONLY: if "1", only send mail when an error happened
# - MAIL: email address
# - SUBJECT: subject text
# - PURGE: remove existing log files
#======
log_noninteractive_to_file_and_mail() {
        local LOG_NONINTERACTIVE_FILE=$1; shift || fatal "${FUNCNAME} usage error"
        local MAIL_ON_ERROR_ONLY=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG_NONINTERACTIVE_MAIL=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG_NONINTERACTIVE_SUBJECT=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG_NONINTERACTIVE_PURGE=$1; shift || LOG_NONINTERACTIVE_PURGE=0

        is_interactive && return 0

        # combined logfile (STDOUT & STDERR)
        mkdir -p "$(dirname $LOG_NONINTERACTIVE_FILE)"
        [ "$LOG_NONINTERACTIVE_PURGE" = "1" ] && \rm -f "$LOG_NONINTERACTIVE_FILE" &> /dev/null

        # error logfile (STDERR only)
        local LOG_NONINTERACTIVE_ERROR=`mktemp`

        # pipe to duplicate STERR to both $ERROR and $LOG
        local LOG_NONINTERACTIVE_PIPE=`mktemp -u`
        mkfifo $LOG_NONINTERACTIVE_PIPE

        # redirect outputs
        exec 5>>$LOG_NONINTERACTIVE_FILE
        /usr/bin/tee $LOG_NONINTERACTIVE_ERROR < $LOG_NONINTERACTIVE_PIPE >&5 &
        local LOG_NONINTERACTIVE_TEEPID=$!

        # remove files when exiting
        trap_add "finish_noninteractive_to_file_and_mail $LOG_NONINTERACTIVE_FILE $LOG_NONINTERACTIVE_ERROR $LOG_NONINTERACTIVE_PIPE $LOG_NONINTERACTIVE_TEEPID $LOG_NONINTERACTIVE_MAIL \"$LOG_NONINTERACTIVE_SUBJECT\" $MAIL_ON_ERROR_ONLY" EXIT

        exec 3>&1 4>&2
        exec 2>$LOG_NONINTERACTIVE_PIPE
        exec 1>&5
}

#======
# FUNCTION finish_noninteractive_to_file_and_mail(LOG_NONINTERACTIVE_FILE, LOG_NONINTERACTIVE_ERROR, LOG_NONINTERACTIVE_PIPE, LOG_NONINTERACTIVE_TEEPID, LOG_NONINTERACTIVE_MAIL, SUBJECT, MAIL_ON_ERROR_ONLY)
# outputs the full log to mail if an error happened
# - LOG_NONINTERACTIVE_FILE: main log filename
# - LOG_NONINTERACTIVE_ERROR: error log filename
# - LOG_NONINTERACTIVE_PIPE: error pipe
# - LOG_NONINTERACTIVE_TEEPID: pid of the tee process
# - LOG_NONINTERACTIVE_MAIL: target email
# - SUBJECT: mail subject
# - MAIL_ON_ERROR_ONLY: if "1", only send mail when an error happened
#======
finish_noninteractive_to_file_and_mail() {
        local LOG_NONINTERACTIVE_FILE=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG_NONINTERACTIVE_ERROR=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG_NONINTERACTIVE_PIPE=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG_NONINTERACTIVE_TEEPID=$1; shift || fatal "${FUNCNAME} usage error"
        local LOG_NONINTERACTIVE_MAIL=$1; shift || fatal "${FUNCNAME} usage error"
        local SUBJECT="[$(whoami)] $1"; shift || fatal "${FUNCNAME} usage error"
        local MAIL_ON_ERROR_ONLY=$1; shift || fatal "${FUNCNAME} usage error"

        # cleanup redirects & force tee to finish
        exec 1>&3 3>&- 2>&4 4>&- 5>&-
        if [ "$LOG_NONINTERACTIVE_TEEPID" != "" ] ; then
                kill -s PIPE "$LOG_NONINTERACTIVE_TEEPID" 2>/dev/null
                for ((i = 0; i < 10; i += 1)); do
                        # wait for max 10s
                        [ -d "/proc/${LOG_NONINTERACTIVE_TEEPID}" ] || break
                        sleep 1
                        kill -s PIPE "$LOG_NONINTERACTIVE_TEEPID" 2>/dev/null
                done
                # terminate tee
                [ -d "/proc/${LOG_NONINTERACTIVE_TEEPID}" ] && kill -9 "$LOG_NONINTERACTIVE_TEEPID" &> /dev/null
        fi

        if [ -s "$LOG_NONINTERACTIVE_ERROR" ] || ( [ $MAIL_ON_ERROR_ONLY == 0 ] && [ -s "$LOG_NONINTERACTIVE_FILE" ] ) ; then
                # send the complete output (stripped from ascii control codes) as mail
                {
                        [ $MAIL_ON_ERROR_ONLY -ne 0 ] && SUBJECT="$SUBJECT - Errors"

                        printf "From: $(whoami)@$(hostname --fqdn)\nTo: $LOG_NONINTERACTIVE_MAIL\nSubject: $SUBJECT\n\n"
                        sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" $LOG_NONINTERACTIVE_FILE
                } | /usr/sbin/sendmail $LOG_NONINTERACTIVE_MAIL
        fi

        rm -f $LOG_NONINTERACTIVE_ERROR 2> /dev/null
        rm -f $LOG_NONINTERACTIVE_PIPE 2> /dev/null
}

#======
# FUNCTION check_user_against_owner()
# Purpose: ensures the current executing user matches the base dir owner
#
# Throws fatal error if the users do not match
#======
check_user_against_owner() {
        local OWNER=`stat -c '%U' "$PATH_USER"`
        if [ "$OWNER" != "$USER" ]; then
                fatal "Executing user ($USER) does not match base owner ($OWNER), aborting."
        fi;
        return 0
}

#======
# FUNCTION check_user_is_not()
# Purpose: ensures the current executing user does not match the given name
#
# - 1st arg: name to check against
#
# Throws fatal error if the users do not match
#======
check_user_is_not() {
        if [ "$1" == "$USER" ]; then
                fatal "Executing user ($USER) is not allowed, aborting."
        fi;
        return 0
}

#======
# FUNCTION await_running_scripts()
# Purpose: wait for scripts to complete running
#
# - 1nd arg: array of allowed scripts
# - 2nd arg: array of scripts that force an immediate abort
# - 3rd arg: ootional timeout [default: 0]
# Return code 0: no scripts running; 1: script that is forcing an abort detected
#======
await_running_scripts() {
        local -n ALLOW=$1; shift || fatal "${FUNCNAME} usage error"
        local -n ABORT=$1; shift || fatal "${FUNCNAME} usage error"
        local TIMEOUT=$1; shift || TIMEOUT=0
        local TIMESTAMP=$(date +%s)

        while : ; do
                RUNNING=$(pgrep --list-full -U "$USER" --full '\.sh( |$)' | grep -v -E "^$PPID " | grep -v -E "(^|/| )$NAME_EXEC( |$)" | sort )

                # concurrently allowed scripts
                for SCRIPT in "${ALLOW[@]}"
                do
                        RUNNING=$(echo "$RUNNING" | grep -v -E "(^|/| )$SCRIPT( |$)")
                done

                RUNNING=$(echo "$RUNNING" | head -n 1)
                [ "$RUNNING" = "" ] && break

                # scripts that force an abort
                for SCRIPT in "${ABORT[@]}"
                do
                        if echo "$RUNNING" | grep -q -E "(^|/| )$SCRIPT( |$)" ; then
                                is_interactive && echo "Abort due to running process '$RUNNING'..."
                                return 1
                        fi
                done

                if [ "$TIMEOUT" != "0" ] && [ $(($(date +%s) - TIMESTAMP)) -gt $TIMEOUT ] ; then
                        is_interactive && echo "Aborting after waiting $TIMEOUT seconds..."
                        return 1
                fi

                is_interactive && echo "Waiting for process '$RUNNING' to finish since $(($(date +%s) - TIMESTAMP)) seconds ..."
                sleep $(( ( RANDOM % 3 )  + 1 ))s
        done
        return 0
}

#======
# FUNCTION is_interactive()
# checks if the current script exection is in interactive mode, i.e. has a tty
#======
is_interactive() {
        tty -s ;
        if [ $? -eq 1 ] ; then
                # non-interactive
                return 1
        fi
        return 0
}

#======
# FUNCTION trap_add()
# Purpose: appends a command to a trap
#
# - 1st arg: code to add
# - remaining args: names of traps to modify
#
# Example:  trap_add 'echo "in trap DEBUG"' DEBUG
#======
trap_add() {
    local TRAP_ADD=$1; shift || fatal "${FUNCNAME} usage error"
    local TRAP_CMD=
    local TRAP_SIGNAL=
    for TRAP_SIGNAL in "$@"; do

        # Grab the currently defined trap commands
        TRAP_CMD=`trap -p "$TRAP_SIGNAL" |  awk -F"'" '{print $2}'`
        TRAP_CMD="${TRAP_CMD}${TRAP_ADD};"

        trap "${TRAP_CMD}" "$TRAP_SIGNAL" || fatal "unable to add to trap ${TRAP_SIGNAL}"
    done
}

#======
# FUNCTION check_cron_disabled()
# Purpose: checks if cron processing is disabled
#       - checks for existence of scripts/cron.disabled
#       - checks if maintenance mode is on
#
# Return code 1: disabled; 0: enabled
#======
check_cron_disabled() {
        if [ -f "$PATH_BASE/scripts/cron.disabled" ] ; then
                return 1
        fi;
        if [ -f "$PATH_BASE/code/storage/framework/down" ] ; then
                return 1
        fi;
        return 0
}

#======
# FUNCTION disable_cron()
# Purpose: disables cron processing
#
# Return code 1: cron is now disabled; 0: cron was already disabled
#======
disable_cron() {
        if [ -f "$PATH_BASE/scripts/cron.disabled" ] ; then
                # cron already disabled
                return 0
        fi;

        touch "$PATH_BASE/scripts/cron.disabled"
        return 1
}

#======
# FUNCTION temporarily_disable_cron()
# Purpose: temporarily disables cron until the script finishes
#       - if cron is already disabled, it will not be enabled after script completion
# Return code 1: cron is now disabled; 0: cron was already disabled
#======
temporarily_disable_cron() {
        if [ -f "$PATH_BASE/scripts/cron.disabled" ] ; then
                # cron already disabled
                return 0
        fi;

        touch "$PATH_BASE/scripts/cron.disabled"
        trap_add "rm -f '$PATH_BASE/scripts/cron.disabled'" EXIT
        return 1
}

#======
# FUNCTION enable_cron()
# Purpose: enables cron processing
#======
enable_cron() {
        if [ -f "$PATH_BASE/scripts/cron.disabled" ] ; then
                rm -f "$PATH_BASE/scripts/cron.disabled"
        fi;
}

#======
# FUNCTION check_script_singleton(...$PARAMS)
# Purpose: ensure the script is not yet running
# Return code 1: script is running; 0: script is not running already
#======
check_script_singleton()
{
        [ $($FUSER "$0" 2>/dev/null | wc -w) -ne 1 ] && return 1

        return 0
}

#======
# FUNCTION check_script_singleton_adv($TIMEOUT, ...$PARAMS)
# Purpose: ensure the script is not yet running and not running longer than $TIMEOUT
# Return code 1: script is not yet running; 0: script is running already
#======
check_script_singleton_adv()
{
    local TIMEOUT=$1; shift || fatal "${FUNCNAME} usage error"

    # make sure script is not already running
    if [ ! "$1" == "--run" ]; then
        local SCRIPT="$PATH_EXEC/$(basename "$0")"

        # check if script is already running
        local PID=`pgrep -f "$SCRIPT --run" | head -1`
        if [ "$PID" == "" ]; then
                # run script
                "$SCRIPT" --run "$@" &
        else
                # check if the script is running too long
                AGE=`expr $(date +%s) - $(stat -c %X /proc/$PID)`
                if [ $AGE -gt $TIMEOUT ]; then
                    echo "'$SCRIPT --run' is running too long ($AGE), killing it..."
                    # kill the process group
                    \kill -s 9 -- -$PID
                fi
        fi
        return 0
    fi

    return 1
}

#======
# FUNCTION is_profile(ENV_NAME)
# checks if the profile matches $ENV_NAME
# ENV_NAME: environment name to check against
#======
is_profile()
{
    local ENV_NAME=$1; shift || fatal "${FUNCNAME} usage error"
    [ -e ${APP_ENV+x} ] && fatal "Missing APP_ENV var"

    [ "$APP_ENV" = "$ENV_NAME" ] && return 0

    return 1
}


# find user if in login-less shell

if [ -z "$USER" ]; then
    export USER="$(id -u -n)"
fi;

# path: executing script
NAME_EXEC="$(basename "$0")"
PATH_EXEC="$(cd "$( dirname "$0" )" && pwd )"

# path: this script
PATH_THIS="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# path: deploy source root
PATH_BASE="$( cd "$( dirname "${PATH_THIS}" )/../" && pwd )"

# path: scripts dir
PATH_SCRIPTS="$PATH_BASE/scripts"


# setting default php options, can be overwritten in env.sh

FUSER=/bin/fuser


# php: activate xdebug debugging

if [ "$XDEBUG" != "" ]; then
      PHP_OPTIONS_BASE="$PHP_OPTIONS_BASE -dzend_extension=xdebug.so -dxdebug.start_with_request=yes"
fi

# load profile based environment config

CONFIG="$PATH_BASE/code/.env"
if [ ! -f "$CONFIG" ] ; then
    echo "Missing code/.env configuration" >&2;
    exit 1;
fi
source "$CONFIG"

CONFIG="$PATH_BASE/code/.env.local"
if [ -f "$CONFIG" ] ; then
    source "$CONFIG"
fi

CONFIG="$PATH_BASE/.env"
if [ ! -f "$CONFIG" ] ; then
    echo "Missing src/.env configuration" >&2;
    exit 1;
fi
source "$CONFIG"


# path: user dir (containing the git checkout)
PATH_USER="$( cd "$( dirname "${PATH_BASE}" )" && pwd )"

# path: tmp
PATH_TEMP="$PATH_USER/tmp"

# path: data
PATH_DATA="$PATH_USER/data"

# path: logs
PATH_LOGS="$PATH_USER/logs"


# php: runtime configuration

PHP_BINARY="${SCRIPTS_PHP_BINARY:=/usr/bin/php}"
PHP_OPTIONS_BASE="${PHP_OPTIONS_BASE:="-ddisplay_errors=on"}"
PHP_OPTION_ERRORREPORTING="${PHP_OPTION_ERRORREPORTING:=22519}"   # E_ALL & ~E_DEPRECATED & ~E_STRICT & ~E_NOTICE
PHP_OPTION_ERRORLOG="${PHP_OPTION_ERRORLOG:=$PATH_LOGS/php-errors-scripts.log}"
PHP_OPTION_TMPDIR="${PHP_OPTION_TMPDIR:=$PATH_TEMP}"
PHP_OPTION_MEMORYLIMIT="${PHP_OPTION_MEMORYLIMIT:=-1}"
PHP_OPTION_SESSIONSAVEPATH="${PHP_OPTION_SESSIONSAVEPATH:=$PHP_OPTION_TMPDIR}"

PHP_RUN="$PHP_BINARY $PHP_OPTIONS_BASE -dvariables_order=EGPCS -dmemory_limit=$PHP_OPTION_MEMORYLIMIT -derror_log=$PHP_OPTION_ERRORLOG -derror_reporting=$PHP_OPTION_ERRORREPORTING -dupload_tmp_dir=$PHP_OPTION_TMPDIR -dsys_temp_dir=$PHP_OPTION_TMPDIR -dsoap.wsdl_cache_dir=$PHP_OPTION_TMPDIR -dopcache.lockfile_path=$PHP_OPTION_TMPDIR -dsession.save_handler=files -dsession.save_path=$PHP_OPTION_SESSIONSAVEPATH "

# framework runtimes

ARTISAN="$PHP_RUN $PATH_BASE/code/artisan"
ARTISAN_BINARY="${PATH_SCRIPTS}/artisan.sh"
PHP_BINARY="${PATH_SCRIPTS}/php.sh"
YARN_BINARY="${PATH_SCRIPTS}/yarn.sh"

# prepare execution

# check users
check_user_against_owner

# keep current directory
pushd . >/dev/null
trap_add 'popd >/dev/null' EXIT
