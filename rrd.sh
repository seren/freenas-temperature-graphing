#!/usr/local/bin/bash
#####
# This script generates and updates an rrdtool database
# of CPU and drive temperatures. It calls 'temps-rrd-format.sh'
# to actually get the data in a format it can use.
# It writes the data files to the same directory it
# runs from.
#
# Author: Seren Thompson
# Date: 2017-04-24
# Website: https://github.com/seren/freenas-temperature-graphing
#####

# # display expanded values
# set -o xtrace
# # quit on errors
# set -o errexit
# # error on unset variables
# set -o nounset


RRDTOOL=/usr/local/bin/rrdtool
SCRIPTVERSION="1.0"


# Helpful usage message
func_usage () {
  echo '
This script generates and updates an rrdtool database
of CPU and drive temperatures. It calls "temps-rrd-format.sh"
to actually get the data in a format it can use.
It writes the data files to the same directory it
runs from.

Usage $0 [-v] [-d] [-h] output-filename

-v | --verbose   Enables verbose output
-d | --debug   Outputs each line of the script as it executes (turns on xtrace)
-h | --help    Displays this message

Options for ESXi:
--platform "esxi"                  Indicates that we will use ESXi tools to retrieve CPU temps
--ipmitool_username <USERNAME>     Required: Username to use when connecting to BMC
--ipmitool_address  <BMC_ADDRESS>  Required: BMC ip address to connect to

Note: The filename must be in the following format: temps-Xmin.rdd
  where X is the minute interval between readings.
  ex: "temps-10min.rrd" would contain readings every 10 minutes

Example:
  $0 /mnt/mainpool/temperatures/temps-5min.rrd
'
}

# Process command line args
args=''
help=
verbose=
debug=
PLATFORM=default
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)  help=1;                     shift 1 ;;
    -v|--verbose) verbose=1;                shift 1 ;;
    -d|--debug) debug=1;                    shift 1 ;;
    --platform) PLATFORM=$2;                shift 2 ;;
    --ipmitool_username) USERNAME=$2;       shift 2 ;;
    --ipmitool_address) BMC_ADDRESS=$2;     shift 2 ;;
    -*)         echo "$0: Unrecognized option: $1 (try --help)" >&2; exit 1 ;;
    *)          datafile=$1;                     shift 1; break ;;
  esac
done

if [ -n "$debug" ]; then
  set -o xtrace
  verbose=1
fi

[ -n "$help" ] && func_usage && exit 0

case "${PLATFORM}" in
  esxi)
    [ -n "$verbose" ] && echo "Platform is set to '${PLATFORM}'. Username is '${USERNAME} and ip is '${BMC_ADDRESS}'"
    [ -z "$USERNAME" ] && echo "You need to to provide --ipmitool_username with an argument" && exit 1
    [ -z "$BMC_ADDRESS" ] && echo "You need to to provide --ipmitool_address with an argument" && exit 1
    args="${args} --platform ${PLATFORM} --ipmitool_username ${USERNAME} --ipmitool_address ${BMC_ADDRESS}"
    ;;
  *)
    args=''
    ;;
esac


# Check we're root
if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0 $1'"
  exit 1
fi

# Check that we were supplied a db filename
if [ -z "${datafile}" ]; then
  echo "Error: you need to give an output filename as an argument."
  echo
  func_usage
  exit 1
fi

# Debugging info
[ -n "$verbose" ] && echo "Rrdtool database filename: ${datafile}"


# Get current working directory
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[ -n "$verbose" ] && echo "Current working directory is: ${CWD}"

# Load common functions (temperature retrieval, device enumeration, etc)
# shellcheck source=./rrd-lib.sh
. "${CWD}/rrd-lib.sh"


# If the rrdtool database exists, make sure it's writable. Otherwise create it
if [ -e "${datafile}" ]; then
  func_test_writable "${datafile}" || exit 1
else
  [ -n "$verbose" ] && echo "Rrdtool database doesn't exist. Creating it."
  get_devices

  # Calculate the sampling interval from the filename
  interval=$(echo "${datafile}" | sed 's/.*temps-\(.*\)min.rrd/\1/')  # extract minute number
  if [ -z $interval ]; then
    echo "Couldn't find a minute number in filename '${datafile}' (should in format: temps-5min.rrd)."
    exit 1
  fi
  timespan=$((interval * 60))
  doubletimespan=$((timespan * 2))
  [ -n "$verbose" ] && echo "Sampling every ${timespan} seconds"

  # Generate the arguments for db creation for each cpu and drive
  rrdarg=
  for (( i=0; i < numcpus; i++ )); do
    rrdarg="${rrdarg} DS:cpu${i}:GAUGE:${doubletimespan}:0:150"
  done
  for i in ${drivedevs}; do
    rrdarg="${rrdarg} DS:${i}:GAUGE:${doubletimespan}:0:100"
  done

  echo "Creating rrdtool db file: ${datafile}"
  echo "Rrdtool arguments:  ${rrdarg}"
  echo ${RRDTOOL} create ${datafile} --step ${timespan} ${rrdarg} RRA:MAX:0.5:1:3000
  ${RRDTOOL} create ${datafile} --step ${timespan} ${rrdarg} RRA:MAX:0.5:1:3000
  if ! [ $? == 0 ]; then
    echo "ERROR: Couldn't initialize ${datafile}. Running diagnostics..."
    func_debug_setup
    exit 1
  else
    [ -n "$verbose" ] && echo "Initialized datafile"
    exit 0
  fi
fi

# If we run temps-rrd-format.sh in verbose mode, we can't capture the output
# in a variable. So if verbose is set, we run it twice, once for the user to
# see and once for the script to grab the output.
[ -n "$verbose" ] && echo "Running script: '${CWD}/temps-rrd-format.sh -v ${args}'"
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && "${CWD}/temps-rrd-format.sh" ${args}
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && echo "(running script again non-verbosely)"
data=$("${CWD}/temps-rrd-format.sh" ${args})
[ -n "$verbose" ] && echo "Data: ${data}"
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && echo "Updating the db: '${RRDTOOL} update ${datafile} N:${data}'"
${RRDTOOL} update ${datafile} N:${data}
if ! [ $? == 0 ]; then
  echo "ERROR: Couldn't update ${datafile} with the data provided. Running diagnostics..."
  func_debug_setup
  exit 1
else
  [ -n "$verbose" ] && echo "Added data"
  exit 0
fi
