#!/usr/bin/env python3
'''
    gcox@mozilla
'''
import os
import sys
import re
import argparse
import json

# paths relative to this script:
BUILD_NUM_JSON_FILE = '../build_numbers/esxi_build_numbers.json'
DMIDECODE_DIR       = '../dmidecode'

__location__ = os.path.dirname(__file__)

def ingest_json(filename):
    '''
        Read in our JSON of VMware's build numbers, and build a hash of
            build number -> version number
        This is pretty much rendering our own 'pretty' version of the VMware KB.
    '''
    fullpath = os.path.join(__location__, filename)
    with open(fullpath, 'r') as jsonfilehandle:
        data = jsonfilehandle.read()
    build_num_json = json.loads(data)

    all_builds = dict()
    for build_ref in build_num_json:
        for attr in ['build_number', 'installer_build_number']:
            try:
                int(build_ref[attr])
            except ValueError:
                continue
            buildnum = build_ref[attr]
            major_version = build_ref['major_version']
            minor_version = build_ref['major_version'] + build_ref['interpolated_update_version']

            all_builds[buildnum] = {'major': major_version,
                                    'minor': minor_version}
    return all_builds

def ingest_dmidecode_files(dirname):
    '''
        This is a search over our dmidecode directory, and from that we build a dict of
            build number -> BIOS Address and Dates
    '''
    all_bios = dict()
    for root, _dirs, files in os.walk(dirname):
        for file in files:
            filenamematch = re.match(r'^dmidecode\.(\d+)\.txt$', file)
            if not filenamematch:
                continue
            buildnum = filenamematch.group(1)
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as dmidecode_filehandle:
                filecontents = dmidecode_filehandle.read()
            addressmatch = re.search(r'^\s*Address:\s+(0x[0-9A-F]{5})\s*$',
                                    filecontents, re.MULTILINE)
            address = addressmatch.group(1)
            datematch = re.search(r'^\s*Release\s+Date:\s+(\d{2}/\d{2}/\d{4})\s*$',
                                 filecontents, re.MULTILINE)
            date = datematch.group(1)
            all_bios[buildnum] = {'address': address, 'date': date}
    return all_bios

def all_possible_builds(bioses, builds, options):
    '''
        Search all of our BIOS dumps and connect them to the build sheet from VMware.
        The result here is a hash of
            biosaddress -> date -> version
        This is a sort of 'reverse hash'.  Each ESX version has a BIOS version, but each
        BIOS version can happen in multiple ESX versions.  We build that latter mapping
        so we can match everyone up later.
    '''
    possible_builds = {}

    if options.minor_version:
        version_attr = 'minor'
    else:
        version_attr = 'major'
    for buildnum, values in bioses.items():
        address = values['address']
        date = values['date']
        version = builds[buildnum][version_attr]

        possible_builds.setdefault(address, {}).setdefault(date, {}).setdefault(version, True)
    return possible_builds

def version_matching(bioses, builds, possibuilds, options):
    '''
        At this point, you have
            BIOSes:  buildnum -> (BIOS address and date)
            VMware:  buildnum -> (version)

        Here we flatten the bios list down to unique combinations of address(+date) -> version
        This uses the build number as the glue, but then gets the build number out of the way
        since it has no meaning in the final results.

        The 'weird' part in here is, a BIOS address can appear in multiple ESXi version.
        So part of what we do in here is squish down to a single answer: address X is ESXi Y.
        We hedge low or high based on the minor_high option.
    '''
    if options.minor_version:
        version_attr = 'minor'
    else:
        version_attr = 'major'

    last = {'address': '', 'date': '', 'version': ''}
    line_order = []

    for buildnum, values in sorted(bioses.items(), key = lambda kv: (builds[kv[0]]['minor'], kv)):
        address = values['address']
        date    = values['date']
        version = builds[buildnum][version_attr]

        # This section truncates dupes, so bypass it if we're going to dump everything:
        if not options.dump:
            # Since the only inputs we have are the address and date, we have to cheat here.
            # Find the desired output version (round low or high) and go straight there.
            possible_versions = sorted(possibuilds[address][date].keys())

            if not options.minor_high:
                possible_versions.reverse()
            version = possible_versions[0]
            # Now that we've rounded $version, check if we've seen it before.
            if (last['address'] == address) and (last['version'] == version):
                continue
            last['address'] = address
            last['date'] = date
            last['version'] = version

        line_order.append({'address': address, 'date': date,
                           'buildnum': buildnum, 'version': version})
    return line_order

def render_output(line_order, options):
    '''
        Print the output, either as lines or as a templated puppet fact
    '''
    if not options.templatefile:
        for line in line_order:
            print(f'{line["address"]} {line["date"]} {line["buildnum"]} {line["version"]}')
        sys.exit(0)

    addresses_considered = dict()
    for line in line_order:
        addresses_considered.setdefault(line["address"], {}
                           ).setdefault(line["date"], {}
                           ).setdefault(line["version"], True)
    flattened_lines = []

    for line in line_order:
        address = line['address']
        date = line['date']
        version = line['version']
        if len(addresses_considered[address]) > 1:
            flattened_lines.append(f"elsif biosaddress == '{address}' and biosdate == '{date}'")
        else:
            flattened_lines.append(f"elsif biosaddress == '{address}'")
        flattened_lines.append(f"    vmversion = '{version}'")

    with open(options.templatefile, 'r') as templatefilehandle:
        unparsed_template = templatefilehandle.readlines()
    print(f"# This file was generated from {options.templatefile}")
    print('')
    for line in unparsed_template:
        line = line.rstrip('\r\n')
        placeholder_matching = re.match(r'^(\s*)\[PLACEHOLDER\].*$', line)
        if not placeholder_matching:
            print(line)
            continue
        spacing = placeholder_matching.group(1)
        for subline in flattened_lines:
            print(f'{spacing}{subline}')


def main(prog_args=None):
    ''' main function '''
    if prog_args is None:
        prog_args = sys.argv
    parser = argparse.ArgumentParser()
    # Show minor (6.0u2) or major (6.0) versions?
    parser.add_argument('--minor',
                        action='store_true',
                        default=False,
                        dest='minor_version',
                        help='Show minor versions')
    # Sometimes, multiple releases use the same BIOS ID as others (e.g 4.1 GA through 4.1u4).
    # When this happens, there's absolutely NO way of knowing where on the spectrum you are.
    # So, we can either put things on the low end (4.1 GA) or the high end (4.1u4).
    # By default we round down: "you're AT LEAST this release."  (though, the report makes it
    # sound like "you ARE this release")
    # If you like, you can set --minor-error-high to round up.  That would say you're 4.1u4
    # even if you're on, say, 4.1u2.  So, it's not always the truth.
    parser.add_argument('--minor-error-high',
                        action='store_true',
                        default=False,
                        dest='minor_high',
                        help='Round minor-version guesses high')
    # Dump all mapping, doing no reduction for same-BIOS-address detection.  A debug helper.
    parser.add_argument('--dump',
                        action='store_true',
                        default=False,
                        dest='dump',
                        help='Dump all possible BIOS/versions')

    # When present, templatefile is a template file of ruby that substitutes [PLACEHOLDER] for
    # a set of if-then's to find your ESXi version.
    parser.add_argument('--template',
                        dest='templatefile',
                        metavar='FILE',
                        help='use <FILE> and substitute our versioning into the [PLACEHOLDER] area')
    cli_options = parser.parse_args(prog_args[1:])

    all_builds = ingest_json(BUILD_NUM_JSON_FILE)
    all_bioses = ingest_dmidecode_files(DMIDECODE_DIR)
    possible_builds = all_possible_builds(all_bioses, all_builds, cli_options)
    version_matchup = version_matching(all_bioses, all_builds, possible_builds, cli_options)
    render_output(version_matchup, cli_options)

if __name__ == '__main__':
    main()
