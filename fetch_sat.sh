#!/bin/bash


fetch_sat(){
    # fetches sat from ordinals.com
    # usage: fetch_sat <inscription_id>
    # example: fetch_sat 8ae1bcf23e58f88f895dab98fba21e7c66aa58858b4d14b2f848fb807c404cf9i0
    # returns: 0 if sat is found, 1 if not
    # output: sat value
    sat=$(curl -s https://ordinals.com/inscription/${inscription} | grep -oP '(?<=<a href=/sat/)[^"]+' | grep -o '[0-9]\{13\}' | uniq 2>/dev/null)
}


tmp_file=tmp_sat_out.json
inscribe_log=inscribe_log.json
last_inscription=$(jq -r '.[] | .inscription' $inscribe_log | tail -1)

rm $tmp_file 2>/dev/null

echo "[" > $tmp_file

for inscription in $(jq -r '.[] | .inscription' $inscribe_log); do
    fetch_sat $inscription
    if [ -z "$sat" ]; then
        sat="unknown-or-pending-inscription"
    fi
    echo "sat: $sat - inscription: $inscription"
    #jq  --arg inscription "$inscription" --arg sat "$sat" 'group_by(.inscription) | map((.[0] + {sat: (if .[0].inscription == $inscription then $sat else .[0].sat end)}))' $inscribe_log
    #jq --arg inscription "$inscription" --arg sat "$sat" 'group_by(.inscription) | map(reduce .[] as $x (.; if $x.inscription == $inscription then . + {sat: $sat} else . end))' $inscribe_log
    jq --arg inscription "$inscription" --arg sat "$sat" '.[] | select(.inscription == $inscription) | . + {sat: $sat}' $inscribe_log >> $tmp_file
    # Check if $inscription is equal to the last element in the loop
    if [ "$inscription" == "$last_inscription" ]; then
        echo "]" >> $tmp_file
        break
    else
        echo "," >> $tmp_file
        continue
    fi

    #jq --arg inscription "$inscription" --arg sat "$sat" 'map(select(.inscription == $inscription) + {sat: $sat}) | unique_by(.inscription)' $inscribe_log >> $tmp_file
 done

echo "input file"
cat $inscribe_log | grep -wc "inscription"
cat $inscribe_log | grep -wc "sat"


cat $tmp_file | grep -wc "inscription" 
cat $tmp_file | grep -wc "sat"

#de-duplicate values:
# jq '[.[] | group_by(.commit | map(add) | .[]]' $tmp_file > new_file.txt
jq --slurp '[.[] | group_by(.inscription) | map(reduce .[] as $item ({}; . * $item))]' $tmp_file | jq '.[0]' > new_file.txt


cat new_file.txt | grep -wc "inscription"
cat new_file.txt | grep -wc "sat"

mv new_file.txt $inscribe_log


