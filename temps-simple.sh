#!/usr/local/bin/bash
# Outputs drive and cpu temps
# From the freenas.org forum, but origin unknown

for i in $(/sbin/sysctl -n kern.disks | awk '{for (i=NF; i!=0 ; i--) if(match($i, '/ada/')) print $i }' );
do
 DevTemp=`sudo /usr/local/sbin/smartctl -a /dev/$i | awk '/Temperature_Celsius/{print $0}' | awk '{print $10 "C"}'`;
 #DevSerNum=`sudo /usr/local/sbin/smartctl -a /dev/$i | awk '/Serial Number:/{print $0}' | awk '{print $3}'`;
 #DevName=`sudo /usr/local/sbin/smartctl -a /dev/$i | awk '/Device Model:/{print $0}' | awk '{print $3}'`;
 echo "$i - $DevTemp $DevSerNum $DevName";
done
/sbin/sysctl -a |egrep -E "cpu\.[0-9]+\.temp"

