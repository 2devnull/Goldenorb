# #!/bin/sh

ROOTER=/usr/lib/rooter

log() {
	logger -t "Quectel Data" "$@"
}

CURRMODEM=$1
COMMPORT=$2

decode_bw() {
	BW=$(echo $BW | grep -o "[0-5]\{1\}")
	case $BW in
		"0")
			BW="1.4"
			;;
		"1")
			BW="3"
			;;
		"2")
			BW="5"
			;;
		"3")
			BW="10"
			;;
		"4")
			BW="15"
			;;
		"5")
			BW="20"
			;;
	esac
}

OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "quectelinfo.gcom" "$CURRMODEM" | tr 'a-z' 'A-Z')

OX=$OX

RSRP=""
RSRQ=""
CHANNEL="-"
ECIO="-"
RSCP="-"
ECIO1=" "
RSCP1=" "
MODE="-"
MODTYPE="-"
NETMODE="-"
LBAND="-"

CSQ=$(echo $OX | grep -o "+CSQ: .\+ +QENG" | tr " " ",")
QENG=$(echo $OX" " | grep -o "+QENG: .\+ OK " | tr " " ",")


CESQ=$(echo $OX | grep -o "+CESQ: .\+ +URAT" | tr " " ",")
URAT=$(echo $OX | grep -o "+URAT: .\+ +UCGED" | tr " " ",")
UCGED=$(echo $OX" " | grep -o "+UCGED: .\+ OK " | tr " " ",")

CSQ=$(echo $CSQ | cut -d, -f2)
CSQ=$(echo $CSQ | grep -o "[0-9]\{1,2\}")

if [ $CSQ -eq "99" ]; then
	CSQ=""
fi
if [ -n $CSQ ]; then
	CSQ_PER=$(($CSQ * 100/31))"%"
	CSQ_RSSI=$((2 * CSQ - 113))" dBm"
else
	CSQ="-"
	CSQ_PER="-"
	CSQ_RSSI="-"
fi

RAT=$(echo $QENG | cut -d, -f4 | grep -o "[A-Z]\{3,5\}")

case $RAT in
	"GSM")
		MODE="GSM"
		LAC=$(echo $QENG | cut -d, -f7)
		LAC=$(echo $LAC | grep -o "[0-9A-F]\{4\}")
		CID=$(echo $QENG | cut -d, -f8)
		CID=$(echo $CID | grep -o "[0-9A-F]\{4\}")
		;;
	"WCDMA")
		MODE="UMTS"
		CHANNEL=$(echo $QENG | cut -d, -f9)
		LAC=$(echo $QENG | cut -d, -f7)
		LAC=$(echo $LAC | grep -o "[0-9A-F]\{4\}")
		CID=$(echo $QENG | cut -d, -f8)
		CID=$(echo $CID | grep -o "[0-9A-F]\{5,8\}")
		RSCP=$(echo $QENG | cut -d, -f12)
		RSCP="-"$(echo $RSCP | grep -o "[0-9]\{1,3\}")
		ECIO=$(echo $QENG | cut -d, -f13)
		ECIO="-"$(echo $ECIO | grep -o "[0-9]\{1,3\}")
		;;
	"LTE")
		MODE="LTE"
		CHANNEL=$(echo $QENG | cut -d, -f10)
		LBAND=$(echo $QENG | cut -d, -f11)
		BW=$(echo $QENG | cut -d, -f12)
		decode_bw
		BWU=$BW
		BW=$(echo $QENG | cut -d, -f13)
		decode_bw
		BWD=$BW
		if [ -z "$BWD" ]; then
			LBAND=""
		fi
		if [ -z "$BWU" ]; then
			LBAND=""
		fi
		if [ -z "$LBAND" ]; then
			LBAND="-"
		else
			LBAND="B"$LBAND" (Bandwidth $BWD MHz Down | $BWU MHz Up)"
		fi
		LAC=$(echo $QENG | cut -d, -f14)
		LAC=$(echo $LAC | grep -o "[0-9A-F]\{4\}")
		CID=$(echo $QENG | cut -d, -f8)
		CID=$(echo $CID | grep -o "[0-9A-F]\{5,8\}")
		RSRP=$(echo $QENG | cut -d, -f15)
		RSRP=$(echo $RSRP | grep -o "[0-9]\{1,3\}")
		if [ -n "$RSRP" ]; then
			RSCP="-"$RSRP" (RSRP)"
		fi
		RSRQ=$(echo $QENG | cut -d, -f16)
		RSRQ=$(echo $RSRQ | grep -o "[0-9]\{1,3\}")
		if [ -n $RSRQ ]; then
			ECIO="-"$RSRQ" (RSRQ)"
		fi
		;;
esac

if [ $RAT = "GSM" ]; then
	if [ -n "$CID" ]; then
		CID_NUM=$(printf "%d" 0x$CID)
		CID=$CID" ("$CID_NUM")"
	fi
else
	if [ -n $CID ]; then
		LCID=$(printf "%08X" 0x$CID)
		LCID_NUM=$(printf "%d" 0x$LCID)
		if [ $RAT = "LTE" ]; then
			RNC=$(printf "${LCID:1:5}")
			CID=$(printf "${LCID:6:2}")
		else
			RNC=$(printf "${LCID:1:3}")
			CID=$(printf "${LCID:4:4}")
		fi
		CID_NUM=$(printf "%d" 0x$CID)
		CID=$CID" ("$CID_NUM")"
		RNC_NUM=" ("$(printf "%d" 0x$RNC)")"
	fi
fi

if [ -n $LAC ]; then
	LAC_NUM=$(printf "%d" 0x$LAC)
	LAC=$LAC" ("$LAC_NUM")"
else
	LAC="-"
	LAC_NUM="-"
fi

echo 'CSQ="'"$CSQ"'"' > /tmp/signal$CURRMODEM.file
echo 'CSQ_PER="'"$CSQ_PER"'"' >> /tmp/signal$CURRMODEM.file
echo 'CSQ_RSSI="'"$CSQ_RSSI"'"' >> /tmp/signal$CURRMODEM.file
echo 'ECIO="'"$ECIO"'"' >> /tmp/signal$CURRMODEM.file
echo 'RSCP="'"$RSCP"'"' >> /tmp/signal$CURRMODEM.file
echo 'ECIO1="'"$ECIO1"'"' >> /tmp/signal$CURRMODEM.file
echo 'RSCP1="'"$RSCP1"'"' >> /tmp/signal$CURRMODEM.file
echo 'MODE="'"$MODE"'"' >> /tmp/signal$CURRMODEM.file
echo 'MODTYPE="'"$MODTYPE"'"' >> /tmp/signal$CURRMODEM.file
echo 'NETMODE="'"$NETMODE"'"' >> /tmp/signal$CURRMODEM.file
echo 'CHANNEL="'"$CHANNEL"'"' >> /tmp/signal$CURRMODEM.file
echo 'LBAND="'"$LBAND"'"' >> /tmp/signal$CURRMODEM.file
echo 'LAC="'"$LAC"'"' >> /tmp/signal$CURRMODEM.file
echo 'LAC_NUM="'""'"' >> /tmp/signal$CURRMODEM.file
echo 'CID="'"$CID"'"' >> /tmp/signal$CURRMODEM.file
echo 'CID_NUM="'""'"' >> /tmp/signal$CURRMODEM.file
echo 'RNC="'"$RNC"'"' >> /tmp/signal$CURRMODEM.file
echo 'RNC_NUM="'"$RNC_NUM"'"' >> /tmp/signal$CURRMODEM.file

if [ "$CSQ" = "-" ]; then
	log "$OX"
fi

WWANX=$(uci get modem.modem$CURRMODEM.interface)
OPER=$(cat /sys/class/net/$WWANX/operstate 2>/dev/null)

if [ ! $OPER ]; then
	exit 0
fi
if echo $OPER | grep -q "unknown"; then
	exit 0
fi

if echo $OPER | grep -q "down"; then
	echo "1" > "/tmp/connstat"$CURRMODEM
fi
