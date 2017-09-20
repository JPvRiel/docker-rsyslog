#!/usr/bin/env python
import sys
import glob
import re

def expand_included_config(conf_file='/etc/rsyslog.conf', re_directive='^\$IncludeConfig (.*)'):
    with open(conf_file, 'r') as parent_file:
        for l in parent_file.readlines():
            m = re.match(re_directive, l)
            if m:
                sys.stdout.write('##< start of include directive: ')
                sys.stdout.write(l)
                for f in glob.glob(m.group(1)):
                    sys.stdout.write('##^ expanding file: {0:s}\n'.format(f))
                    # recurse in case children config files also have $Include
                    expand_included_config(f)
                sys.stdout.write('##> end of expand directive: ')
                sys.stdout.write(l)
            else:
                sys.stdout.write(l)

if __name__ == "__main__":
    if len(sys.argv) == 1:
        expand_included_config()
    elif len(sys.argv) == 2:
        expand_included_config(sys.argv[1])
    else:
        raise ValueError("The only optional argument is the rsyslog config filename")
