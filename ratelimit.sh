#!/bin/bash

: ${RULE_NAME:=ratelimit}
: ${LIMIT:=5000}        # in packets, about 20MB/s, use 3000 for about 10MB/s
: ${BURST:=5000}
: ${SUDO:=sudo}
: ${DEV:=eth0}
: ${PORT:=9208}

$SUDO iptables -L INPUT -n --line-numbers | perl -lane "print \$F[0] if \$F[1] eq \"$RULE_NAME\"" | tac | xargs -n 1 --no-run-if-empty $SUDO iptables -D INPUT

$SUDO iptables -N $RULE_NAME 2>/dev/null || $SUDO iptables -F $RULE_NAME
$SUDO iptables -A $RULE_NAME -m limit --limit $LIMIT/s --limit-burst $BURST -j ACCEPT
$SUDO iptables -A $RULE_NAME -j DROP

$SUDO iptables -A INPUT -i $DEV -p tcp --dport $PORT -j $RULE_NAME

$SUDO iptables -L -n --line-numbers

