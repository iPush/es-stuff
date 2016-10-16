#!/bin/env python
import argparse
import urllib2
import time

def __delete_index(index, es="http://localhost:9200/"):
    opener = urllib2.build_opener(urllib2.HTTPHandler)
    index_url = "{}/{}".format(es, index)
    request = urllib2.Request(index_url)
    request.get_method = lambda: 'DELETE'
    res = opener.open(request, timeout=20)
    if res.getcode() == 200:
        return 1
    else:
        return 0

def delete_index(index, es):
    for i in range(3):
        if __delete_index(index, es) == 0:
            time.sleep(3)
        else:
            return 1
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="pre-create ES indices ")
    parser.add_argument("--es",
    default="http://localhost:9200",
    help="ES address. default to http://localhost:9200")
    args = parser.parse_args()
    es = args.es

    if not is_es_cluster_green(es):
        print "{} is not green now. stop pre-create indices".format(es)
        sys.exit(1)

    #TODO delete old indices not in reserve_date time ranges
