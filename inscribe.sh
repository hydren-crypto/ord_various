#!/bin/bash

file="${1}"
shift
fee="${1:=4}"
shift

get_unconfirmed_trx(){
    ord wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq
}

#for i in $(ord wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq); do bitcoin-cli getrawtransaction "$i"; done
# check aws access key: aws configure get aws_access_key_id

check_confirmation(){
    txid=$1
    echo "Checking if transaction $txid is confirmed"
    while true; do
        sleep 60
        is_confirmed=$(bitcoin-cli getrawtransaction "$txid" 1)
        if [[ $is_confirmed =~ "confirmations" ]]; then
            echo "Transaction $txid is confirmed"
            break
        fi
    done
}

check_balance(){
    wallet_balance=$(ord wallet balance)
    if [ "$wallet_balance" -gt 0 ]; then
        echo "Balance is greater than 0"
    else 
        echo "Balance is not greater than 0"
        exit
    fi
}


fetch_json_log(){
    aws s3 cp s3://hydren.io/inscribed/${inscribe_log} .
}

prep_json_to_log(){
    sed -i '/\]/d' ${inscribe_log} # Strip trailing ]
    echo "," >> ${inscribe_log}
}

close_json_file(){
    echo "]" >> ${inscribe_log}
    ## jq . ${inscribe_log} | sponge ${inscribe_log} # beautify
}

send_file_to_aws(){  # ORIGINAL_NAME  TARGET_NAME
    aws s3 cp "${1}" s3://hydren.io/inscribed/${2:=$1}
}

get_aws_url(){
    #potentially add a direct reference for the file
    aws s3 presign s3://hydren.io/inscribed/${1} --expires-in 604800  #1 week
}    

tmp_file=tmp_out.txt
confirm_file=confirmations.txt
inscribe_log=inscribe_log.txt

mkdir "./done" 2> /dev/null

check_balance
echo "proceeding with ${file} and a fee rate of ${fee}"

ord wallet inscribe ${file} --fee-rate ${fee} &> $tmp_file
ord_success=$?

if [[ ${ord_success} -eq 0 ]]; then
    confirmation=$(cat ${tmp_file}  | jq -r '.commit')
    inscription=$(cat ${tmp_file} | jq -r '.inscription')
    inscr_url=https://ordinals.com/inscription/$inscription
    echo "Confirmation: http://mempool.space/tx/${confirmation}"
    
    # check_confirmation ${confirmation}
    send_file_to_aws "${file}" "${inscription}_${file}" && mv "${file}" ./done/${inscription}_${file}
    aws_url=$(get_aws_url "${inscription}_${file}")
    fetch_json_log # download from aws to append
    prep_json_to_log   
    cat ${tmp_file} | jq --arg file "$file"  '. + {"filename": $file}' | \
	    jq --arg fee "$fee" '. + {"fee_rate": $fee}' | \
	    jq --arg aws_url "$aws_url" '. + {"aws_url": $aws_url}' | \
	    jq --arg explorer "$inscr_url" '. + {"explorer": $explorer}' >> ${inscribe_log}
    close_json_file
    send_file_to_aws "${inscribe_log}" "${inscribe_log}" 
else
    echo "Unsuccessful inscription!"
    echo "$(cat tmp_file)"
fi


rm "${tmp_file}"
