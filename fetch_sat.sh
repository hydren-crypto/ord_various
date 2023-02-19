#!/bin/bash


fetch_sat(){
    # fetches sat from ordinals.com
    # usage: fetch_sat <inscription_id>
    # example: fetch_sat 8ae1bcf23e58f88f895dab98fba21e7c66aa58858b4d14b2f848fb807c404cf9i0
    # returns: 0 if sat is found, 1 if not
    # output: sat value
    sat=$(curl -s https://ordinals.com/inscription/${inscription} | grep -oP '(?<=<a href=/sat/)[^"]+' | grep -o '[0-9]\{13\}' | uniq 2>/dev/null)
    inscription_id=$(curl -s https://ordinals.com/inscription/${inscription} | grep -o '<title>Inscription [0-9]\+</title>' | grep -o '[0-9]\+' 2>/dev/null)
    block=$(curl -s https://ordinals.com/sat/${sat} | grep -oP '(?<=<a href=/block/)[^>]+' 2>/dev/null)
}

fetch_description_from_filename(){
    # fetches description from filename
    # usage: fetch_description_from_filename <filename>
    # example: fetch_description_from_filename 8ae1bcf23e58f88f895dab98fba21e7c66aa58858b4d14b2f848fb807c404cf9i0
    # returns: 0 if description is found, 1 if not
    # output: description value
    description=$(ls ./done/ | grep $inscription |  cut -d_ -f2- | cut -d. -f1)
    if [ -z "$description" ]; then
        description="unknown"
    fi
}

fetch_filename_from_done_dir(){
    # fetches filename from done directory
    # usage: fetch_filename_from_done_dir <filename>
    # example: fetch_filename_from_done_dir 8ae1bcf23e58f88f895dab98fba21e7c66aa58858b4d14b2f848fb807c404cf9i0
    # returns: 0 if filename is found, 1 if not
    # output: filename value
    filename=$(ls ./done/ | grep $inscription |  cut -d_ -f2)
    if [ -z "$filename" ]; then
        filename="unknown"
    fi
}

tmp_file=tmp_sat_out.json
inscribe_log=inscribe_log.json
last_inscription=$(jq -r '.[] | .inscription' $inscribe_log | tail -1)

cp $inscribe_log inscribe_log.bak
rm $tmp_file 2>/dev/null

echo "[" > $tmp_file

for inscription in $(jq -r '.[] | .inscription' $inscribe_log); do
    fetch_sat $inscription

    if [ -z "$sat" ] && [ -z "$inscription_id" ]; then
        echo "inscription: $inscription - no value yet for sat and inscription_id - skipping"
        jq --arg inscription "$inscription" '.[] | select(.inscription == $inscription)' $inscribe_log >> $tmp_file
    else
        echo "inscription: $inscription - sat: $sat - block: $block - inscription_id: $inscription_id "
        # if the keys exist they will not be overwritten
        jq --arg inscription "$inscription" --arg sat "$sat" --arg inscription_id "$inscription_id" --arg block "$block" \
            '.[] | select(.inscription == $inscription) | . + {sat: $sat, inscription_id: $inscription_id, block: $block}' $inscribe_log >> $tmp_file
    fi
    # Check if $inscription is equal to the last element in the loop
    if [ "$inscription" == "$last_inscription" ]; then
        echo "]" >> $tmp_file
        break
    else
        echo "," >> $tmp_file
        continue
    fi
 done

echo "Line count for Inscription and sat"
echo "$inscribe_log"
original_lc=$(jq '.[] | .inscription' $inscribe_log | wc -l)
echo "$original_lc"
jq '.[] | .sat' $inscribe_log | wc -l

echo "$tmp_file - after adding sat value"
temp_lc=$(jq '.[] | .inscription' $tmp_file | wc -l)
echo "$temp_lc"
jq '.[] | .sat' $tmp_file | wc -l


#de-duplicate values:
# jq '[.[] | group_by(.commit | map(add) | .[]]' $tmp_file > new_file.txt
jq --slurp '[.[] | group_by(.inscription) | map(reduce .[] as $item ({}; . * $item))]' $tmp_file | jq '.[0]' > new_file.txt

echo "Deduplicated inscription line count"
echo "new_file.txt"
jq '.[] | .inscription' new_file.txt | wc -l
jq '.[] | .sat' new_file.txt | wc -l


echo "moving new_file.txt to $inscribe_log - backup saved as inscribe_log.bak"
mv new_file.txt $inscribe_log


