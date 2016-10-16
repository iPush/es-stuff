#!/bin/bash

: ${RULE_NAME:=whitelist}
: ${SUDO:=sudo}
: ${DEV:=eth0}
: ${DPORTS:=9200,9300,9208,9308,9218,9318}

HOST_FILE=${1:?}

$SUDO iptables -L INPUT -n --line-numbers | perl -lane "print \$F[0] if \$F[1] eq \"$RULE_NAME\"" | tac | xargs -n 1 --no-run-if-empty $SUDO iptables -D INPUT

$SUDO iptables -N $RULE_NAME 2>/dev/null || $SUDO iptables -F $RULE_NAME

while read line; do
   [[ -n "$line" ]] || break;
   $SUDO iptables -A $RULE_NAME -m iprange --src-range "$line" -j RETURN
done < "$HOST_FILE"

$SUDO iptables -A $RULE_NAME -j REJECT

$SUDO iptables -I INPUT -i $DEV -p tcp -m multiport --dports $DPORTS -j $RULE_NAME

$SUDO iptables -L -n --line-numbers
