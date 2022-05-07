#!/bin/bash

while read line; do
    echo $line | kcat -F kcat.config -P -t class-attendance

     echo "Sent message"

done < classes_years_2013_2022.ndjson