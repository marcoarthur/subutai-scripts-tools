#!/bin/bash

REX_FILE="$HOME/tools/perl5/subutai/subutai-rex/Rexfile"
HOST_COLOR='\033[0;34m'
TASK_COLOR='\033[0;31m'
NC='\033[0m'

function rexx () {
    if ! [[ -e $REX_FILE ]]; then
        echo "Can't find Rexfile"
        exit 1
    fi
    rex -f $REX_FILE $@
}

function list_task() {
    rexx -T
    echo -e "\n${HOST_COLOR} HOSTS  IP's ${NC}"
    subutai.pl --list-peers
}

function main() {
    if (( $# < 1 )); then
        list_task
        echo -e "\nAdd ${TASK_COLOR}new task${NC} using: $REX_FILE"
        exit 0
    fi

    rexx $@
}

main $@
