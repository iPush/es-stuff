#!/bin/bash

set -o pipefail

ES="${1:-localhost:9200}"       # ES host
HOURS="${2:-2}"                 # 2 hours
PATTERN="${3:-index-*}"         # index pattern
TRIES="${4:-10}"                # how many times to retry
RATE="${5:-2000}"               # ingesting rate, documents per second
NODES="${6:-145}"               # expected number of nodes in the cluster
REPLICAS="${7:-1}"              # how many replicas for an index
MAX_SHARDS_PER_NODE="${8:-2}"   # how many primary and replica shards of an index on single node

while (( --TRIES >= 0 )); do
    echo "[`date`] checking $ES/_cat/indices/$PATTERN?h=index,rep,docs.count,health ..."
    indices1=`curl -m 60 -s "$ES/_cat/indices/$PATTERN?h=index,rep,docs.count,health" | sort`

    if [ $? = 0 -a "$indices1" ]; then
        time1=`date +%s`
        break
    fi

    sleep 5
done

echo "first: $time1"
echo "$indices1"
echo

echo "sleep 120s..."
sleep 120

while (( --TRIES >= 0 )); do
    echo "[`date`] checking $ES/_cat/indices/$PATTERN?h=index,rep,docs.count,health ..."
    indices2=`curl -m 60 -s "$ES/_cat/indices/$PATTERN?h=index,rep,docs.count,health" | sort`

    if [ $? = 0 -a "$indices2" ]; then
        time2=`date +%s`

        echo "second: $time2"
        echo "$indices2"
        echo

        for i in `seq 1 10`; do
            echo "[`date`] checking $ES/_cat/health?h=node.total ..."
            total_nodes=`curl -m 20 -s "$ES/_cat/health?h=node.total"`

            if [ $? = 0 -a "$total_nodes" ]; then
                if [ $total_nodes -lt $NODES ]; then
                    echo "[`date`] ERROR: expected $NODES nodes but got $total_nodes nodes, this cluster may be being deployed."
                    exit 1
                else
                    break
                fi
            fi

            sleep 2
        done

        [ -z "$total_nodes" ] && {
            echo "[`date`] ERROR: failed to check $ES/_cat/health?h=node.total"
            exit 1
        }

        join <(echo "$indices1") <(echo "$indices2") |
            while read index cols; do
                echo "[`date`] checking $index..."

                perl -lwe 'use POSIX; use strict;
                    my ($hours, $index, $rep1, $count1, $health1,
                                        $rep2, $count2, $health2,
                        $rate, $interval) = @ARGV;
                    exit(1) unless defined $interval && $interval > 0;
                    exit(1) if $rep2 > 0;
                    exit(0) if $health2 eq "red";
                    exit(1) if $count2 == 0;
                    exit(1) if (($count2 - $count1) / $interval) >= $rate;
                    my $t = strftime("%Y-%m-%d-%H", localtime(time() - $hours * 3600));
                    my $len = length($t);
                    $index =~ s/[^0-9\-]/-/g;
                    exit(1) if length($index) < $len || substr($index, -$len) gt $t;
                    ' $HOURS $index $cols $RATE $(( $time2 - $time1 )) &&
                        for i in `seq 1 5`; do
                            echo "[`date`][$i/5] change number_of_replicas to $REPLICAS for $ES/$index ..."
                            curl -m 20 -s -XPOST "$ES/$index/_flush/synced" && sleep 10 &&
                            curl -m 20 -s -XPUT "$ES/$index/_settings" --data-binary "{\"index.number_of_replicas\": $REPLICAS, \"index.routing.allocation.total_shards_per_node\": $MAX_SHARDS_PER_NODE}" &&
                                break
                            sleep 5
                        done

                sleep 1
            done

        break
    fi

    sleep 5
done

