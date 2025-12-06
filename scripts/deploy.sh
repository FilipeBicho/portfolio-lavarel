#!/bin/bash

source "$(dirname ${BASH_SOURCE[0]})/env/bash.sh"

check_script_singleton || exit 0


#======
# FUNCTION print_usage()
#======
usage() {
    [ "$1" != "" ] && echo "$1" >&2 && echo >&2
    echo "Usage:" >&2
    echo "   $0 [--enable] [--maintenance] [--skip-git] [--no-silent] [--help]" >&2

    echo >&2
    echo "Options:" >&2
    echo "   --enable               force enable cron & website after successful deploy" >&2
    echo "   --maintenance          force a full maintenance" >&2
    echo "   --skip-git             do not update the code from git" >&2
    echo "   --no-scripts-check     don't check for currently running scripts" >&2
    echo "   --no-silent            show all output of underlying commands" >&2
    echo "   --help                 show usage" >&2

    echo >&2
    exit 1
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

        echo "$(date +'%H:%M:%S') -- $MSG"
        [ "$LOG" != "" ] && echo "$(date +'%Y-%m-%d %H:%M:%S') [$$] $MSG" >> "$LOG"
}



# set default values

LOGFILE="$PATH_LOGS/deploy.log"

PATH_SRC="${PATH_USER}/src"

UPDATE_GIT=1

PRESERVE_MAINTENANCE=0
PRESERVE_CRON=0

GIT_REVISION=""
FORCE_ENABLE=0
FORCE_MAINTENANCE=0
SILENT=1

if is_profile "local" ; then
    # set some defaults for local dev environments
    FORCE_ENABLE=1
    UPDATE_GIT=0
fi


# parse parameters

PARAMS_ORI="$@"

while [[ $# -gt 0 ]]; do
    key="$1"
    case "$key" in
        -h|--help)
            usage
            ;;
        --no-silent)
            SILENT=0
            ;;
        --no-scripts-check|--no-script-check)
            CHECK_SCRIPTS=0
            ;;
        --enable)
            FORCE_ENABLE=1
            ;;
        --skip-git)
            UPDATE_GIT=0
            ;;
        --maintenance)
            FORCE_MAINTENANCE=1
            ;;
        *)
            usage "Error: Unknown option '$key'"
            ;;
    esac
    shift
done

[ "$SILENT" = "1" ] && CONSOLE_SILENT=" --quiet" || CONSOLE_SILENT=""



log "STARTING NEW DEPLOYMENT: $0 $PARAMS_ORI" "$LOGFILE"


# grab current revision and check if git credentials are ok

if [ "$UPDATE_GIT" = "1" ] ; then

    pushd "${PATH_BASE}" > /dev/null

    msg "git authentication" "$LOGFILE"
    git fetch --prune --quiet || fatal "FAIL: git fetch" "$LOGFILE"

    GIT_REVISION="$(git rev-parse HEAD)"

    popd > /dev/null

fi


# check local file system for unwanted changes

if [ "$UPDATE_GIT" = "1" ] ; then

    pushd "${PATH_SRC}" > /dev/null

    msg "checking for local git changes" "$LOGFILE"
    # "git diff-index --quiet --ignore-submodules=untracked HEAD -- " doesn't work on repositories without commits
    OUTPUT=$(git status --porcelain --untracked-files=no)
    if [ "${OUTPUT//[$'\t\r\n ']}" != "" ] ; then
        err "Git has local changes that need to be reverted or committed before the deploy" "$LOGFILE"
        echo "$OUTPUT"
        fatal
    fi

    popd > /dev/null

fi


# disable cron

if check_cron_disabled ; then
    msg "disable cron" "$LOGFILE"
else
    # cron is already disabled
    PRESERVE_CRON=1
fi
disable_cron # as cron could also be disabled via maintenance, we're disabling it here to be sure


# make sure no other script is currently running

if [ "$CHECK_SCRIPTS" = "1" ] ; then
    ALLOW=( )
    while : ; do
        RUNNING=$(pgrep --list-full -U "$USER" --full '\.sh( |$)' | grep -v -E "^$PPID " | grep -v -E "(^|/| )$NAME_EXEC( |$)" | sort -n )
        for SCRIPT in "${ALLOW[@]}"
        do
          RUNNING=$(echo "$RUNNING" | grep -v -E "(^|/| )$SCRIPT( |$)")
        done
        RUNNING=$(echo "$RUNNING" | head -n 1)
        [ "$RUNNING" = "" ] && break

        msg "Waiting for process '${RUNNING}' to terminate..."
        sleep 2
    done
fi

if [ -e "${PATH_BASE}/code/storage/framework/down" ] ; then
    # maintenance is already enabled, keep it that way
    PRESERVE_MAINTENANCE=1
elif [ "$FORCE_MAINTENANCE" = "1" ] ; then
    msg "enable maintenance mode" "$LOGFILE"
    touch "${PATH_BASE}/code/storage/framework/down" || fatal "FAIL" "$LOGFILE"
fi

START_TIMESTAMP=$(date +%s)



# update branch

if [ "$UPDATE_GIT" = "1" ] ; then

    pushd "${PATH_SRC}" > /dev/null

    msg "update code" "$LOGFILE"

    git pull | grep -v -E 'Already up.to.date\.' ; [ ${PIPESTATUS[0]} -eq 0 ] || fatal "FAIL: git pull" "$LOGFILE"

    if [ "$(git rev-parse HEAD)" = "$GIT_REVISION" ] ; then
        # the code wasn't updated, so any possible further rollbacks aren't needed
        UPDATE_GIT=0
    fi
    popd > /dev/null

fi



# actual deployment starts...

pushd "${PATH_SRC}/code" > /dev/null || fatal "FAIL: unable to switch into ${PATH_SRC}/code"

# ignore warnings for outdated browserlists - we don't want packages to update randomly
export BROWSERSLIST_IGNORE_OLD_DATA=true

msg "run db migrations" "$LOGFILE"
$ARTISAN migrate $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"

msg "purge & refresh cache" "$LOGFILE"
$ARTISAN cache:clear $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"

msg "purge & refresh config cache" "$LOGFILE"
$ARTISAN config:clear $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"
$ARTISAN config:cache $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"

msg "discover packages" "$LOGFILE"
$ARTISAN package:discover $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"

msg "purge & refresh route cache" "$LOGFILE"
$ARTISAN route:clear $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"

msg "purge & refresh view cache" "$LOGFILE"
$ARTISAN view:clear $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"
$ARTISAN view:cache $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"

# capture available commands for all later actions
AVAILABLE_COMMANDS=$($ARTISAN 2> /dev/null)

if echo "$AVAILABLE_COMMANDS" | grep -q ' refusion:render-cms-tailwindcss-classes ' ; then
    msg "render cms block tailwindcss"
    $ARTISAN refusion:render-cms-tailwindcss-classes $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"
fi

msg "install node modules & build assets" "$LOGFILE"
rm -rf public/build/assets || true
if [ "$SILENT" = "1" ] ; then
    $YARN_BINARY --silent install || fatal "FAIL" "$LOGFILE"
    $YARN_BINARY --silent build || fatal "FAIL" "$LOGFILE"
else
    $YARN_BINARY install || fatal "FAIL" "$LOGFILE"
    $YARN_BINARY build || fatal "FAIL" "$LOGFILE"
fi


popd > /dev/null



# cleanup

if echo "$AVAILABLE_COMMANDS" | grep -q ' storage:link ' ; then
    msg "link storage"
    $ARTISAN storage:link --force --quiet || fatal "Error running storage:link" "$LOGFILE"
fi

if [ "$SCRIPTS_CRONTAB_CONFIG" != "" ] ; then
    msg "reloading crontab" "$LOGFILE"
    [ -f "${PATH_SRC}/${SCRIPTS_CRONTAB_CONFIG}" ] || fatal "Unable to find ${PATH_SRC}/${SCRIPTS_CRONTAB_CONFIG} (defined in SCRIPTS_CRONTAB_CONFIG)" "$LOGFILE"
    crontab "${PATH_SRC}/${SCRIPTS_CRONTAB_CONFIG}" || fatal "FAIL" "$LOGFILE"
fi

if [ -e "${PATH_BASE}/code/storage/framework/down" ] && { [ "$PRESERVE_MAINTENANCE" = "0" ] || [ "$FORCE_ENABLE" = "1" ] ; } ; then
    msg "disable maintenance mode" "$LOGFILE"
    $ARTISAN up $CONSOLE_SILENT || fatal "FAIL" "$LOGFILE"
fi

if [ "$PRESERVE_CRON" = "0" ] || [ "$FORCE_ENABLE" = "1" ] ; then
    msg "enable cron" "$LOGFILE"
    rm $PATH_SCRIPTS/cron.disabled || fatal "FAIL" "$LOGFILE"
fi


# ... and done!

msg "done, active part took $(expr $(date +%s) - ${START_TIMESTAMP}) seconds" "$LOGFILE"
