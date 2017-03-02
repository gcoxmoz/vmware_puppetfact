#!/bin/bash

for file in ../../dmidecode/dmidecode.* ; do grep Address $file | awk '{print $2}' | tr '\n' ' ';  build=`echo $file | tr -C -d 0-9`; echo -n "$build "; jq --arg build $build -c 'limit(1; .[] | select(.interpolated_build_number==$build)? // select(.build_number==$build)? | { version: "\(.major_version)\(.interpolated_update_version)" } | .version )' ../../build_numbers/esxi_build_numbers.json ; done | sort -k3
