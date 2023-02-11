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
    echo "checking wallet balance and syncing index if needed..."
    wallet_balance=$(ord wallet balance)
    if [ "$wallet_balance" -eq 0 ]; then
        echo "insufficient balance to inscribe. Bye! "
        exit
    fi
}

fetch_json_log(){
    aws s3 cp "${aws_s3_uri}"/"${aws_s3_dir}"/${inscribe_log} .
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
    aws s3 cp "${1}" "${aws_s3_uri}"/"${aws_s3_dir}"/${2:=$1}
}

invalidate_s3_file(){
    aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "{$1}"
}

get_aws_url(){
    #potentially add a direct reference for the file
    aws s3 presign "${aws_s3_uri}"/"${aws_s3_dir}"/${1} --expires-in 604800  #1 week
} 

usage(){
    echo "USAGE: $0 -f [fee rate] -d [description] FILENAME"
    echo ""
    echo " -f   | fee rate [default: ${fee_rate}]"
    echo " -d   | description [detault: filename-prefix] - identifier in JSON output"
    echo ""
    display_fee_rates
    exit 0
}

get_fee_rates

tmp_file=tmp_out.txt
inscribe_log=inscribe_log.json
fee_rate=$fee_rate_1440
aws_s3_uri=s3://hydren.io
aws_s3_dir=inscribed
ord_description=""
skipcheck=false

while [[ $1 =~ ^- ]]; do
    case $1 in
        "--skip"|"--s")
            skipcheck=true
            ;;
        "--fee"|"-f")
            shift
            fee_rate=$1
            ;;
        "--description"|"-d")
            shift
            ord_description=$1
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

root_filename=${cmdline_filename%.*}
if [ -z "$ord_description" ]; then
  ord_description="$root_filename"
fi

mkdir "./done" 2> /dev/null

check_balance

echo "Proceeding with a fee rate of ${fee_rate}"
display_fee_rates
[[ "$skipcheck" = true ]] || read -p "Press enter to continue..."


ord wallet inscribe ${cmdline_filename} --fee-rate ${fee_rate} &> $tmp_file
ord_success=$?

if [[ ${ord_success} -eq 0 ]]; then
    filesize=$(stat -c%s ${cmdline_filename})
    confirmation=$(cat ${tmp_file}  | jq -r '.commit')
    inscription=$(cat ${tmp_file} | jq -r '.inscription')
    inscr_url=https://ordinals.com/inscription/$inscription
    echo "Confirmation: http://mempool.space/tx/${confirmation}"
    
    # check_confirmation ${confirmation}
    send_file_to_aws "${cmdline_filename}" "${inscription}_${cmdline_filename}" && mv "${cmdline_filename}" ./done/${inscription}_${cmdline_filename}
    aws_url=$(get_aws_url "${inscription}_${cmdline_filename}")
    fetch_json_log # download from aws to append
    prep_json_to_log   
    cat ${tmp_file} | jq --arg file "$cmdline_filename"  '. + {"filename": $file}' | \
        jq --arg fee_rate "$fee_rate" '. + {"fee_rate": $fee_rate}' | \
        jq --arg aws_url "$aws_url" '. + {"aws_url": $aws_url}' | \
        jq --arg explorer "$inscr_url" '. + {"explorer": $explorer}' | \
        jq --arg description "$ord_description" '. + {"description": $description}' | \
        jq --arg filesize "$filesize" '. + {"filesize": $filesize}' >> ${inscribe_log}
    close_json_file
    send_file_to_aws "${inscribe_log}" "${inscribe_log}"
    aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths /${aws_s3_dir}/${inscribe_log}
else
    echo "Unsuccessful inscription!"
    echo "$(cat $tmp_file)"
fi

rm "${tmp_file}"