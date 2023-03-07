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
BLOCKHASH=$(bitcoin-cli getblockhash 777592)
CURRENTBLOCK=$(bitcoin-cli getblockcount)
LASTBLOCK="777592"

#while [ $LASTBLOCK -lt $CURRENTBLOCK ]; do

    #BLOCK=($LASTBLOCK + 1)
    BLOCK=$LASTBLOCK
    TXIDS=$(bitcoin-cli getblock  $BLOCKHASH | jq -r '.tx[]')
    #TXIDS=$(bitcoin-cli listsinceblock  $BLOCKHASH | jq -r '.transactions[].txid')
    for TXID in $TXIDS
    do
	# stamp:"data:image/gif;base64,R0lGODlhGAAYAJEAAOYVFQAAAP=="
	#TXID=3e034d5522e5c4abd9466ad5e9ca340ded72bafad413dd4c1c2583e801e751ff
	# curl -s https://xchain.io/api/tx/3e034d5522e5c4abd9466ad5e9ca340ded72bafad413dd4c1c2583e801e751ff | jq '.description? | select(startswith("stamp",ignorecase))' 
	#CNTRPRTYDESC=$(curl -s https://xchain.io/api/tx/$TXID | jq '.description? | tostring | ascii_downcase | select(startswith("stamp"))')
	CNTRPRTYDESC=$(curl -s https://xchain.io/api/tx/$TXID | jq '.description? | tostring ')
	CNTRPRTYDESC="${CNTRPRTYDESC//\"}"
	# VOUTS=$(bitcoin-cli getrawtransaction $TXID true | jq -r '.vout[] | select(.scriptPubKey.asm | contains("OP_RETURN")) | .n')
	if [[ -n "$CNTRPRTYDESC" && "$CNTRPRTYDESC" != ""null"" ]]; then 
		echo $CNTRPRTYDESC
	fi
        #echo "$BLOCK - $TRXID"	
	if [[ "$TRXID" == "3e034d5522e5c4abd9466ad5e9ca340ded72bafad413dd4c1c2583e801e751ff" ]]; then
		echo "FOUNDIT"
	fi
        #for VOUT in $VOUTS
        #do
        #    ADDRESS=$(bitcoin-cli getrawtransaction $TXID true | jq -r ".vout[$VOUT].scriptPubKey.addresses[0]")
        #    VALUE=$(bitcoin-cli getrawtransaction $TXID true | jq -r ".vout[$VOUT].value")
        #    TIMESTAMP=$(date +%s)
        #    DATA=$(bitcoin-cli getrawtransaction $TXID true | extract_data)
        #    if [ ! -z "$DATA" ]; then
        #        sqlite3 $DATABASE "INSERT INTO stamps (txid, vout, address, value, timestamp, stamp) VALUES ('$TXID', $VOUT, '$ADDRESS', $VALUE, $TIMESTAMP, '$DATA');"
        #        echo "Stamp added: $TXID:$VOUT"
        #    fi
        #done
    done

	LASTBLOCK=$BLOCK
#done
