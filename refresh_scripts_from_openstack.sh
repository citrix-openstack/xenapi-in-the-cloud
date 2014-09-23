#!/bin/bash

set -eu

TMPDIR=$(mktemp -d)
CONFIG="$TMPDIR/config"
REPO="https://github.com/openstack-infra/config"

THIS_FILE=$(readlink -f $0)
THIS_DIR=$(dirname $THIS_FILE)
SCRIPT_DIR="$THIS_DIR/scripts"

git clone "$REPO" "$CONFIG"

for fname in $SCRIPT_DIR/*; do
    PATH_TO_SOURCE=$(find $CONFIG -name $(basename $fname))

    if [ "1" != "$(echo $PATH_TO_SOURCE | wc -w)" ]; then
        echo "Multiple files found with name $fname at $REPO"
        exit 1
    fi

    if [ -z "$PATH_TO_SOURCE" ]; then
        echo "$path was not found within $REPO" >&2
        exit 1
    else
        echo "Copy $PATH_TO_SOURCE to $SCRIPT_DIR"
        cp "$PATH_TO_SOURCE" $SCRIPT_DIR/
    fi
done

rm -rf $TMPDIR
