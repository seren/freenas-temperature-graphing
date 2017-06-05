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

Note: The filename must be in the following format: temps-Xmin.rdd
  where X is the minute interval between readings.
  ex: "temps-10min.rrd" would contain readings every 10 minutes

Example:
  $0 /mnt/mainpool/temperatures/temps-5min.rrd
'
}

# Checks that a file is writeable
func_test_writable () {
  # If it doesn't exist, exit with a non-error code
  if ! [ -e ${1} ]; then
    echo "'${1}' doesn't exist"
    return 0
  fi
  # Exit if the data file is something other than a file for safety and security
  if [ -e ${1} ] && ! [ -f ${1} ]; then
    echo "'${1}' exists, but isn't a file."
    exit 1
  fi
  {  # try
    touch ${1}
    return 0
  } || {  # catch
    echo ''
    echo "Error: Could not write to '${1}'."
    echo "Check that the enclosing directory exists and is is writable by the script user"
    return 1
  }
}

# Checks we can use chmod
func_test_chmod () {
  TEMPFILENAME=$(dd if=/dev/urandom bs=300 count=1 status=noxfer 2>/dev/null | sha256)

  # Test that chmod works in /tmp
  { # try
    touch "/tmp/chmodtest_${TEMPFILENAME}"
    chmod 600 "/tmp/chmodtest_${TEMPFILENAME}"
  } || {  # catch
    echo ''
    echo "Error: Couldn't use chmod in /tmp. Is the filesystem a Windows filesystem?"
    rm "/tmp/chmodtest_${TEMPFILENAME}"
    return 1
  }
  rm -f "/tmp/chmodtest_${TEMPFILENAME}"

  dir=${1%/*}
  # If it doesn't exist, exit with a non-error code
  if ! [ -d "${dir}" ]; then
    echo "'${1}' doesn't exist"
    return 0
  fi
  { # try
    touch "${dir}/chmodtest_${TEMPFILENAME}"
    chmod 600 "${dir}/chmodtest_${TEMPFILENAME}"
  } || {  # catch
    echo ''
    echo "Error: Couldn't use chmod in ${dir}. Is the filesystem a Windows filesystem?"
    rm "${dir}/chmodtest_${TEMPFILENAME}"
    return 1
  }
  rm -f "${dir}/chmodtest_${TEMPFILENAME}"
}

# Checks whether the rrd file and the data variable have matching number of fields
func_compare_data_field_count_to_rrd_gauge_count () {
  if [ -z "${data}" ]; then
    echo "Data variable is empty"
    return 1
  fi
  gauges_in_file=$(${RRDTOOL} info ${datafile} | grep -c 'type = "GAUGE"')
  colons_from_data="${data//[^:]}"
  fields_in_data=$(( ${#colons_from_data} + 1 ))
  if ! [ "${gauges_in_file}" == "${fields_in_data}" ]; then
    echo "The number of fields in the rrd file (${gauges_in_file}) does not match the number of fields supplied (${fields_in_data})"
    echo "You may need to delete the rrd file and try again"
    return 1
  fi
 return 0
}

# Does rrdtool barf when trying to parse the data file?
func_check_file_is_rrd () {
  ${RRDTOOL} info "${1}" &>/dev/null
  return $?
}

# Run sanity checks and validations
func_debug_setup () {
  func_debug_setup_return_test () {
    if ! [ "$1" == "0" ]; then
      echo "Test failed (returned $1)"
      exit 1
    fi
  }

  echo "Testing file permissions..."
  func_test_writable "${datafile}"
  func_debug_setup_return_test $?

  echo "Testing chmod..."
  func_test_chmod "${datafile}"
  func_debug_setup_return_test $?

  echo "Testing file field count..."
  func_compare_data_field_count_to_rrd_gauge_count
  func_debug_setup_return_test $?

  echo "Testing that file is a valid rrd file..."
  func_check_file_is_rrd "${datafile}"
  if ! [ "$?" == "0" ]; then
    echo "Test failed. '${datafile}' is not a valid rrd file. You may need to delete it and run this script again"
    exit 1
  fi

  echo "Daignostics didn't find anything wrong."
}





# Process command line args
help=
verbose=
debug=
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)  help=1;                     shift 1 ;;
    -v|--verbose) verbose=1;                shift 1 ;;
    -d|--debug) debug=1;                    shift 1 ;;
    -*)         echo "$0: Unrecognized option: $1 (try --help)" >&2; exit 1 ;;
    *)          datafile=$1;                     shift 1; break ;;
  esac
done

if [ -n "$debug" ]; then
  set -o xtrace
  verbose=1
fi

[ -n "$help" ] && func_usage && exit 0

# Check we're root
if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0 $1'"
  exit 1
fi

# Check that we were supplied a db filename
if [ -z ${datafile} ]; then
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


# If the rrdtool database exists, make sure it's writable. Otherwise create it
if [ -e ${datafile} ]; then
  func_test_writable "${datafile}" || exit 1
else
  [ -n "$verbose" ] && echo "Rrdtool database doesn't exist. Creating it."
  # Get CPU numbers
  numcpus=$(/sbin/sysctl -n hw.ncpu)
  # Get drive device names
  drivedevs=
  for i in $(/sbin/sysctl -n kern.disks | awk '{for (i=NF; i!=0 ; i--) if(match($i, '/da/')) print $i }' ); do
    # Sanity check that the drive will return a temperature (we don't want to include non-SMART usb devices)
    DevTemp=`/usr/local/sbin/smartctl -a /dev/$i | awk '/194 Temperature_Celsius/{print $0}' | awk '{print $10}'`;
    if ! [[ "$DevTemp" == "" ]]; then
      drivedevs="${drivedevs} ${i}"
    fi
    [ -n "$verbose" ] && echo "numcpus: ${numcpus}"
    [ -n "$verbose" ] && echo "drivedevs: ${drivedevs}"
  done

  # Calculate the sampling interval from the filename
  interval=`echo ${datafile} | sed 's/.*temps-\(.*\)min.rrd/\1/'`  # extract minute number
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


[ -n "$verbose" ] && echo "Running script: '${CWD}/temps-rrd-format.sh'"
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && "${CWD}/temps-rrd-format.sh" "$@"
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && echo ""
[ -n "$verbose" ] && echo "(running script again non-verbosely)"
data=`${CWD}/temps-rrd-format.sh`
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
