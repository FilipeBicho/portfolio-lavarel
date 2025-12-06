#!/bin/bash

# make sure we're not root
if [[ $EUID = 0 ]]; then
   echo "ERROR: This script must be run as the webuser"
   exit 1
fi

#======
# FUNCTION print_usage()
#======
usage() {
    [ "$1" != "" ] && echo "$1" >&2 && echo >&2
    echo "Usage:" >&2
    echo "   $0 {config-profile} [--overwrite]"
    echo >&2
    echo "Options:" >&2
    echo "   config-profile         the profile to apply, f.e. 'vshn/prod'" >&2
    echo "   --overwrite            overwrite possible existing files" >&2
    echo "   --help                 show usage" >&2
    echo >&2
    exit 1
}

#======
# FUNCTION fatal()
# Purpose: outputs message to stderr and exits
#
# - first parameter: message to output
#======
fatal() {
        echo "$1" 1>&2
        exit 64
}


# parse options

BASE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" && pwd )"
PATH_USER="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../../" && pwd )"
CONFIG_DIR="environments/$1"; shift || usage
OVERRIDE_DIR="config/override"
OVERWRITE_EXISTING=0

while [[ $# -gt 0 ]]; do
    key="$1"
    case "$key" in
        -h|--help)
            usage
            ;;
        --overwrite)
            OVERWRITE_EXISTING=1
            ;;
        --overwrite=* )
            OVERWRITE_EXISTING="${key#*=}"
            ;;
        *)
            usage "Error: Unknown option '$key'"
            ;;
    esac
    shift
done


# check folders

[ -d "$BASE/$CONFIG_DIR" ] || fatal "Unable to find config dir '$BASE/$CONFIG_DIR'"


# check if symlinks are supported

ln -s $BASE $BASE/symlink.test 2> /dev/null
if [ $? -ne 0 ]; then
    SYMLINK_SUPPORT=0
else
    SYMLINK_SUPPORT=1
    rm -f $BASE/symlink.test > /dev/null
fi

# read local.sh variables for use during symlinking
[ -f "$BASE/$CONFIG_DIR/scripts/env/local.sh" ] && source "$BASE/$CONFIG_DIR/scripts/env/local.sh"

## exit on failures
#set -e

function symlink()
{
        local DIR="$1"
        local FILE="$2"
        local TARGET="$3"
        local CREATE="$4"

        echo "$DIR/$FILE:"

        if [ $SYMLINK_SUPPORT != 0 ] && [ -e "$DIR/$FILE" ]; then
                if [ ! -L "$DIR/$FILE" ]; then
                        [ "$OVERWRITE_EXISTING" != "1" ] && echo "   exists but is not a symlink" && return 1
                        [ -d "$DIR/$FILE" ] && echo "  exists but is a directory, not replacing. remove $DIR/$FILE manually" 1>&2 && return 1
                        echo "   exists but is not a symlink, replacing."
                        rm -f "$DIR/$FILE"
                fi;
        fi;

        # switch directory
        if [ ! -e "$DIR" ]; then
            mkdir -p "$DIR"
        fi;
        pushd "$DIR" >/dev/null

        # create dir if needed
        if [ ! -e "$TARGET " ]; then
                if [ "$CREATE" = "1" ]; then
                        echo "   create target directory '$TARGET'"
                        mkdir -p "$TARGET"
                fi;
        fi;

        if [ $SYMLINK_SUPPORT = 0 ]; then
                # copy file
                echo "   copy file"
                cp -f "$TARGET" "$FILE"
        else
                # create symlink
                echo "   create symlink to '$TARGET'"
                ln -sfn "$TARGET" "$FILE"
        fi

        # switch back
        popd >/dev/null

        return 0;
}

function processDir()
{
    local BASE="$1"
    local CONFIG_DIR="$2"

    pushd "$BASE/$CONFIG_DIR" >/dev/null
    for FILE in `find . -type f`;
    do
            FILE="${FILE:2}"
            DIR="$(dirname $FILE)"
            FILE="${FILE##*/}"

            if [ "$DIR" == "." ]; then
                    # file is in the git root
                    REL=""
                    SRC_FILE="$FILE"
            else
                    # file is not in the git root

                    LEVEL=$(grep -o "/" <<< "$DIR" | wc -l)
                    REL="../"
                    for ((i=1; i<=$LEVEL; i++))
                    do
                            REL="../$REL"
                    done

                    SRC_FILE="$DIR/$FILE"
            fi;

            symlink "$BASE/$DIR" "$FILE" "$REL$CONFIG_DIR/$SRC_FILE" 0
    done
    popd >/dev/null
}
