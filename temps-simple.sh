#!/usr/local/bin/bash
# Outputs drive and cpu temps
# From the freenas.org forum, but origin unknown

if [ "$(id -u)" != "0" ]; then
  echo "Error: this script needs to be run as root (for smartctl). Try 'sudo $0'"
  exit 1
fi

/sbin/sysctl -a |egrep -E "cpu\.[0-9]+\.temp"
for i in $(/sbin/sysctl -n kern.disks | awk '{for (i=NF; i!=0 ; i--) if(match($i, '/da/')) print $i }' )
do
 DevTemp=`/usr/local/sbin/smartctl -a /dev/$i | awk '/194 Temperature_Celsius/{print $0}' | awk '{print $10 "C"}'`;
 #DevSerNum=`/usr/local/sbin/smartctl -a /dev/$i | awk '/Serial Number:/{print $0}' | awk '{print $3}'`;
 #DevName=`/usr/local/sbin/smartctl -a /dev/$i | awk '/Device Model:/{print $0}' | awk '{print $3}'`;
 echo "$i - $DevTemp $DevSerNum $DevName";
done

