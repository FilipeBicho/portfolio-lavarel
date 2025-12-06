#!/bin/bash

source "$(dirname ${BASH_SOURCE[0]})/env/bash.sh"

cd "${PATH_BASE}/" || fatal "Unable to switch into directory ${PATH_BASE}/"

$ARTISAN "$@"
