#!/bin/bash

set -o noglob

ES=${1:-$ES}
ES=${ES:-localhost:9200}
INDEX=${2:-$INDEX}

[ "$INDEX" ] || {
    echo "Usage: $0 ES INDEX" >&2
    exit 1
}

shards_response=`curl -m 60 -s $ES/_cat/shards/$INDEX/?h=index,shard,state,node`
nodes=`echo "$shards_response" | grep -v UNASSIGNED | awk '{print $4}' | sort -u`

echo "$shards_response" | grep UNASSIGNED | sort -u |
    while read index shard other_fields; do
        echo "fixing $index shard $shard ..."
        candidates=`curl -m 60 -s $ES/_cat/shards?h=node,state | grep -v UNASSIGNED | awk '{print $1}' | sort | uniq -c | sort -k1,1 -n | awk '{print $2}'`
        [ "$candidates" ] || {
            echo "ERROR: failed to pick least used node for $index shard $shard"
            continue
        }

        allocated=false
        for node in $candidates; do
            echo "$nodes" | grep -q "^$node$" && continue

            file=/tmp/fix-${index}_${shard}-`date +%s`.log
            echo -n "trying to allocate $index shard $shard to node $node, log file at $file..."

            curl -m 300 -s -XPOST $ES/_cluster/reroute --data-binary \
                "{\"commands\": [{\"allocate\": {\"index\": \"$index\", \"shard\": \"$shard\", \"node\": \"$node\", \"allow_primary\": true}}]}" |
            tee $file | grep -q '"acknowledged"\s*:\s*true' &&
                    nodes="$nodes"$'\n'"$node" &&
                    allocated=true &&
                    echo " allocated." &&
                    break
            echo
        done

        [ $allocated = true ] || echo "ERROR: failed to allocate $index shard $shard."
    done

