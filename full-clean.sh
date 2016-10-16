#!/bin/bash

INVENTORY_FILE=${1:-hosts}
shift 1

[ -f "$INVENTORY_FILE" ] || {
    echo "ERROR: inventory file '$INVENTORY_FILE' must exist!" >&2
    exit 1
}

read -p "Confirm to clean hosts in $INVENTORY_FILE? [y/N]" c
[ "$c" = y -o "$c" = Y ] &&
    ansible elasticsearch -i $INVENTORY_FILE -b --become-user admin -f 200 -m shell -a \
        '/bin/rm -rf /export/Data/elasticsearch-*/* /export/Logs/elasticsearch-*/* /export/tmp/elasticsearch-*/* /data*/Data/elasticsearch-*/*' "$@"

