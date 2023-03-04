#!/bin/bash

# This script scans Bitcoin transactions for messages containing a stamp
# and stores the relevant information in a database. It starts by scanning from block 700000,
# and keeps refreshing and updating the database in real-time.

# Set variables
DATABASE=stamp.db
BLOCK=$(bitcoin-cli getblockcount)
LOGFILE=stamp_scan.log

# Function to extract data from transaction output
function extract_data {
    echo $1 | jq -r '.vout[] | select(.scriptPubKey.asm | contains("OP_RETURN")) | .scriptPubKey.asm' | tr -d '[:space:]' | sed -n 's/.*stamp:"\?\(.*\)".*/\1/p'
}

# Initialize database if it doesn't exist
if [ ! -f "$DATABASE" ]; then
    sqlite3 $DATABASE "CREATE TABLE stamps (txid TEXT, vout INTEGER, address TEXT, value REAL, timestamp INTEGER, stamp TEXT);"
    echo "Database created."
fi

# Start scanning transactions
while true
do
    NEWBLOCK=$(bitcoin-cli getblockcount)
    if [ $NEWBLOCK -gt $BLOCK ]; then
        echo "New block detected: $NEWBLOCK"
        BLOCK=$NEWBLOCK
        TXIDS=$(bitcoin-cli listsinceblock 700000 | jq -r '.transactions[].txid')
        for TXID in $TXIDS
        do
            VOUTS=$(bitcoin-cli getrawtransaction $TXID true | jq -r '.vout[] | select(.scriptPubKey.asm | contains("OP_RETURN")) | .n')
            for VOUT in $VOUTS
            do
                ADDRESS=$(bitcoin-cli getrawtransaction $TXID true | jq -r ".vout[$VOUT].scriptPubKey.addresses[0]")
                VALUE=$(bitcoin-cli getrawtransaction $TXID true | jq -r ".vout[$VOUT].value")
                TIMESTAMP=$(date +%s)
                DATA=$(bitcoin-cli getrawtransaction $TXID true | extract_data)
                if [ ! -z "$DATA" ]; then
                    sqlite3 $DATABASE "INSERT INTO stamps (txid, vout, address, value, timestamp, stamp) VALUES ('$TXID', $VOUT, '$ADDRESS', $VALUE, $TIMESTAMP, '$DATA');"
                    echo "Stamp added: $TXID:$VOUT"
                fi
            done
        done
    fi
    sleep 5s
done
