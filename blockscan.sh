#!/bin/bash

# This script scans Bitcoin transactions for messages containing a stamp
# and stores the relevant information in a database. It starts by scanning from block 700000,
# and keeps refreshing and updating the database in real-time.

prep_json_to_log(){
    sed -i '/\]/d' ${STAMP_JSON} # Strip trailing ]
    echo "," >> ${STAMP_JSON} # add comma for next entry
}

send_file_to_aws(){  # ORIGINAL_NAME  TARGET_NAME
    aws s3 cp "${1}" "${aws_s3_uri}"/"${aws_s3_dir}"/${2:=$1}
}

logfile=stamp_scan.log
stamp_json=stamp.json
blockhash=$(bitcoin-cli getblockhash 779652)
currentblock=$(bitcoin-cli getblockcount)
lastblock="779652"

# open JSON for editing
if [ -f ${stamp_json} ]; then
    echo "Appending to existing $stamp_json in current directory"
    prep_json_to_log # this assumes $inscribe_log already contains an array
else
    echo "[" > $stamp_json
fi

#while [ $lastblock -lt $currentblock ]; do

block=$lastblock
txids=$(bitcoin-cli getblock  $blockhash | jq -r '.tx[]')
#txids=$(bitcoin-cli listsinceblock  $blockhash | jq -r '.transactions[].txid')
counter=0

for txid in $txids
do
    cntrprty_data=$(curl -s https://xchain.io/api/tx/$txid)
    cntrprtydesc=$(echo $cntrprty_data | jq '.description?')
    cntrprtydesc="${cntrprtydesc//\"}"
    timestamp=$(echo $cntrprty_data | jq '.timestamp')
    block_index=$(echo $cntrprty_data | jq '.block_index')
    asset_longname=$(echo $cntrprty_data | jq '.asset_longname')
    asset=$(echo $cntrprty_data | jq '.asset')

    if [[ -n "$cntrprtydesc" && "$cntrprtydesc" != ""null"" ]]; then 
        echo "Found a Counterparty Trx"
        if [[ "$cntrprtydesc" == *"stamp"* ]]; then
            echo "FOUND A STAMP"
            echo "," >> $stamp_json
            stampstring=$(echo $cntrprtydesc | sed -n 's/.*stamp:"\?\(.*\)".*/\1/p')
            cat <<EOF >> $stamp_json
            {
                "txid": "$txid",
                "asset_longname": "$asset_longname",
                "asset": "$asset",
                "timestamp": "$timestamp",
                "block_index": "$block_index",
                "stampstring": "$stampstring"
            }
EOF
        fi
    fi
    ((counter++))
done

echo "Total Number of Transactions Scanned: $counter"