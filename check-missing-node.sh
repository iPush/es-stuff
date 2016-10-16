#!/bin/bash

INVENTORY_FILE=${1:-$INVENTORY_FILE}
INVENTORY_FILE=${INVENTORY_FILE:-hosts}
ES=${2:-$ES}
ES=${ES:-localhost:9200}

[ -f "$INVENTORY_FILE" ] || {
    echo "ERROR: inventory file '$INVENTORY_FILE' must exist!" >&2
    exit 1
}

nodes=`curl -m 60 -s $ES/_cat/nodes?h=name`
[ $? = 0 -a "$nodes" ] || {
    echo "ERROR: failed to query $ES/_cat/nodes?h=name"
    exit 1
}

master_nodes=`echo "$nodes" | perl -lne 'print $1 if /master-(\S+)/' | sort`
data_nodes=`echo "$nodes" | perl -lne 'print $1 if /data-(\S+)/' | sort`
gateway_nodes=`echo "$nodes" | perl -lne 'print $1 if /gateway-(\S+)/' | sort`

diff -U0 --label "expected-master-nodes" --label "actual-master-nodes" \
    <( ansible elasticsearch.master -i $INVENTORY_FILE --list-hosts | sed -e 's/\s//g' -e 's/\.es_master//' | sort ) \
    <( echo "$master_nodes" ) | sed -e 's/^-\([0-9]\)/- \1/' | grep -v ^@@

diff -U0 --label "expected-gateway-nodes" --label "actual-gateway-nodes" \
    <( ansible elasticsearch.gateway -i $INVENTORY_FILE --list-hosts | sed -e 's/\s//g' -e 's/\.es_gateway//' | sort ) \
    <( echo "$gateway_nodes" ) | sed -e 's/^-\([0-9]\)/- \1/' | grep -v ^@@

diff -U0 --label "expected-data-nodes" --label "actual-data-nodes" \
    <( ansible elasticsearch.data -i $INVENTORY_FILE --list-hosts | sed -e 's/\s//g' -e 's/\.es_data//' | sort ) \
    <( echo "$data_nodes" ) | sed -e 's/^-\([0-9]\)/- \1/' | grep -v ^@@

