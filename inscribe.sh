#!/bin/bash

file=${1}
shift
fee=${1}
shift

get_unconfirmed_trx(){
    ord wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq
}

#for i in $(ord wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq); do bitcoin-cli getrawtransaction "$i"; done

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


tmp_file=tmp_out.txt
confirm_file=confirmations.txt
inscribe_log=inscribe_log.txt

mkdir "./done" 2> /dev/null

check_balance
echo "proceeding with ${file} and a fee rate of ${fee:=4}"

ord wallet inscribe ${file} --fee-rate ${fee:=4} &> $tmp_file
ord_success=$?

if [[ ${ord_success} -eq 0 ]]; then
    confirmation=$(cat ${tmp_file}  | jq -r '.commit')
    cat ${tmp_file} | jq '. + {"filename": "${file}"}' | jq '. + {"fee_rate": "${fee:=4}"}'  >> ${inscribe_log}
    rm ${tmp_file}
    echo "Confirmation: ${confirmation}"
    echo "${confirmation}  ${file}" >> ${confirm_file}
    # check_confirmation ${confirmation}
    mv "${file}" ./done/
    aws s3 cp ${inscrobe_log}  s3://hydren.io
else
    echo "Unsuccessful command!"
    echo "${tmp_file}"
fi


