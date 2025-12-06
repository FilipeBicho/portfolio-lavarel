#!/bin/bash

source "$(dirname ${BASH_SOURCE[0]})/env/bash.sh"

cd "${PATH_BASE}/code" || fatal "Unable to switch into directory ${PATH_BASE}/code"

# ignore warnings for outdated browserlists - we don't want packages to update randomly
export BROWSERSLIST_IGNORE_OLD_DATA=true

${SCRIPTS_YARN_BINARY:=/usr/bin/yarn} "$@"
