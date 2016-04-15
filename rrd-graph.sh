#!/usr/local/bin/bash
#####
# Given an rrd file of the system's cpu and drive temperatures
# as input, this script uses rrdtool to graph the data.
# The input files must named as such: temps-Xmin.rdd
# where X is the minute interval between readings.
# ex: "temps-10min.rrd" would contain readings every 10 minutes
# Author: Seren Thompson
# Date: 2016-04-02
#####

# quit on errors
set -o errexit
# error on unset variables
set -o nounset

if [ -z $1 ]; then
  echo "Error: you need to give an input filename as an argument. Ex:"
  echo " $0 temps-Xmin.rrd"
  echo
  echo "Exiting..."
  exit 1
fi


######################################
# Script variables
######################################
MAXGRAPHTEMP=50
MINGRAPHTEMP=20
SAFETEMPLINE=40

# # Different strokes for different folks
# LINECOLORS=( 0000FF 4573A7 AA4644 89A54E 71588F 006060 0f4880 )
# LINECOLORS=( 0000FF FF4A46 008941 006FA6 A30059 FFDBE5 7A4900 0000A6 63FFAC B79762 004D43 8FB0FF 997D87 )
LINECOLORS=( 1CE6FF FF34FF FF4A46 008941 A30059 7A4900 63FFAC B79762 004D43 8FB0FF 997D87 000000 )

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# rrdtool database file
datafile=$1
outputprefix=${datafile%.*}  # strip extension
outputprefix=${outputprefix##*/}   # extract filename
interval=`echo $datafile | sed 's/.*temps-\(.*\)min.rrd/\1/'`  # extract minute number

# Get CPU numbers
numcpus=$(/sbin/sysctl -n hw.ncpu)
# Get drive device names
drivedevs=
for i in $(/sbin/sysctl -n kern.disks | awk '{for (i=NF; i!=0 ; i--) if(match($i, '/ada/')) print $i }' ); do
  drivedevs="${drivedevs} ${i}"
done

title="Temps"


######################################
# Script functions
######################################
write_graph_to_disk ()
{
  /usr/local/bin/rrdtool graph ${BASEDIR}/${outputprefix}-${outputfilename}.png \
  -w 785 -h 151 -a PNG \
  --slope-mode \
  --start end-${timespan} --end now \
  --font DEFAULT:7: \
  --title "${title}" \
  --watermark "`date`" \
  --vertical-label "Celcius" \
  --right-axis-label "Celcius" \
  ${guidrule} \
  ${defsandlines} \
  --right-axis 1:0 \
  --alt-autoscale \
  --lower-limit ${MINGRAPHTEMP} \
  --upper-limit ${MAXGRAPHTEMP} \
  --rigid
  # "HRULE:${SAFETEMPLINE}#FF0000:Max safe temp - ${SAFETEMPLINE}"
  # "HRULE:${SAFETEMPLINE}#FF0000:Max-${SAFETEMPLINE}"
}



######################################
# Main
######################################
# seconds in:
# a day:   86400
# 2 days:  172800
# a week:  604800
# 30 days: 2592000

interval=`echo ${datafile} | sed 's/.*temps-\(.*\)min.rrd/\1/'`
if [[ "$interval" == "" ]]; then
  interval=1
fi
timespan=$((interval * 86400))

# # Graph all cpus and drives together
# outputfilename=everything
# title="Temperature: All CPUs and Drives, ${interval} minute interval"
# guidrule=
# defsandlines=
# for (( i=0; i < ${numcpus}; i++ )); do
#   defsandlines="${defsandlines} DEF:cpu${i}=${datafile}:cpu${i}:MAX LINE1:cpu${i}${LINECOLORS[$i]}:\"cpu${i}\""
# done
# for i in ${drivedevs}; do
#   defsandlines="${defsandlines} DEF:${i}=${datafile}:${i}:MAX LINE1:${i}${LINECOLORS[$i]}:\"${i}\""
# done
# write_graph_to_disk

# Output a combined graph of all cpus
outputfilename=cpus
defsandlines=
title="Temperature: All CPUs, ${interval} minute interval"
guidrule=
for (( i=0; i < ${numcpus}; i++ )); do
  defsandlines="${defsandlines} DEF:cpu${i}=${datafile}:cpu${i}:MAX LINE1:cpu${i}#${LINECOLORS[$i]}:cpu${i}"
done
write_graph_to_disk

# Output a combined graph of all drives
outputfilename=drives
defsandlines=
title="Temperature: All Drives, ${interval} minute interval"
guidrule=HRULE:${SAFETEMPLINE}#FF0000:Max-safe-temp:dashes
for i in ${drivedevs}; do
  drivenum=${i#ada*}
  defsandlines="${defsandlines} DEF:${i}=${datafile}:${i}:MAX LINE1:${i}#${LINECOLORS[$drivenum]}:${i}"
done
write_graph_to_disk

# # Output graphs of each cpu
# for (( i=0; i < ${numcpus}; i++ )); do
#   defsandlines="DEF:cpu${i}=${datafile}:cpu${i}:MAX LINE1:cpu${i}${LINECOLORS[$i]}:\"cpu${i}\""
#   outputfilename=cpu${i}
#   title="Temperature: CPU ${i}, ${interval} minute interval"
#   guidrule=
#   write_graph_to_disk
# done

# # Output graphs of each drive
# for i in ${drivedevs}; do
#   drivenum=${i#ada*}
#   defsandlines="DEF:${i}=${datafile}:${i}:MAX LINE1:${i}${LINECOLORS[$drivenum]}:\"${i}\""
#   outputfilename=drive-${i}
#   guidrule="HRULE:${SAFETEMPLINE}#FF0000"
#   title="Temperature: Drive ${i}, ${interval} minute interval"
#   write_graph_to_disk
# done

