#!/bin/bash

while read line; do
    echo $line | kcat -F kcat.config -P -t entry-events

     echo "Sent message"

done < events_years_13_22.ndjson