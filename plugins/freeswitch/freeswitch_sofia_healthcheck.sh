#!/bin/bash

set -e
set -u
set -o pipefail

if [ $# -ne 2 ]; then
	echo "ERROR: use ${0} [profile|gateway] item"
	exit 3 # UNKNOWN
fi

MODE=${1}
ITEM=${2}


function get_profile_status() {

	local item=$1

	fs_cli -bnx "sofia status" | grep profile | grep ${item} | awk '{print $4}'

}

function get_gateway_status() {

	local item=$1

	fs_cli -bnx "sofia status gateway ${item}"|grep ^Status | awk '{print $2}'

}

function get_return_code() {

	local mode=$1
	local status=$2
	local item=$3

	if [ -z ${status} ]; then
		echo "Unable to get status for ${item}"
		exit 3 # UNKNOWN
	else
		echo "${mode} ${item} is ${status}"
	fi

	if [ ${status} == "UP" -o ${status} == "RUNNING" ]; then
		exit 0 # OK
	else
		exit 2 # CRITICAL
	fi

}


case "$1" in
	profile)
		STATUS=$(get_profile_status $ITEM)
		;;
	gateway)
		STATUS=$(get_gateway_status $ITEM)
		;;
	*)
		echo "ERROR: use ${0} [profile|gateway] item"
		exit 3 # UNKNOWN
		;;
esac

get_return_code ${MODE} ${STATUS} ${ITEM}
