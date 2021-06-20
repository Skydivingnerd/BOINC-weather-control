#!/bin/bash
# This script controls the local BOINC clients to balance CPU and GPU computing heat load for the
# house with the outside air temp. This script requires the 'weather-util' package to be
# installed.

##### Configuration Settings #####
# BOINC Hosts to control. List DNS names with one space between host entries.
BOINC_HOST="amaranth rimbeth trebeth joruth keranth"

# BOINC RPC password
BOINC_PASSWD="boinc"

# Define temperature bands for controlling CPU and GPU computing. All temperatures are a two digit, with one decimal place,
# number with the decimal point removed as bash does not work with anything other than whole numbers. For example, 81.5 degrees
# is 815 or 92.7 degrees is 927.
# Weather temperature bands
COOL_WEATHER_MAX="820"

WARM_WEATHER_MIN="820"
WARM_WEATHER_MAX="880"

HOT_WEATHER_MIN="880"
##### EndConfiguration Settings #####

##### Functions #####

# Logging to syslog
log() {
logger -t boinc-weather-control "${MESSAGE}"
}
##### End Functions #####


# Obtain weather data from the weather-util app
OUTSIDE_TEMP=$(weather fips5163093651 --headers=Temperature --no-cache | grep Temperature | awk '{gsub("[.]", "", $2); print $2}')
WEATHER_LAST_UPDATE_TIME=$(weather fips5163093651 | sed -n '2p' | awk '{print $1,$2,$3,$4,$5,$7,$8,$9}')
wait
if [[ ${?} -eq "0" ]]
        then
        MESSAGE="Reported outside temperature is ${OUTSIDE_TEMP} F : ${WEATHER_LAST_UPDATE_TIME}"
        log
        else
        MESSAGE="Unable to obtain weather data. Exiting"
        log
        exit 1
fi

# The variables below manipulate the BOINC client Activity settings for all projects for the CPU and GPU resources.
# Those options are "Run Always", "Run based on preferences", and "Suspend" for CPU resources and "Use GPU always",
# "Use GPU based on preferences", and "Suspend GPU" for GPU resources. The commands that set these run modes from
# the CLI are "always", "auto", and "never" for the '--set_run_mode and --set_gpu_mode' options for boinccmd.

# Set Intended Run Status depending on temperature
if [[ ${OUTSIDE_TEMP} -le ${COOL_WEATHER_MAX} ]]
        then
        INTENDED_CPU_STATUS="auto"
        INTENDED_GPU_STATUS="auto"
        WEATHER_STATUS="The weather is cool. Enabling CPU and GPU computing."
        elif [[ ${OUTSIDE_TEMP} -gt ${WARM_WEATHER_MIN} && ${OUTSIDE_TEMP} -le ${WARM_WEATHER_MAX} ]]
        then
        INTENDED_CPU_STATUS="auto"
        INTENDED_GPU_STATUS="never"
        WEATHER_STATUS="Weather is warm. Enabling CPU and disabling GPU computing."
        elif [[ ${OUTSIDE_TEMP} -gt ${HOT_WEATHER_MIN} ]]
        then
        INTENDED_CPU_STATUS="never"
        INTENDED_GPU_STATUS="never"
        WEATHER_STATUS="Weather is hot. Disabling CPU and GPU computing."
fi

# Translate CPU run status between the boinccmd setting and what the BOINC client reports back.
case "${INTENDED_CPU_STATUS}" in
        always)
        TRANSLATED_CPU_STATUS="always"
        ;;
        auto)
        TRANSLATED_CPU_STATUS="according"
        ;;
        never)
        TRANSLATED_CPU_STATUS="never"
        ;;
esac

# Translate GPU run status between the boinccmd setting and what the BOINC client reports back.
case "${INTENDED_GPU_STATUS}" in
        always)
        TRANSLATED_GPU_STATUS="always"
        ;;
        auto)
        TRANSLATED_GPU_STATUS="according"
        ;;
        never)
        TRANSLATED_GPU_STATUS="never"
        ;;
esac

# Loop for each BOINC host
for CLIENT in ${BOINC_HOST}
do

# Check host is online
boinccmd --host ${CLIENT} --passwd ${BOINC_PASSWD} --get_cc_status &> /dev/null
if [[ ${?} -eq "0" ]]
        then

# Get the current running status of the BOINC host. awk and sed parse out the single word status to use in the script.
        CLIENT_CPU_STATUS=$(boinccmd --host ${CLIENT} --passwd ${BOINC_PASSWD} --get_cc_status | awk '/current mode/ {print $3}' | sed -n '1p')
        CLIENT_GPU_STATUS=$(boinccmd --host ${CLIENT} --passwd ${BOINC_PASSWD} --get_cc_status | awk '/current mode/ {print $3}' | sed -n '2p')

# Validate CPU run state and set if not already running in the intended state
        if [[ ${CLIENT_CPU_STATUS} != "${TRANSLATED_CPU_STATUS}" ]]
                then
                boinccmd --host ${CLIENT} --passwd ${BOINC_PASSWD} --set_run_mode ${INTENDED_CPU_STATUS}
                if [[ ${?} -eq "0" ]]
                        then
                        CLIENT_CPU_STATUS=$(boinccmd --host ${CLIENT} --passwd ${BOINC_PASSWD} --get_cc_status | awk '/current mode/ {print $3}' | sed -n '1p')
                        MESSAGE="${CLIENT}: Changing BOINC configuration  -  CPU:${CLIENT_CPU_STATUS}"
                        log
                        else
                        MESSAGE="${CLIENT}: Client update failed."
                        log
                fi

        fi

# Validate GPU run state and set if not already running in the intended state
        if [[ ${CLIENT_GPU_STATUS} != "${TRANSLATED_GPU_STATUS}" ]]
                then
                boinccmd --host ${CLIENT} --passwd ${BOINC_PASSWD} --set_gpu_mode ${INTENDED_GPU_STATUS}
                if [[ ${?} -eq "0" ]]
                        then
                        CLIENT_GPU_STATUS=$(boinccmd --host ${CLIENT} --passwd ${BOINC_PASSWD} --get_cc_status | awk '/current mode/ {print $3}' | sed -n '2p')
                        MESSAGE="${CLIENT}: Changing BOINC configuration  -  GPU:${CLIENT_GPU_STATUS}"
                        log
                        else
                        MESSAGE="${CLIENT}: Client update failed."
                        log
                fi
        fi

# If BOINC Client cannot be contacted. Check if host is online or not.
else
MESSAGE="${CLIENT}: Unable to connect to BOINC client."
log
PING -c3 -i2 ${CLIENT} &> /dev/null
wait
        case "${?}" in
                0)
                MESSAGE="${CLIENT}: Host appears alive. Check BOINC Client status."
                log
                ;;
                1)
                MESSAGE="${CLIENT}: Host appears offline. Check host is online and functioning."
                log
                ;;
                ?)
                MESSAGE="${CLIENT}: Ping check failed. Host status unknown."
                log
                ;;
        esac

fi
done
exit 0
