#!/bin/bash
# monitor.sh SERIAL OUT: every 30 s, append one block of phone readings to OUT:
# Android's thermal status and temperatures, battery level, charge state and
# current, and the clock of one core of each CPU cluster (0 little, 4 mid,
# 8 big). Stop it by its process ID.
while true; do
  adb -s "$1" shell '
    echo "@ $(date +%s)"
    dumpsys thermalservice | grep -E "Thermal Status|Temperature\{"
    dumpsys battery | grep -E "^  (level|AC powered|USB powered|Wireless powered):"
    echo "current_now $(cat /sys/class/power_supply/battery/current_now)"
    for c in 0 4 8; do echo "cpu$c $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq)"; done
  ' >> "$2" 2>&1
  sleep 30
done
