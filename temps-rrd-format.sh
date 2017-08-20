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


# When this script is executed as a FreeNAS cron job, it is executed with $PWD   
# set to /root. Because it can be installed in any arbitrary directory, we
# must use dirname to find what to include in $PATH. Unless make or pkgng can
# be used to install freenas-temperature-graphing, we must live with this 
# unfortunate hack.
PATH="$PATH:$(dirname $0)"

source rrd-lib.sh

# Helpful usage message
func_usage () {
  echo ' This script gathers and outputs the CPU and drive
temperatures in a format rrdtool can consume.

Usage $0 [-v] [-d] [-h]

-v | --verbose  Enables verbose output
-d | --debug   Outputs each line of the script as it executes (turns on xtrace)
-h | --help    Displays this message
'
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
    *)          shift 1; break ;;
  esac
done

if [ -n "$debug" ]; then
  set -o xtrace
  verbose=1
fi

[ -n "$verbose" ] && set -o xtrace

[ -n "$help" ] && func_usage && exit 0

# Check we're root
if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0 $1'"
  exit 1
fi

sep=':'

get_devices
get_temperatures

# Strip any leading, trailing, or duplicate colons
[ -n "$verbose" ] && echo "Cleaned up data:"
echo "${data}" | sed 's/:::*/:/;s/^://;s/:$//'

[ -n "$verbose" ] && echo "Done gathering temp data returning"
