#!/bin/bash

ES=${1:-$ES}
ES=${ES:-localhost:9200}
NODE=${2:-$NODE}
: ${PREFIX=data-}
: ${TYPE:=persistent}

perl -MJSON -e 1 2>/dev/null || {
    echo "ERROR: perl-JSON isn't installed."
    exit 1
}

[ "$NODE" ] || {
    echo "Usage: $0 ES NODE" >&2
    exit 1
}

[ "$TYPE" = persistent -o "$TYPE" = transient ] || {
    echo "ERROR: \$TYPE must be 'persistent' or 'transient'"
    exit 1
}

[ "$NODE" != "${NODE#$PREFIX}" ] || NODE="${PREFIX}$NODE"

read -p "Confirm to ${TYPE}ly enable $NODE for $ES? [y/N]" c
[ "$c" = y -o "$c" = Y ] || exit 1

echo "requesting $ES/_cluster/settings?pretty ..."
response=`curl -m 60 -s $ES/_cluster/settings?pretty`
[ $? = 0 -a "$response" ] && echo "$response" || {
    echo "ERROR: failed to query $ES/_cluster/settings"
    exit 1
}

nodes=`perl -MJSON -e '
        $h = decode_json($ARGV[0]);
        exit 1 unless $h && exists $h->{$ARGV[1]};
        print $h->{$ARGV[1]}{"cluster"}{"routing"}{"allocation"}{"exclude"}{"_name"}' "$response" $TYPE 2>/dev/null`
[ $? = 0 ] || {
    echo "ERROR: failed to query $ES/_cluster/settings"
    exit 1
}

echo
echo "old excluded nodes: $nodes"

if perl -e 'exit(scalar(grep $_ eq $ARGV[1], split(/\s*,\s*/, $ARGV[0])) > 0 ? 0 : 1)' "$nodes" "$NODE"; then
    nodes=`perl -e '%h = map { $_, 1 } split(/\s*,\s*/, $ARGV[0]); delete $h{$ARGV[1]}; print join(",", sort keys %h)' "$nodes" "$NODE"`

    echo "new excluded nodes: $nodes"

    curl -m 60 -s -XPUT $ES/_cluster/settings?pretty --data-binary \
        "{\"$TYPE\": {\"cluster.routing.allocation.exclude._name\": \"$nodes\"}}" |
        grep -q ' "acknowledged"\s*:\s*true' || {
            echo "ERROR: failed to put cluster.routing.allocation.exclude._name=$nodes to $ES/_cluster/settings"
            exit 1
        }
else
    echo "$NODE isn't in excluding list."
fi

echo
echo "Issue this command to enable rebalancing if it's not enabled:"
echo "  curl -m 60 -s -XPUT $ES/_cluster/settings --data-binary '{\"transient\": {\"cluster.routing.rebalance.enable\": \"all\"}}'"
echo "then periodically use these commands to check if $NODE is really joined:"
echo "  curl -s $ES/_cat/health?v"
echo "  curl -s $ES/_cat/shards | fgrep $NODE"
echo "  curl -s $ES/_cat/recovery | fgrep -v done"
echo "After it's done, restore \"cluster.routing.rebalance.enable\" to its original value, eg. none."
echo

