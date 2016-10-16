#!/bin/bash

INVENTORY_FILE=${1:-hosts}
PLAYBOOK=${2:-site.yml}
shift 2
INDICES_TEMPLATES=(lbha lbha-dev lbha-charge lbha-dev-charge cdn cdn-dev)

function  create_index_templates()
{
    for template in "${INDICES_TEMPLATES[@]}"
    do
        __create_index_template $1 $template
    done
}

function __create_index_template()
{
    while :; do
        date; echo "create index template for $2"
        if `dirname $0`/create-index-template.sh $1 $2 | grep -q 'acknowledged.*true'; then
            break
        else
            date; echo "failed to create template for $2, retry..."
            sleep 5
        fi
    done

}


[ -f "$INVENTORY_FILE" -a -f "$PLAYBOOK" ] || {
    echo "ERROR: inventory file '$INVENTORY_FILE' or playbook file '$PLAYBOOK' must exist!" >&2
    exit 1
}

read -p "Confirm to deploy hosts in $INVENTORY_FILE? [y/N]" c
[ "$c" = y -o "$c" = Y ] && {
    master_nodes=(`ansible elasticsearch.master -i $INVENTORY_FILE --list-hosts`)
    data_nodes=(`ansible elasticsearch.data -i $INVENTORY_FILE --list-hosts`)
    if [ ${#master_nodes[@]} = 0 -o ${#data_nodes[@]} = 0 ]; then
        echo "ERROR: no master or data nodes found!" >&2
        exit 1
    fi

    date; echo "stop ES gateway for indexing"
    ansible elasticsearch.gateway.index -i $INVENTORY_FILE -b --become-user admin \
        -m shell -a 'cd /tmp; d=/export/servers; f=$d/service/elasticsearch-gateway; [ ! -e $f ] || $d/runit-2.1.2/bin/sv -w 30 force-stop $f; rm -f $f' "$@"
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

    date; echo "deploy ES master nodes, data nodes and gateway nodes for searching"
    ansible-playbook -i $INVENTORY_FILE -b --become-user admin $PLAYBOOK -l elasticsearch.master:elasticsearch.data:elasticsearch.gateway.search "$@" || exit 1

    date; echo "waiting cluster to be healthy..."
    indices_created=
    while :; do
        i=$(( $RANDOM % ${#data_nodes[@]} ))
        data_node=${data_nodes[$i]}
        data_node=${data_node%.es_data}
        date; echo "checking http://$data_node:9200/_cat/health?v..."
        response=`curl -m 5 -s http://$data_node:9200/_cat/health?v`
        echo "$response"
        if perl -e 'exit 1 unless @ARGV >= 14 && $ARGV[5] eq "green" && $ARGV[6] >= ($ARGV[0] + $ARGV[1]) && $ARGV[7] >= $ARGV[1] && $ARGV[10] + $ARGV[11] + $ARGV[12] + $ARGV[13] == 0' \
                ${#master_nodes[@]} ${#data_nodes[@]} `echo "$response" | tail -1`; then

            [ "$indices_created" ] && break

            create_index_templates $data_node:9200

            [ -z "$PRECREATE_INDICES" ] || perl -le 'use POSIX;
                $t1 = time() - 2 * 3600;
                $t2 = $t1 + 52 * 3600;
                while ($t1 < $t2) {
                    print strftime("%Y-%m-%d-%H", localtime($t1));
                    $t1 += 3600;
                }' | while read t; do
                date; echo "create index index-0-$t..."
                curl -s -XPUT http://$data_node:9200/index-0-$t
                sleep 1
            done

            indices_created=true
        else
            sleep 5
        fi
    done
    sleep 2

    date; echo "deploy ES gateway for indexing"
    ansible-playbook -i $INVENTORY_FILE -b --become-user admin $PLAYBOOK -l elasticsearch.gateway.index "$@"
}
