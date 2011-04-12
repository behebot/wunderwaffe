#!/bin/bash

usage() {
cat << EOF

This script runs some shit.

Options:
	-d DEVICE : device (Default: eth0)
	-l PERCENTAGE : loss (Default: 5%)
	-t BASE,JITTER,CORRELATION : delay (Default: 50ms, 50ms, 25% correlation value)
	-a IP_ADDRESS : address (No default, sry :( )
	-p PERCENTAGE : percentage of bad traffic (Default: 10%)
	-f : flush current rules
	-s : show current rules status
	-g : debug mode. Do nothing, print commands only.
	-h : Help! I need somebody!

EOF
}

# Setting defaults

E_WRONG_PARAM=43

DEVICE=eth0
LOSS=5
TIMINGS=50,50,25
PERCENTAGE=10
ADDRESS=
DEBUG=

# Done with setting defaults

# Let's check if any params present

if [ "$#" -eq 0 ] 
then 
	usage
	exit 
fi

while getopts "d:l:t:a:p:fshg" OPTION
do
	case $OPTION in
		d)
			DEVICE=$OPTARG
		;;
		l)
			if [[ $OPTARG =~ ^[0-9]{1,3}$ ]]
				then
					LOSS=$OPTARG
				else
					echo "Wrong format of loss (-l) option value."
					exit $E_WRONG_PARAM
			fi
		;;
		t)
			if [[ $OPTARG =~ ^[0-9]{1,4},[0-9]{1,4},[0-9]{1,3}$ ]]
				then
					TIMINGS=$OPTARG
				else
					echo "Wrong format of timings (-t) option value."
					exit $E_WRONG_PARAM
			fi
		;;
		p)
			if [[ $OPTARG =~ ^[0-9]{1,3}$ ]]
				then
					PERCENTAGE=$OPTARG
				else
					echo "Wrong format of percentage (-p) option value."
					exit $E_WRONG_PARAM
			fi
		;;
		a)
			ADDRESS=$OPTARG
			# Check if it looks like IP
			if [[ $OPTARG =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]
				then
					ADDRESS=$OPTARG
				else
					echo "Looks like IP_ADDRESS you've provided is bad. Check it out again: $ADDRESS"
					exit $E_WRONG_PARAM
				fi
		;;
		s)
			echo iptables:
			iptables -L OUTPUT -t mangle -n
			echo
			echo Classes:
			tc class ls dev $DEVICE
			echo
			echo "Disciplines (with some raw stat):"
			tc -s qdisc ls dev $DEVICE
			echo
			echo Filters:
			tc filter ls dev $DEVICE
			echo
			exit 0
		;;
		f)
			# Flushing iptables
			iptables -F OUTPUT -t mangle
			# Flushing tc
			tc qdisc del dev $DEVICE root
			exit 0
		;;
		h)
			usage
			exit 0
		;;
		g)
			DEBUG=echo
		;;
		?)
			usage
			exit $E_WRONG_PARAM
		;;
	esac
done

# Parse TIMINGS
DELAY=`echo $TIMINGS | cut -d',' -f 1`
JITTER=`echo $TIMINGS | cut -d',' -f 2`
CORRELATION=`echo $TIMINGS | cut -d',' -f 3`
PERCENTAGE=`echo "scale=2; $PERCENTAGE / 100" | bc -l`

# Flush 'em all first
$DEBUG iptables -F OUTPUT -t mangle
$DEBUG tc qdisc del dev $DEVICE root

# Setting things up
# iptables first

$DEBUG iptables -t mangle -I OUTPUT -d $ADDRESS -m statistic --mode random --probability $PERCENTAGE -j MARK --set-mark 0x1

# tc next
$DEBUG tc qdisc add dev $DEVICE root handle 1: prio
$DEBUG tc qdisc add dev $DEVICE parent 1:1 handle 10: netem delay ${DELAY}ms ${JITTER}ms ${CORRELATION}% loss ${LOSS}%
$DEBUG tc filter add dev $DEVICE protocol ip parent 1:0 prio 3 handle 1 fw flowid 10:1

$DEBUG echo Device: $DEVICE
$DEBUG echo Loss: $LOSS
$DEBUG echo Timings: $TIMINGS
$DEBUG echo Delay: $DELAY
$DEBUG echo Jitter: $JITTER
$DEBUG echo Correlation: $CORRELATION
$DEBUG echo Percentage: $PERCENTAGE
$DEBUG echo Address: $ADDRESS
