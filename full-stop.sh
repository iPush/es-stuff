#!/bin/bash

INVENTORY_FILE=${1:-hosts}
shift 1

[ -f "$INVENTORY_FILE" ] || {
    echo "ERROR: inventory file '$INVENTORY_FILE' must exist!" >&2
    exit 1
}

read -p "Confirm to stop hosts in $INVENTORY_FILE? [y/N]" c
[ "$c" = y -o "$c" = Y ] && {
    data_nodes=(`ansible elasticsearch.data -i $INVENTORY_FILE --list-hosts`)
    if [ ${#data_nodes[@]} = 0 ]; then
        echo "ERROR: no data nodes found!" >&2
        exit 1
    fi

    date; echo "stop ES gateway"
    ansible elasticsearch -i $INVENTORY_FILE -b --become-user admin \
        -m shell -a 'cd /tmp; d=/export/servers; f=$d/service/elasticsearch-gateway; [ ! -e $f ] || $d/runit-2.1.2/bin/sv -w 30 force-stop $f' "$@"
    sleep 2

    failed_connections=0
    n=0
    while [ -z "$NO_SYNCED_FLUSH" ]; do
        i=$(( $RANDOM % ${#data_nodes[@]} ))
        data_node=${data_nodes[$i]}
        data_node=${data_node%.es_data}
        date; echo "requesting $data_node:9200/_flush/synced ..."
        response=`curl -m 60 -s -XPOST "http://$data_node:9200/_flush/synced?pretty=true"`
        [ $? = 7 ] && {
            echo "failed to connect $data_node:9200, tried $(( ++failed_connections )) times, limit ${#data_nodes[@]} times"
            [ $failed_connections -gt ${#data_nodes[@]} ] && break
            sleep 1
            continue
        }

        echo "$response"
        failed_flushes=`echo "$response" | perl -ne '$a += $1 if /^\s*"failed"\s*:\s*(\d+)\s*,?\s*$/; END { print $a }'`
        echo "total failed flushes: $failed_flushes"
        [ "$failed_flushes" = 0 ] && break

        date; echo "wait 5s for $data_node:9200/_flush/synced ..."; echo
        sleep 5
        [ $(( ++n )) -gt ${#data_nodes[@]} ] &&
            read -p "Too many retries for /_flush/synced, force to continue? [y/N]" c &&
            [ "$c" = y -o "$c" = Y ] && break
    done
    sleep 2

    date; echo "stop all ES nodes"
    ansible elasticsearch -i $INVENTORY_FILE -b --become-user admin \
        -m shell -a 'cd /tmp; d=/export/servers; sv=$d/runit-2.1.2/bin/sv; $sv -w 120 force-stop $d/service/elasticsearch-*' \
        "$@"
}

