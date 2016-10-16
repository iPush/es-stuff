#!/bin/env python

import datetime
import json
from optparse import OptionParser
import urllib2
import time
import sys
import pytool.common

import itertools


def __creat_index(index, es):
    pytool.common.wait_to_avoid_full_clock()

    try:
        opener = urllib2.build_opener(urllib2.HTTPHandler)
        index_url = "{0}/{1}".format(es, index)
        print "creating {0}".format(index_url)

        request = urllib2.Request(index_url)
        request.get_method = lambda: 'PUT'
        res = opener.open(request, timeout=60)

        if res.getcode() == 200:
            print "OK to create {0}".format(index_url)
            return True
        else:
            print "Failed to create {0}. Http Code: {1}. Response: {2}".format
            (
                index_url, res.getcode(), res.read()
            )
            return False

    except urllib2.HTTPError as e:
        print "HTTPError: ", e.getcode
        return False
    except urllib2.URLError as e:
        print "URLError: ", e.reason
        return False
    except SocketError as e:
        print "SocketError: ", e.errno
        return False
    except Exception as e:
        return False


def create_index(index, es):
    for i in range(3):
        if __creat_index(index, es) == 0:
            time.sleep(30)
        else:
            return True
    return False


def prepare_hourly_index(index_prefix, es):
    now = datetime.datetime.utcnow()
    for i in range(1, 25):
        dst_hour = now + datetime.timedelta(hours=i)
        index = "{0}-{1}".format(
            index_prefix,
            dst_hour.strftime("%Y-%m-%d-%H"))
        create_index(index, es)

        pytool.common.wait_for_es_green(es)


def bfs_prepare_hourly_index(index_prefix_list, es):
    for (hour, index_prefix) in itertools.product(
            range(1, 25),
            index_prefix_list):
        now = datetime.datetime.utcnow()
        dst_hour = now + datetime.timedelta(hours=hour)
        index = "{0}-{1}".format(
                index_prefix,
                dst_hour.strftime("%Y-%m-%d-%H"))
        create_index(index, es)

        pytool.common.wait_for_es_green(es)


def prepare_daily_index(index_prefix, es):
    now = datetime.datetime.utcnow()
    tomorrow = now + datetime.timedelta(days=1)
    index = "{0}-{1}".format(index_prefix, tomorrow.strftime("%Y-%m-%d"))
    create_index(index, es)

    pytool.common.wait_for_es_green(es)


if __name__ == "__main__":
    parser = OptionParser()
    parser.add_option(
        "-e",
        "--es",
        dest="es",
        default="http://localhost:9218",
        help="ES address. default to http://localhost:9218")
    (options, args) = parser.parse_args()
    es = options.es

    if not pytool.common.wait_for_es_green(es):
        print "{0} is not green now. stop pre-create indices".format(es)
        sys.exit(1)

    for k, v in pytool.common.indices_pattern_and_prefix.items():
        if k == "daily":
            for prefix in v:
                prepare_daily_index(prefix, es)
        elif k == "hourly":
            bfs_prepare_hourly_index(v, es)
