#!/bin/bash
# POST ordsea.io/api/create 
# json: { inscription, proof, price, contact }

# jq '.[] | select(.description | contains("FLOON")) | .inscription' < inscribe_log.json
get_address(){
    address=$(curl -s  https://ordapi.xyz/inscription/$1 | jq .address)
}

get_description(){
    echo=$1
    description=$(jq --arg desc "$1" '.[] | select(.inscription == $desc) | .description' $inscribe_log)
}

inscription_id=$1
shift

inscription_stripped=${inscription_id//\"/}
ordsea_create_api="https://ordsea.io/api/create"
inscribe_log=inscribe_log.json

get_address $inscription_stripped
get_description $inscription_stripped

noquote_address=${address//\"/}
proof=$(bitcoin-cli signmessage "$noquote_address" "$inscription_stripped 0")
contact="@mrarwyn"
price="0.42"

echo "ins: $inscription_stripped"
echo "address-unused: $address"
echo "proof: $proof"
echo "description: $description"

#curl -d '{"inscription":"'"$inscription_stripped"'", "proof":"'"$proof"'", "price":"'"$price"'", "contact":"'"$contact"'", "description":""}' -H 'Content-Type: application/json' -X POST $ordsea_create_api
echo "" 
