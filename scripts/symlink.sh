#!/bin/bash

#shellcheck source=env/inc-symlink.sh
source "$(dirname ${BASH_SOURCE[0]})/env/source.symlink.sh"

# symlink app dirs

DST_DIR="$DATA_DIR"
[ "$DST_DIR" == "" ] && DST_DIR="../../../data/storage"

#symlink "$BASE/code/storage" "framework" "$DST_DIR/framework" 1
#symlink "$BASE/code/storage" "logs" "$DST_DIR/logs" 1

# auto-symlink files in the config dir
processDir "$BASE" "$CONFIG_DIR"

# now do the same for the override directory, if necessary
if [ -d "$BASE/$OVERRIDE_DIR" ]; then
    echo
    echo "taking care of overrides..."

    processDir "$BASE" "$OVERRIDE_DIR"
fi

mkdir -p "${PATH_USER}/logs/crons"
mkdir -p "${PATH_USER}/data/storage/framework/"{cache/data,sessions,views}
mkdir -p "${PATH_USER}/data/storage/logs"

