import re

search_re = re.compile(r'^([^-]+)-([^-/]+)(/(.*))?$')
only_int_re = re.compile(r'^\d+$')
any_int_re = re.compile(r'^\d+')
star_or_int_re = re.compile(r'^(\d+|\*)$')

class CronParser:
    MONTHS_IN_YEAR = 12
    RANGES = (
        (1, 12)
        (1, 31)
    )
    bad_length = "Exactly 2 fileds should be specified. 1st for month, and 2nd for day of month"

    def __init__(self, expr):
        self.exprs = expr.split()
        if len(exprs) != 2:
            raise ValueError(self.bad_length)

        expanded = []
        for i, expr in enumerate(self.exprs):
            t = re.sub(r'^\*(/.+)$', r'%d-%d\1' % (
                    self.RANGES[i][0],
                    self.RANGES[i][1]),
                    str(expr))
            m = search_re.search(t)

            if m:
                (low, high, step) = m.group(1), m.group(2), m.group(4) or 1
