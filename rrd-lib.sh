######################################
# Common
######################################

# AWK program for extracting temperature data
# Get the temperature (column 10) from lines begining with SMART attribute
# 190 or 194, giving precedence to 190 in the case that both exist. If neither
# one exists, output nothing.
GETTEMP=$(mktemp)
cat <<'EOF' > $GETTEMP
BEGIN         { attr=0; temp=-99 }
$1 ~ /19[04]/ { if (attr != "194") { attr=$1; temp=$10 } }
END           { if (temp != "-99") print temp }
EOF
trap "{ rm $GETTEMP; }" EXIT

get_devices () {
  # Get CPU count
  case "${PLATFORM}" in
    esxi)
      [ -n "$verbose" ] && echo "Platform is set to '${PLATFORM}'. Attempting to retrieve the list of CPUs using ipmitool with username '${USERNAME} and ip ${BMC_ADDRESS}..."
      numcpus=$(ipmitool -I lanplus -H "${BMC_ADDRESS}" -U "${USERNAME}" -f /root/.ipmi sdr elist all | grep -c -i "cpu.*temp")
      ;;
    *)
      numcpus=$(/sbin/sysctl -n hw.ncpu)
  esac

  # Get drive device names
  drivedevs=
  for i in $(/sbin/sysctl -n kern.disks | awk '{ for (i=NF; i>1; i--) printf("%s ",$i); print $1; }'); do
    # Sanity check that the drive will return a temperature (we don't want to include non-SMART usb devices)
    DevTemp=$(/usr/local/sbin/smartctl -a /dev/"${i}" | awk -f $GETTEMP)
    if [ -n "$DevTemp" ]; then
      drivedevs="${drivedevs} ${i}"
      [ -n "$verbose" ] && echo "drivedevs: ${drivedevs}"
    fi
  done
  [ -n "$verbose" ] && echo "numcpus: ${numcpus}"
  export numcpus drivedevs
}

get_temperatures () {
  # Get CPU temperatures
  sep=':'
  data=
  # Get CPU temperatures
  for (( i=0; i < ${numcpus}; i++ )); do
    case "${PLATFORM}" in
      esxi)
        [ -n "$verbose" ] && echo "Platform is set to '${PLATFORM}'. Attempting to retrieve CPU$((i+1)) temperatures using ipmitool with username '${USERNAME} and ip ${BMC_ADDRESS}..."
        t=$(ipmitool -I lanplus -H "${BMC_ADDRESS}" -U "${USERNAME}" -f /root/.ipmi sdr elist | sed -Ene 's/^CPU[^ ]+ +Temp +\| .* ([^ ]+) degrees C/\1/p' | sed -n "$((i+1))p")
        ;;
      *)
        t=$(/sbin/sysctl -n dev.cpu.$i.temperature)
    esac
    data=${data}${sep}${t%.*}  # Append the temperature to the data string, removing anything after the decimal
  done
  # Get drive temperatures
  for i in ${drivedevs}; do
    DevTemp=$(/usr/local/sbin/smartctl -a /dev/$i | awk -f $GETTEMP)
    if [ -n "$DevTemp" ]; then
      data="${data}${sep}${DevTemp}"
    fi
  done
  [ -n "$verbose" ] && echo "Raw data: ${data}"
  export data
}

######################################
# rrd.sh
######################################

# Checks that a file is writeable
func_test_writable () {
  # If it doesn't exist, exit with a non-error code
  if ! [ -e "${1}" ]; then
    echo "'${1}' doesn't exist"
    return 0
  fi
  # Exit if the data file is something other than a file for safety and security
  if [ -e "${1}" ] && ! [ -f "${1}" ]; then
    echo "'${1}' exists, but isn't a file."
    exit 1
  fi
  {  # try
    touch "${1}"
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
    rm -f "/tmp/chmodtest_${TEMPFILENAME}"
    echo "Permissions in /tmp:"
    ls -lL /tmp | cut -d' ' -f 1
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
    rm -f "${dir}/chmodtest_${TEMPFILENAME}"
    echo "Permissions in ${dir}:"
    ls -lL "${dir}" | cut -d' ' -f 1
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
  gauges_in_file=$(${RRDTOOL} info "${datafile}" | grep -c 'type = "GAUGE"')
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

  echo "Script version: ${SCRIPTVERSION}"

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
  if ! func_check_file_is_rrd "${datafile}"; then
    echo "Test failed. '${datafile}' is not a valid rrd file. You may need to delete it and run this script again"
    exit 1
  fi

  echo "Daignostics didn't find anything wrong."
}

######################################
# rrd-graph.sh
######################################

write_graph_to_disk () {
  /usr/local/bin/rrdtool graph "${CWD}/${outputprefix}-${outputfilename}.png" \
  -w 785 -h 151 -a PNG \
  --start end-"${timespan}" --end now \
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
  --rigid > /dev/null
  # "HRULE:${SAFETEMPLINE}#FF0000:Max safe temp - ${SAFETEMPLINE}"
  # "HRULE:${SAFETEMPLINE}#FF0000:Max-${SAFETEMPLINE}"
}
