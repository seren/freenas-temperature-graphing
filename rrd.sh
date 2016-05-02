#!/usr/local/bin/bash
#####
# This script generates and updates an rrdtool database
# of CPU and drive temperatures. It calls 'temps-rrd-format.sh'
# to actually get the data in a format it can use.
# It writes the data files to the same directory it
# runs from.
# Author: Seren Thompson
# Date: 2016-04-02
#####

# # quit on errors
# set -o errexit
# # error on unset variables
# set -o nounset



if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0 $1'"
  exit 1
fi

if [ -z $1 ]; then
  echo "Error: you need to give an output filename as an argument. Ex:"
  echo " $0 outputdata.rrd"
  echo
  echo "Exiting..."
  exit 1
fi

# Get current working directory
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# If the rrdtool database file doesn't exist, create it
if ! [ -f $1 ]; then
  # Get CPU numbers
  numcpus=$(/sbin/sysctl -n hw.ncpu)
  # Get drive device names
  drivedevs=
  for i in $(/sbin/sysctl -n kern.disks | awk '{for (i=NF; i!=0 ; i--) if(match($i, '/da/')) print $i }' ); do
    # Sanity check that the drive will return a tempurature (we don't want to include non-SMART usb devices)
    DevTemp=`/usr/local/sbin/smartctl -a /dev/$i | awk '/194 Temperature_Celsius/{print $0}' | awk '{print $10}'`;
    if ! [[ "$DevTemp" == "" ]]; then
      drivedevs="${drivedevs} ${i}"
    fi
  done

  # Calculate the sampling interval from the filename
  interval=`echo $1 | sed 's/.*temps-\(.*\)min.rrd/\1/'`
  if [[ "$interval" == "" ]]; then
    interval=1
  fi
  timespan=$((interval * 60))
  doubletimespan=$((timespan * 2))

  # Generate the arguments the db creation for each cpu and drive
  rrdarg=
  for (( i=0; i < ${numcpus}; i++ )); do
    rrdarg="${rrdarg} DS:cpu${i}:GAUGE:${doubletimespan}:0:150"
  done
  for i in ${drivedevs}; do
    rrdarg="${rrdarg} DS:${i}:GAUGE:${doubletimespan}:0:100"
  done

  echo "Creating $1"
  echo $rrdarg
  echo /usr/local/bin/rrdtool create $1 --step ${timespan} ${rrdarg} RRA:MAX:0.5:1:3000
  /usr/local/bin/rrdtool create $1 --step ${timespan} ${rrdarg} RRA:MAX:0.5:1:3000
fi

data=`${CWD}/temps-rrd-format.sh`
# echo $data
/usr/local/bin/rrdtool update $1 N:$data
# echo "/usr/local/bin/rrdtool update $1 N:$data"
# echo "Added: $data"
