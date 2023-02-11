#!/bin/bash

# wrapper around ord to save log files in json to aws
# simplifies mult-file inscription processing

# perhaps we add functionality to launch in subshells and trigger something
# when the inscription is confirmed? 

get_unconfirmed_trx(){
    ord wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq
}

#for i in $(ord wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq); do bitcoin-cli getrawtransaction "$i"; done
# check aws access key: aws configure get aws_access_key_id

get_fee_rates(){
    # checking for 1440 minutes / 24hr
    # see: https://bitcoiner.live/doc/api
    fee_rate_1440=$(curl -s https://bitcoiner.live/api/fees/estimates/latest | jq '.estimates."1440".sat_per_vbyte')
    fee_rate_120=$(curl -s https://bitcoiner.live/api/fees/estimates/latest | jq '.estimates."120".sat_per_vbyte')
}

display_fee_rates(){
    echo " current fee rates:"
    echo "   1440: $fee_rate_1440"
    echo "   120:  $fee_rate_120"
}

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
    aws s3 cp "${aws_s3_uri}"/${inscribe_log} .
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
    aws s3 cp "${1}" "${aws_s3_uri}"/${2:=$1}
}

get_aws_url(){
    #potentially add a direct reference for the file
    aws s3 presign "${aws_s3_uri}"/${1} --expires-in 604800  #1 week
} 

usage(){
    echo "USAGE: $0 -f [fee rate] -d [description] FILENAME"
    echo ""
    echo " -f   | fee rate [ default: ${fee_rate}]"
    echo " -d   | description - used for an identifier in the JSON output"
    echo ""
    display_fee_rates
    exit 0
}

check_balance
get_fee_rates

tmp_file=tmp_out.txt
inscribe_log=inscribe_log.json
fee_rate=$fee_rate_1440
aws_s3_uri=s3://hydren.io/inscribed

while [[ $1 =~ ^- ]]; do
    case $1 in
        "--fee"|"-f")
            shift
            fee_rate=$1
            ;;
        "--description"|"-d")
            shift
            ord_description=$1
            ;;
        "--check"|"-c")
            CHECKONLY=true
            ;;
        *)
            echo "Unknown option $1"
            echo; usage
            exit 1
            ;;
    esac
    shift
done

if [ $# -eq 0 ]; then
 usage
fi

cmdline_filename=$1
shift

mkdir "./done" 2> /dev/null


echo "Proceeding with a fee rate of ${fee_rate}"
display_fee_rates
read -p "Press enter to continue..."


ord wallet inscribe ${cmdline_filename} --fee-rate ${fee_rate} &> $tmp_file
ord_success=$?

if [[ ${ord_success} -eq 0 ]]; then
    confirmation=$(cat ${tmp_file}  | jq -r '.commit')
    inscription=$(cat ${tmp_file} | jq -r '.inscription')
    inscr_url=https://ordinals.com/inscription/$inscription
    echo "Confirmation: http://mempool.space/tx/${confirmation}"
    
    # check_confirmation ${confirmation}
    send_file_to_aws "${cmdline_filename}" "${inscription}_${cmdline_filename}" && mv "${cmdline_filename}" ./done/${inscription}_${cmdline_filename}
    aws_url=$(get_aws_url "${inscription}_${cmdline_filename}")
    fetch_json_log # download from aws to append
    prep_json_to_log   
    cat ${tmp_file} | jq --arg file "$cmdline_filename"  '. + {"filename": $cmdline_filename}' | \
        jq --arg fee_rate "$fee_rate" '. + {"fee_rate": $fee_rate}' | \
        jq --arg aws_url "$aws_url" '. + {"aws_url": $aws_url}' | \
        jq --arg explorer "$inscr_url" '. + {"explorer": $explorer}' | \
        jq --arg description "$ord_description" '. + {"description": $description}' >> ${inscribe_log}
    close_json_file
    send_file_to_aws "${inscribe_log}" "${inscribe_log}" 
else
    echo "Unsuccessful inscription!"
    echo "$(cat $tmp_file)"
fi

rm "${tmp_file}"