#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Load environment variables
source $SCRIPT_DIR/loadEnv.sh
source $PWD/.env

forge script "$@" --broadcast \
-vvv \
--rpc-url $LOCAL_PROVIDER
