#!/bin/bash

# POST ordsea.io/api/create 
# json: { inscription, proof, price, contact }

# jq '.[] | select(.description | contains("FLOON")) | .inscription' < inscribe_log.json

get_address(){
    address=$(curl -s  https://ordapi.xyz/inscription/"$1" | jq .address)
}

inscription_id=$1
ordsea_create_api="https://ordsea.io/api/create"
get_address
proof=$(bitcoin-cli signmessage "$address" "$inscription_id 0")
contact="@mrarwyn"
price="0.42"

echo "proof: $proof"

curl -d '{"inscription":"$inscription", "proof":"$proof", "price":"$price", "contact":"$contact"}' -H "Content-Type: application/json" -X POST $ordsea_create_api