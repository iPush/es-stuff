#!/bin/bash

INVENTORY_FILE=${1:-hosts}
shift 1

[ -f "$INVENTORY_FILE" ] || {
    echo "ERROR: inventory file '$INVENTORY_FILE' must exist!" >&2
    exit 1
}

ansible elasticsearch -i $INVENTORY_FILE -b --become-user admin -f 200 -m shell -a \
    'cd /tmp; /export/servers/runit-2.1.2/bin/sv status /export/servers/service/elasticsearch-*' "$@"

