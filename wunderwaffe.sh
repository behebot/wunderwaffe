#!/bin/bash

usage() {
cat << EOF

This script runs some shit.

Options:
	-d DEVICE : device (Default: eth0)
	-l PERCENTAGE : loss (Default: 5%)
	-t BASE,JITTER,CORRELATION : delay (Default: 50ms, 50ms, 25% correlation value)
	-a IP_ADDRESS : address (No default, sry :( )
	-b PORT : matches a set of source ports. Up to 15 ports can be specified. Usage: [!] port[,port[,port:port...]]
	-p PERCENTAGE : percentage of bad traffic (Default: 10%)
	-n BANDWIDTH : network bandwidth (Default: 1000Mbit). Example: 100Mbit, 1024Kbit, 512Kbps
	-i : ignore loss (-l), delay (-t) and percentage of bad traffic (-p)
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
PORT=
BANDWIDTH=1000Mbit
IGNORE=

# Done with setting defaults

# Let's check if any params present

if [ "$#" -eq 0 ] 
then 
	usage
	exit 
fi

while getopts "d:l:t:a:b:p:n:ifshg" OPTION
do
	case $OPTION in
		d)
			DEVICE=$OPTARG
		;;
		l)
			if [[ $OPTARG =~ ^([0-9]{1,3}|[0-9]{1,3}\.[0-9]{1,3})$ ]]
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
		b)
			# Check it it looks like port option
			if [[ $OPTARG =~ ^(((\! )|())(([0-9]{1,5})|((([0-9]{1,5})((\,)|(:))){1,14}([0-9]{1,5}))))$ ]]
                                then
					PORT="-p tcp -m multiport --port $OPTARG"
				else
					echo "Wrong format of port (-b) option value."
                                        exit $E_WRONG_PARAM
				fi
		;;
                n)
                        if [[ $OPTARG =~ ^[0-9]{1,5}(Mbps|Kbps|Mbit|Kbit)$ ]]
                                then
                                        BANDWIDTH=$OPTARG
                                else
                                        echo "Wrong format of bandwidth (-i) option value."
                                        exit $E_WRONG_PARAM
                                fi
                ;;
		i)
			IGNORE=1
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
# Don't really flush because we have the ``-f'' option.
# $DEBUG iptables -F OUTPUT -t mangle
# $DEBUG tc qdisc del dev $DEVICE root

# Setting things up
# iptables first

$DEBUG iptables -t mangle -I OUTPUT -d $ADDRESS $PORT -m statistic --mode random --probability $PERCENTAGE -j MARK --set-mark 0x1

# tc next
# Add root qdisc
$DEBUG tc qdisc add dev $DEVICE root handle 1: htb default 10
$DEBUG tc class add dev $DEVICE parent 1: classid 1:1 htb rate 10000Mbit 

# Add class and qdisc for all traffic
$DEBUG tc class add dev $DEVICE parent 1:1 classid 1:10 htb rate 1000Mbit
$DEBUG tc qdisc add dev $DEVICE parent 1:10 handle 10: sfq perturb 10

# Add class and qdisc special for shaped traffic
$DEBUG tc class add dev $DEVICE parent 1:1 classid 1:20 htb rate $BANDWIDTH

# Ignore delay and loss packets if not -i option
if [[ $IGNORE -ne 1 ]]
	then
		$DEBUG tc qdisc add dev $DEVICE parent 1:20 handle 20: netem delay ${DELAY}ms ${JITTER}ms ${CORRELATION}% loss ${LOSS}%
		$DEBUG tc filter add dev $DEVICE protocol ip parent 1:0 prio 3 handle 1 fw classid 1:20
	else
		$DEBUG tc qdisc add dev $DEVICE parent 1:20 handle 20: sfq perturb 10
                $DEBUG tc filter add dev $DEVICE protocol ip parent 1:0 prio 3 handle 1 fw classid 1:20		
fi

$DEBUG tc filter add dev $DEVICE protocol ip parent 1:0 prio 3 handle 1 fw classid 1:20

$DEBUG echo Device: $DEVICE
if [[ $IGNORE -ne 1 ]]
        then
		$DEBUG echo Loss: $LOSS
		$DEBUG echo Timings: $TIMINGS
		$DEBUG echo Delay: $DELAY
		$DEBUG echo Jitter: $JITTER
		$DEBUG echo Correlation: $CORRELATION
		$DEBUG echo Percentage: $PERCENTAGE
fi

$DEBUG echo Address: $ADDRESS
$DEBUG echo PORT: $PORT
$DEBUG echo BANDWIDTH: $BANDWIDTH
