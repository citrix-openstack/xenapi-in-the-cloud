#!/bin/bash

set -eu
THIS_DIR=$(dirname $(readlink -f $0))

grep -e '^FILE_TO_TOUCH_ON_COMPLETION=.*' $THIS_DIR/../scripts/xenapi-in-rs.sh |
    cut -d "=" -f2 | tr -d '"'
