#!/bin/bash

ES=${1:-$ES}
ES=${ES:-localhost:9200}
TEMPLATE=${2:-lbha}

curl -m 20 -s -XPUT $ES/_template/{TEMPLATE} --data-binary "@`dirname pwd`/templates/${TEMPLATE}.json"
