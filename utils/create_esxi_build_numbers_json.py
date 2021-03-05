#!/usr/bin/env python3
'''
    This script is a pipeline.  cat raw_data_from_KB.txt | this
    In here, we parse the contents of the VMware KB into a JSON data structure that we can use in,
    well, whatever we want.  It's a basis for making a map for a puppet fact, in our case, but the
    JSON itself might have use for others.

    gcox@mozilla
'''
import sys
import json
import re

fields       = ('osname', 'full_version', 'major_version', 'true_minor_version',
                'release_date', 'build_number', 'installer_build_number')
addon_fields = ('interpolated_update_version', 'interpolated_build_number')

def match_one_line(line_fields, line):
    '''
        Perform regex matching on submitted line.
        return dict() of mapped info, or string of error
    '''
    if re.match(r'^\s*$', line):
        # skip empty lines
        return {}
    if re.match(r'^\s*#', line):
        # skip comments
        return {}
    linematcher = re.compile(r'''
    ^\s*                          # leading spaces if any
     (ESX|ESXi|ESXI||ESXi/ESX)\s+ # ESX or ESXi, space
     ((\d\.\d)                    # Major version number  (doublegrab here, full version and breakout)
       (?:\s+|\.\d?\s*|\S\s*)     # either spaces, or, .0(optionalspace) to get rid of stupid cases of
                                  # there being "5.1.0 GA" and "6.0.0b" and "7.0b"
     (.*?))                       # A grab-it-all for the descriptor of the release.
     \t                           #   BREAK
     [^\t]+                       # A release name, which we do not currently use   FIXME
     \t                           #   BREAK
     (\s|\d{1,2}/\d{1,2}/\d{4}|\d{4}-\d{2}-\d{2})
                                  # Release date (if they put one in)
     \t                           #   BREAK
     (\d+)                        # Numeric build number
     \t                           #   BREAK
     (\S+)                        # Installer build number (though usually an "NA" or "N/A")
     \s*$                         # trailing spaces if any
     ''',
    re.X)
    # If VMW changes the layout of the KB, this regexp will probably need tweaking.
    # In lieu of an example line for this evil regexp, see raw_data_from_KB.txt
    linematch = linematcher.match(line)
    line = line.rstrip('\r\n')
    if linematch:
        vals = list(linematch.groups())
        line_dict = {line_fields[i] : vals[i] for i in range(0, len(vals))}
        if line_dict['release_date'] in [' ']:
            line_dict['release_date'] = ''
        # Fix the date into YYYY-MM-DD
        datecheck_usa = re.match(r'(\d{1,2})/(\d{1,2})/(\d{4})', line_dict['release_date'])
        if datecheck_usa:
            line_dict['release_date'] = '{yyyy:04d}-{mm:02d}-{dd:02d}'.format(
                    yyyy=int(datecheck_usa.group(3)),
                    mm=int(datecheck_usa.group(1)),
                    dd=int(datecheck_usa.group(2)))
        return line_dict
    return 'Could not match "{}"'.format(line)

def main():
    ''' main function '''
    # For each line, make a hash of k/v pairs based on the structure of the KB.
    parsed_lines = list()
    for stdin_line in sys.stdin:
        parsed_line = match_one_line(fields, stdin_line)
        if isinstance(parsed_line, str):
            # strings are errors
            print(parsed_line, file=sys.stderr)
            continue
        if not isinstance(parsed_line, dict):
            print('Invalid return type from match_one_line.', file=sys.stderr)
            sys.exit(2)
        if not parsed_line:
            # comment or blank line, okay to skip.
            continue
        # Note that we're insert() rather than append(), to reverse the list as we build it.
        parsed_lines.insert(0, parsed_line)

    ## Interpolate a build number and a "well, it's MOSTLY this update version" into variables for
    ## simplicity's sake.

    output_lines = list()
    interpolated_update_version = ''
    major_version_tracker = "-123456"    # just something that doesn't match a real version

    # remember that this loop is handled in 'reverse list order'.
    # because of how we sequenced inserts into parsed_lines in the last loop.
    # i.e. we're now working from old to new / bottom to top of the KB sheet.
    for parsed_line in parsed_lines:
        if major_version_tracker != parsed_line['major_version']:
            major_version_tracker = parsed_line['major_version']
            interpolated_update_version = ''
        else:
            update_match = re.match(r'(?:U|Update )(\d+)', parsed_line['true_minor_version'])
            if update_match:
                interpolated_update_version = 'u{}'.format(update_match.group(1))
        parsed_line['interpolated_update_version'] = interpolated_update_version

        build_match = re.match(r'^\d+$', parsed_line['installer_build_number'])
        if build_match:
            parsed_line['interpolated_build_number'] = parsed_line['installer_build_number']
        else:
            parsed_line['interpolated_build_number'] = parsed_line['build_number']
        # Note that we're insert() rather than append(), to reverse the list as we build it.
        # This puts us back in 'sheet' order
        output_lines.insert(0, parsed_line)

    json_text = json.dumps(output_lines, ensure_ascii=False, indent=3, separators=(',', ' : '))
    print(json_text)

if __name__ == '__main__':
    main()
