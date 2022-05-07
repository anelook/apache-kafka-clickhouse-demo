#!/bin/bash

while read line; do
    echo $line | kcat -F kcat.config -P -t test-manual-items

     echo "Sent message"

done < classes_years_13_22.ndjson