import urllib2
import json
import time
import datetime
import pprint

'''
indices pattern and prefix
hourly: index has the following prefix will be created for every single hour
daily:  index has the following prefix will be created for every single day
'''
indices_pattern_and_prefix = {
    "hourly": ("lbha-common-10s", "lbha-common-1s", "cdn-common-10s"),
    "daily": ("lbha-common-5m", "lbha-charge-5m", "cdn-common-5m")
}


'''
reserve date tuple
ES index which match reserve date will not be deleted by delete-old-indices.py

format:
* *
| | +--  Day of the Month   (range: 1-31)
| +----  Month of the Year (range: 1-12)

All fields may be a list of values splitted by comma(,), e.g. 2,4,6 * means
    every day in Feb, Apr and Jun
All fields may be asterisk(*), which means every
All fileds may be range of values (two integers separated by a hyphen, e.g.1-5)

'''
reserve_date = (
    "11 1-12",
    "10 31",
    "6 14-20"
)


def wait_for_es_green(es):
    max_wait = 20
    i = 0
    while i < max_wait:
        if is_es_cluster_green(es):
            return True
        else:
            i += 1
            time.sleep(30)
    return False


def is_es_cluster_green(es):
    url = "{0}/_cluster/health".format(es)
    try:
        res = urllib2.urlopen(url, timeout=10)
        if not res:
            return False

        health = json.loads(res.read())
        if health['status'] == "green":
            return True
        else:
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


def wait_to_avoid_full_clock():
    while True:
        if is_near_full_clock():
            print "Is near full clock"
            time.sleep(30)
        else:
            print "Is NOT near full clock"
            return


def is_near_full_clock():
    DIFF_MIN = 6
    now = datetime.datetime.utcnow()

    if now.minute + DIFF_MIN > 60 or now.minute - DIFF_MIN < 0:
        return True

    return False
