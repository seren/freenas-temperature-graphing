#!/usr/local/bin/bash
#####
# This script gathers and outputs the CPU and drive
# temperatures in a format rrdtool can consume.
#
# Author: Seren Thompson
# Date: 2017-04-24
# Website: https://github.com/seren/freenas-temperature-graphing
#####

# # display expanded values
# set -o xtrace
# quit on errors
set -o errexit
# error on unset variables
set -o nounset


# Helpful usage message
func_usage () {
  echo ' This script gathers and outputs the CPU and drive
temperatures in a format rrdtool can consume.

Usage $0 [-v] [-d] [-h]

-v | --verbose  Enables verbose output
-d | --debug    Outputs each line of the script as it executes (turns on xtrace)
-h | --help     Displays this message

Options for ESXi:
--platform "esxi"                  Indicates that we will use ESXi tools to retrieve CPU temps
--ipmitool_username <USERNAME>     Required: Username to use when connecting to BMC
--ipmitool_address  <BMC_ADDRESS>  Required: BMC ip address to connect to

'
}


# Process command line args
help=
verbose=
debug=
USERNAME=
BMC_ADDRESS=
PLATFORM=
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)  help=1;                     shift 1 ;;
    -v|--verbose) verbose=1;                shift 1 ;;
    -d|--debug) debug=1;                    shift 1 ;;
    --platform) PLATFORM=$2;                shift 2 ;;
    --ipmitool_username) USERNAME=$2;       shift 2 ;;
    --ipmitool_address) BMC_ADDRESS=$2;     shift 2 ;;
    -*)         echo "$0: Unrecognized option: $1 (try --help)" >&2; exit 1 ;;
    *)          shift 1; break ;;
  esac
done

if [ -n "$debug" ]; then
  set -o xtrace
  verbose=1
fi

# [ -n "$verbose" ] && set -o xtrace

[ -n "$help" ] && func_usage && exit 0

case "${PLATFORM}" in
  esxi)
    [ -n "$verbose" ] && echo "Platform is set to '${PLATFORM}'. Username is '${USERNAME} and ip is '${BMC_ADDRESS}'"
    [ -z "$USERNAME" ] && echo "You need to to provide --ipmitool_username with an argument" && exit 1
    [ -z "$BMC_ADDRESS" ] && echo "You need to to provide --ipmitool_address with an argument" && exit 1
    ;;
esac

# Check we're root
if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0 $1'"
  exit 1
fi

# Get current working directory
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[ -n "$verbose" ] && echo "Current working directory is: ${CWD}"

# Load common functions (temperature retrieval, device enumeration, etc)
# shellcheck source=./rrd-lib.sh
. "${CWD}/rrd-lib.sh"

get_devices
get_temperatures

# Strip any leading, trailing, or duplicate colons
[ -n "$verbose" ] && echo "Cleaned up data:"
echo "${data}" | sed 's/:::*/:/;s/^://;s/:$//'

[ -n "$verbose" ] && echo "Done gathering temp data returning"
