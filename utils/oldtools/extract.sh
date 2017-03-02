#!/bin/bash

#
# Super simple extract of the JSON, matching the build number most likely to be known, with the shorthand version
#

jq '[.[] | { build: "\(.interpolated_build_number)", version: "\(.major_version)\(.interpolated_update_version)" }]' ../../build_numbers/esxi_build_numbers.json
