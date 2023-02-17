#!/bin/bash


fetch_sat(){
    # fetches sat from ordinals.com
    # usage: fetch_sat <inscription_id>
    # example: fetch_sat 8ae1bcf23e58f88f895dab98fba21e7c66aa58858b4d14b2f848fb807c404cf9i0
    # returns: 0 if sat is found, 1 if not
    # output: sat value
    sat=$(curl -s 'https://ordinals.com/inscription/${inscription}'| grep -oP '(?<=<a href=/sat/)[^"]+' | grep -o '[0-9]\{13\}' | uniq 2>/dev/null)
}


tmp_file=tmp_sat_out.json
inscribe_log=inscribe_log.json


for inscription in $(jq -r '[]. | .inscription' $inscribe_log); do
    fetch_sat $inscription
    echo "sat: $sat - inscription: $inscription "
    jq --arg inscription "$inscription" --arg sat "$sat" 'map(if .inscription == $inscription then .sat = $sat else .sat = "unknown" end)' $inscribe_log > $tmp_file
done


 