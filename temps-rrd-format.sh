#!/usr/local/bin/bash
#####
# This script gathers and outputs the CPU and drive
# temperatures in a format rrdtool can consume.
# Author: Seren Thompson
# Date: 2016-04-02
#####

# quit on errors
set -o errexit
# error on unset variables
set -o nounset

if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0'"
  exit 1
fi

sep=':'

# Get CPU ids
numcpus=$(/sbin/sysctl -n hw.ncpu)
# Get drive device names
drivedevs=
for i in $(/sbin/sysctl -n kern.disks | awk '{for (i=NF; i!=0 ; i--) if(match($i, '/ada/')) print $i }' ); do
  drivedevs="${drivedevs} ${i}"
done

# Get CPU temperatures
data=
for (( i=0; i < ${numcpus}; i++ )); do
  t=`/sbin/sysctl -n dev.cpu.$i.temperature`
  data=${data}${sep}${t%.*}  # Append the temperature to the data string, removing anything after the decimal
done
# Get drive temperatures
for i in ${drivedevs}; do
 DevTemp=`/usr/local/sbin/smartctl -a /dev/$i | grep '194 *Temperature_Celsius' | awk '{print $10}'`;
 data="${data}${sep}${DevTemp}"
done

# remove the C's from the temps
data=`echo ${data} | tr -d 'C'`

# strip the unnecessary leading colon
echo ${data#?}

