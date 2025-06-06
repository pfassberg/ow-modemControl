#!/bin/bash
#
# Depends on following packages:
# - bash
# - coreutils-stty
# - jq
# apk update
# apk add bash coreutils-stty jq
#
# Supports 6005:2c7c Qeuctel
# 

trap ctrl_c INT

function ctrl_c() {
  echo "** Trapped CTRL-C"
  echo "Exiting"
  sleep 1
  exit 3
}

export FIFO="/tmp/at"


# First try to find first supported modem, skip the rest

VP=""
SPEED="115200"
for sysfsprod in `ls /sys/bus/usb/devices/*/product`
do
	device=`dirname $sysfsprod`
	VP=`cat $device/idProduct`:`cat $device/idVendor`
	if [ "$VP" = "6005:2c7c" ]; then
		DEVTTY="/dev/"`ls $device/*:*/ep_86/../*/tty/`
		SPEED="9600"
		break
	fi
done

if [ "$VP" = "" ]; then
	echo "Didn't find any supported modems"
	sleep 1
	exit 1
fi

echo "Found supported modem!"
echo "VID:PID:" $VP
echo "AT device:" $DEVTTY
echo "AT speed: " $SPEED

rm -f $FIFO
mkfifo $FIFO

# set up modem device to translate outgoing \n into \r\n
stty -F $DEVTTY $SPEED -echo igncr icanon onlcr

# Open modem for reading and writing
exec 5<$DEVTTY
exec 6>$DEVTTY

# echo $2 >&6

# Remove the echo and the blank line
# read -t 1 <&5
# read -t 1 <&5


# Start background process for handling ubus input (send to named pipe for now)
(
ubus -S listen sendModem |
(
while read -r line
do
        echo "line:" $line
        cmd=`echo ${line} | jq -r .sendModem.cmd`
	#echo "cmd:" $cmd
        #echo "FIFO:" $FIFO
        if [ "$cmd" == "quit" ]; then
             break
        fi
	echo $cmd >$FIFO
done

echo "Quitting"
sleep 1
kill $$
exit 0
)
) &


# Start background process for configuring the modem (if any)
(
  if [ "$VP" = "6005:2c7c" ];	# Qeuctel EC200A
	then
		# Ask for Manufacturer name
		sleep 1; echo "AT+CGMI" >$FIFO
		# Ask for Model name
		sleep 1; echo "AT+CGMM" >$FIFO
		# Ask for IMEI
		sleep 1; echo "AT+CGSN" >$FIFO
		# Ask for IMSI
		sleep 1; echo "AT+CIMI" >$FIFO
		# Configure URCs
		sleep 1; echo "AT+QINDCFG=\"csq\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"datastatus\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"mode\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"smsfull\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"smsincoming\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"act\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"service\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"call\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"message\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"sqi\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"ring\",1,0" >$FIFO
		sleep 1; echo "AT+QINDCFG=\"nocarrier\",1,0" >$FIFO
		sleep 1; echo "AT+CREG=2" >$FIFO
		# Ask for registration status
		sleep 1; echo "AT+CREG?" >$FIFO
		# Put the modem in autoconnect ECM mode
		sleep 1; echo "AT+QNETDEVCTL=3,1" >$FIFO
		# Ask for modem mode
		sleep 1; echo "AT+QNETDEVCTL?" >$FIFO
	fi
) &

FLAG="GO"

# Loop until quitted
while [ "${FLAG}" == "GO" ]; do
# READ FROM FIFO, send to modem
	#echo "read from fifo"
	line=""
	read -t 0.1 line <>$FIFO
	if [ "${line}" == "quit" ];
	then
		FLAG="EXIT"
		line=""
	fi
	if [ -n "$line" ];
	then	
		echo "Got fifo: " $line
		echo $line >&6
	fi
	if [ "${line}" == "quit" ];
	then
		FLAG="EXIT"
	fi
# TODO: Wait for response instead of handling everything as URCs

# READ FROM MODEM (waiting for answer or URC)
	#echo "read from modem"
	REC=""
	read -t 0.1 REC <&5
	ERR=$?
	if [ $ERR -lt 128 ]; # Not timed out
	then	
		echo "Rec:" "x"$REC"x"
		STR='"'${REC//\"/\\\"}'"'
		echo "STR:" "x"$STR"x"
		data=`jq -n --argjson str "${STR}" '{str: $str}'`
		echo $data
		#data="'"$data"'"
		echo $data
		ubus send recModem "$data"
	fi
done

# Close the connections
exec 5<&-
exec 6>&-

ubus send sendModem '{"cmd":"quit"}'

echo "Quitted"
