# ow-modemControl
OpenWrt Modem Control

This script controls the modem and the LEDs (radio access technology and rssi).

It can also be used to send arbitrary command to the modem using ubus events.

It uses a named pipe (fifo) to communicate between the different subprocesses.  it activates URCs thet will be used to steer the LEDs.

If you use this script please don't talk directly to the modem AT port (there is usually anoyther "modem" port that this script won't control.

Modem Manager can't be used in parallell for the same modem.

Currently this script supports Asus RT-AX56 (Fibocom modem) and Teltonica RUT200 (Quectel modem).

