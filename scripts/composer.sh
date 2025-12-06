#!/bin/bash

source "$(dirname ${BASH_SOURCE[0]})/env/bash.sh"

# compile composer.phar if necessary
NEEDS_PHAR_UPDATE=0
if [ ! -f "$PATH_SCRIPTS/env/composer.phar" ] ; then
    NEEDS_PHAR_UPDATE=1
else
    LAST_UPDATE=$(( $(date +%s) - $(date +%s -r "$PATH_SCRIPTS/env/composer.phar") ))
    [ "$LAST_UPDATE" -ge 1209600 ] && NEEDS_PHAR_UPDATE=1  # older than 14 days
fi

if [ "$NEEDS_PHAR_UPDATE" -eq 1 ] || [ "$1" = "--update-composer" ] ; then
    pushd "$PATH_SCRIPTS/env" >/dev/null

    echo "Composer: downloading installer"
    EXPECTED_CHECKSUM="$($PHP_RUN -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    $PHP_RUN -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$($PHP_RUN -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ] ; then
        rm composer-setup.php
        fatal 'ERROR: Invalid installer checksum'
    fi

    echo "Composer: installing"
    $PHP_RUN composer-setup.php --quiet "--${COMPOSER_VERSION:-2}"
    RESULT=$?
    rm composer-setup.php
    [ "$RESULT" != "0" ] && fatal "Composer: build failed"

    popd >/dev/null

    touch "$PATH_SCRIPTS/env/composer.phar"
    [ "$1" = "--update-composer" ] && echo "Composer: update completed" && $PHP_RUN "$PATH_SCRIPTS/env/composer.phar" --version && exit 0
fi

COMPOSER_OPTS=''
[[ "$*" =~ (^| )(update|require|remove|install)( |$) ]] && COMPOSER_OPTS="$COMPOSER_OPTS --ignore-platform-reqs"

cd "$PATH_BASE/code"
$PHP_RUN "$PATH_SCRIPTS/env/composer.phar" "$@" $COMPOSER_OPTS


# cleanup unwanted changes

[[ "$*" == *"--quiet"* ]] || echo "$(tput setaf 7)Checking & reverting unwanted changes $(tput sgr 0)"

_CHECK=.gitignore
if ! git diff -s --exit-code "${_CHECK}" ; then
    cp "${_CHECK}" "${_CHECK}-dist"
    git diff -s --exit-code "${_CHECK}-dist" || echo "$(tput setaf 1)WARNING: code/${_CHECK}-dist changes need to be merged to code/${_CHECK} $(tput sgr 0)"
    git checkout -- "${_CHECK}"
fi
