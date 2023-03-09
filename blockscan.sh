#!/bin/bash

source .env 2> /dev/null

# This script scans Bitcoin transactions for Counterparty transactions that contain
# a description field containing / bgins with STAMP:

# function to scan the stamp_json variable and find the highest stamp # and output the value
# if null then return 0
fetch_last_stamp(){
    if [[ -f $stamp_json ]]; then
        laststamp=$(jq '.[-1].stamp' $stamp_json)
        if [[ -z $laststamp ]]; then
            laststamp=0
        fi
    else
        laststamp=0
    fi
}

invalidate_s3_file(){
    aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "{$1}"
}

prep_json_to_log(){
    sed -i '/\]/d' ${stamp_json} # Strip trailing ]
    echo "," >> ${stamp_json} # add comma for next entry
}

send_file_to_aws(){  # ORIGINAL_NAME  TARGET_NAME
    aws s3 cp "${1}" "${aws_s3_uri}"/"${aws_s3_dir}"/$1
}

logfile=stamp_scan.log
stamp_json=stamp.json
aws_s3_dir=stamps

source lastblock.log 2> /dev/null
firstblock=${lastblock:=779652}  # 779652 is assumed to be the first block with a stamp trx for testing
scan_to_block=$(bitcoin-cli getblockcount)
block=$firstblock
newjson=false
source ${script_dir}/.env 2> /dev/null
fetch_last_stamp

# open JSON for editing
if [ -f ${stamp_json} ]; then
    echo "Appending to existing $stamp_json in current directory"
    prep_json_to_log # this assumes $inscribe_log already contains an array
else
    echo "[" > $stamp_json
    newjson=true
fi

echo "Scanning from block $firstblock to $scan_to_block"
while [ $block -lt $scan_to_block ]; do
    printf "scanning $block"
    blockhash=$(bitcoin-cli getblockhash $block)
    txids=$(bitcoin-cli getblock  $blockhash | jq -r '.tx[]')
    txs_in_block=$(bitcoin-cli getblock  $blockhash | jq -r '.tx[]' | wc -l)
    #txids=$(bitcoin-cli listsinceblock  $blockhash | jq -r '.transactions[].txid')
    trx_counter=0

    if [[ $laststamp == 0 ]]; then
        block=$firstblock
    fi

    for txid in $txids
    do
        printf "."
        # txid=17686488353b65b128d19031240478ba50f1387d0ea7e5f188ea7fda78ea06f4
        cntrprty_data=$(curl -s https://xchain.io/api/tx/$txid)
        cntrprtydesc=$(echo $cntrprty_data | jq '.description?' | tr -d \")
        timestamp=$(echo $cntrprty_data | jq '.timestamp' | tr -d \")
        block_index=$(echo $cntrprty_data | jq '.block_index' | tr -d \")
        asset_longname=$(echo $cntrprty_data | jq '.asset_longname' | tr -d \")
        asset=$(echo $cntrprty_data | jq '.asset' | tr -d \")

        if [[ -n "$cntrprtydesc" && "$cntrprtydesc" != ""null"" ]]; then 
            echo "..found a CNTRPRTY TXID: $txid"
            if [[ "$cntrprtydesc" == *"stamp"* ]]; then
                echo "FOUND A STAMP TXID: $txid"
                ((laststamp++))
                if [[ "$newjson" == true ]]; then
                    newjson=false
                else
                    prep_json_to_log
                fi
                stampstring=$cntrprtydesc
                stampstring=$(echo $cntrprtydesc | awk -F "stamp:" '{print $2}')
                # convert the base64 value of $stampstring to RAW, determine the file type and save the file
                # iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==
                echo $stampstring | base64 -d > stamp_${laststamp}.tmp
                base64 --decode <<< $stampstring > stamp_${laststamp}.out
                suffix=$(file stamp_${laststamp}.out | cut -d ' ' -f2)
                mv stamp_${laststamp}.out stamp_${laststamp}.$suffix
                send_file_to_aws stamp_${laststamp}.$suffix
                cat <<EOF >> $stamp_json
    {
        "txid": "$txid",
        "stamp": "$laststamp",
        "asset_longname": "$asset_longname",
        "asset": "$asset",
        "timestamp": "$timestamp",
        "block_index": "$block_index",
        "stampstring": "$stampstring",
        "stamp_url": "https://www.hydren.io/${aws_s3_dir}/stamp_${laststamp}.$suffix"
    }
EOF
                send_file_to_aws $stamp_json
                invalidate_s3_file /${aws_s3_dir}/$stamp_json
            fi
        fi
        ((trx_counter++))

    done

    echo "Total trx scanned in block $block: $counter"
    echo "Total trx in block $block: $txs_in_block"
    ((block++))
    # if we don't scan all transactions in a block then we need to log this in case the script aborts and a block isn't finished
    echo "]" > $stamp_json

done
echo "lastblock_scanned=$block" > lastblock.log