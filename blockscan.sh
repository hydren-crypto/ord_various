#!/bin/bash

# This script scans Bitcoin transactions for messages containing a stamp
# and stores the relevant information in a database. It starts by scanning from block 700000,
# and keeps refreshing and updating the database in real-time.

prep_json_to_log(){
    sed -i '/\]/d' ${STAMP_JSON} # Strip trailing ]
    echo "," >> ${STAMP_JSON} # add comma for next entry
}

# Set variables
DATABASE=stamp.db
BLOCK=$(bitcoin-cli getblockcount)
LOGFILE=stamp_scan.log
STAMP_JSON=stamp.json

# Initialize database if it doesn't exist
#if [ ! -f "$DATABASE" ]; then
#    sqlite3 $DATABASE "CREATE TABLE stamps (txid TEXT, vout INTEGER, address TEXT, value REAL, timestamp INTEGER, stamp TEXT);"
#    echo "Database created."
#fi

# Start scanning transactions
BLOCKHASH=$(bitcoin-cli getblockhash 779652)
CURRENTBLOCK=$(bitcoin-cli getblockcount)
LASTBLOCK="779652"

# open JSON for editing
if [ -f ${STAMP_JSON} ]; then
    echo "Appending to existing $STAMP_JSON in current directory"
    prep_json_to_log # this assumes $inscribe_log already contains an array
else
    echo "[" > $STAMP_JSON
fi

#while [ $LASTBLOCK -lt $CURRENTBLOCK ]; do

    #BLOCK=($LASTBLOCK + 1)
    BLOCK=$LASTBLOCK
    TXIDS=$(bitcoin-cli getblock  $BLOCKHASH | jq -r '.tx[]')
    #TXIDS=$(bitcoin-cli listsinceblock  $BLOCKHASH | jq -r '.transactions[].txid')
    for TXID in $TXIDS
    do
    #TXID=3e034d5522e5c4abd9466ad5e9ca340ded72bafad413dd4c1c2583e801e751ff
    # curl -s https://xchain.io/api/tx/3e034d5522e5c4abd9466ad5e9ca340ded72bafad413dd4c1c2583e801e751ff | jq '.description? | select(startswith("stamp",ignorecase))' 
    CNTRPRTY_DATA=$(curl -s https://xchain.io/api/tx/$TXID)
    CNTRPRTYDESC=$(echo $CNTRPRTY_DATA | jq '.description?')
    CNTRPRTYDESC="${CNTRPRTYDESC//\"}"
    TIMESTAMP=$(echo $CNTRPRTY_DATA | jq '.timestamp')
    BLOCK_INDEX=$(echo $CNTRPRTY_DATA | jq '.block_index')
    ASSET_LONGNAME=$(echo $CNTRPRTY_DATA | jq '.asset_longname')
    ASSET=$(echo $CNTRPRTY_DATA | jq '.asset')

    if [[ -n "$CNTRPRTYDESC" && "$CNTRPRTYDESC" != ""null"" ]]; then 
        echo "Found a Counterparty Trx"
        if [[ "$CNTRPRTYDESC" == *"stamp"* ]]; then
            echo "FOUND A STAMP"
            echo "," >> $STAMP_JSON
            STAMPSTRING=$(echo $CNTRPRTYDESC | sed -n 's/.*stamp:"\?\(.*\)".*/\1/p')  # this captures up to the next double quote
            # grep -o 'stamp:[^;]*'  - this captures up to the next semicolon
            cat <<EOF >> $STAMP_JSON
            {
                "txid": "$TXID",
                "asset_longname": "$ASSET_LONGNAME",
                "asset": "$ASSET",
                "timestamp": "$TIMESTAMP",
                "block_index": "$BLOCK_INDEX",
                "stampstring": "$STAMPSTRING"
            }
EOF
        fi
    fi
    done
