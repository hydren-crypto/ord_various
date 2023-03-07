#!/bin/bash
# Wrapper script for 'ord' to save log files in JSON format, and optionally upload to AWS S3.
# This simplifies multi-file inscription processing and creates a more complete JSON log, which includes filename and an optional inscription description/collection name. The default description is the short filename - e.g. Ordinalien42.jpg will get a description of Ordinalien42. This provides additional data over the 'ord wallet inscription' command for future processing.

# REQUIREMENTS: 
# - Fully functional ord wallet - i.e. 'ord wallet balance' displays a value
# - jq must be installed on the host for proper logging

# OPTIONAL ENVIRONMENT VARIABLES:
# - Create a .env file with your variables for the following:
#    - CLOUDFRONT_ID=<your cloudfront ID>
#    - aws_s3_uri=s3://hydren.io
#    - aws_s3_dir=inscribed

# Note: If these values are not defined, we will not upload the inscribe_log to AWS S3. The inscribe_log will still be maintained

check_balance(){ 
    echo "checking wallet balance and syncing index if needed..."
    wallet_balance=$(ord --wallet $wallet_name ${ord_args} wallet balance | jq '.cardinal')
    wallet_balance_btc=$(echo "$wallet_balance * 0.00000001" | bc)
    if [ "$wallet_balance" -eq 0 ]; then
        echo "insufficient balance to inscribe. Bye! "
        exit
    fi
}

check_bitcoin_cli_balance(){
    bcli_balance=$(bitcoin-cli ${bitcoin_cli_args} -getinfo | grep "Balance:" | awk '{print $2}')
}

check_confirmation(){
    txid=$1
    echo "Checking if transaction $txid is confirmed"
    while true; do
        sleep 60
        is_confirmed=$(bitcoin-cli ${bitcoin_cli_args} getrawtransaction "$txid" 1)
        if [[ $is_confirmed =~ "confirmations" ]]; then
            echo "Transaction $txid is confirmed"
            break
        fi
    done
}

close_json_file(){
    echo "]" >> ${inscribe_log}
    ## jq . ${inscribe_log} | sponge ${inscribe_log} # beautify - this requires sponge
}

display_fee_rates(){
    echo " current fee rates:"
    echo "   1440: $fee_rate_1440"
    echo "   120:  $fee_rate_120"
}

fetch_json_log(){
    aws s3 cp "${aws_s3_uri}"/"${aws_s3_dir}"/${inscribe_log} .
}

get_aws_url(){
    #potentially add a direct reference for the file
    aws s3 presign "${aws_s3_uri}"/"${aws_s3_dir}"/${1} --expires-in 604800  #1 week
} 

get_count_of_inscriptions(){
    jq '.[] | .inscription'  ${inscribe_log} | wc -l
}

get_fee_rates(){
    # checking for 1440 minutes / 24hr
    # see: https://bitcoiner.live/doc/api
    fee_rate_1440=$(curl -s https://bitcoiner.live/api/fees/estimates/latest | jq '.estimates."1440".sat_per_vbyte')
    fee_rate_120=$(curl -s https://bitcoiner.live/api/fees/estimates/latest | jq '.estimates."120".sat_per_vbyte')
    btc_price_usd=$(curl -s 'https://api.coindesk.com/v1/bpi/currentprice/USD.json' | jq '.bpi.USD.rate_float')
}

get_unconfirmed_trx(){
    ord --wallet $wallet_name ${ord_args} wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq
}

invalidate_s3_file(){
    aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "{$1}"
}

prep_json_to_log(){
    sed -i '/\]/d' ${inscribe_log} # Strip trailing ]
    echo "," >> ${inscribe_log}
}

send_file_to_aws(){  # ORIGINAL_NAME  TARGET_NAME
    aws s3 cp "${1}" "${aws_s3_uri}"/"${aws_s3_dir}"/${2:=$1}
}

usage(){
    echo "Usage: $0 [--description|-d] [--fee|-f] [--skip|-s] FILENAME"
    echo "  --description|-d: description of the file"
    echo "  --fee|-f: fee rate to use (default: $fee_rate)"
    echo "  --skip|-s: skip confirmation check"
    echo "  --wallet|-w: wallet name (default: $wallet_name)"
    echo "  FILENAME: file to inscribe"
    echo ""
    display_fee_rates
    echo ""
    echo "ord wallet balance BTC: $wallet_balance_btc"
    echo "ord wallet balance SAT: $wallet_balance"
    echo "bitcoin-cli balance: $bcli_balance"
    echo ""
    exit 0
}

#for i in $(ord wallet transactions | grep -E '\s0$' | awk '{ print $1 }' | uniq); do bitcoin-cli getrawtransaction "$i"; done
# check aws access key: aws configure get aws_access_key_id

get_fee_rates # for definition of the default fee_rate if undefined

bitcoin_cli_args=${BITCOIN_CLI_ARGS}
ord_args=${ORD_ARGS} # Set ENV Var
ord_version=$(ord --version | cut -d ' ' -f 2)
wallet_name=ord
tmp_file=tmp_out.txt
inscribe_log=inscribe_log.json
fee_rate=${fee_rate_1440:=4}
ord_description=""
skipcheck=false
ord_explorer_url=https://ordinals.com/inscription/
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${script_dir}/.env

while [[ $1 =~ ^- ]]; do
    case $1 in
	"--check-fee"|"-cf")
            get_fee_rates
            display_fee_rates
	    exit 0
	    ;;
        "--description"|"-d")
            shift
            ord_description=$1
            ;;
        "--fee"|"-f")
            shift
            fee_rate=$1
            ;;
        "--skip"|"-s")
            skipcheck=true
            ;;
        "--wallet"|"-w")
            shift
            wallet_name=$1
            ;;
        "--help"|"-h")
            usage
            ;;
        *)
            echo "Unknown option $1"
            echo; usage
            exit 1
            ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but it's not installed.  Aborting."; exit 1; }


check_balance
check_bitcoin_cli_balance

if [ $# -eq 0 ]; then
 usage
fi

if [ -n "${CLOUDFRONT_ID}" ] && [ -n "${aws_s3_uri}" ] && [ -n "${aws_s3_dir}" ]; then
   echo "$inscribe_log will be sent to AWS S3"
   aws_upload=true
else
   echo "AWS S3 vars undefined - we will not upload $inscribe_log to AWS"
   aws_upload=false
fi

cmdline_filename=$1
shift

if [ ! -f "$cmdline_filename" ]; then
    echo "File $cmdline_filename does not exist"
    exit 1
fi

root_filename=${cmdline_filename%.*}
if [ -z "$ord_description" ]; then
  ord_description="$root_filename"
fi

mkdir "${script_dir}/done" 2> /dev/null


display_fee_rates
echo "Proceeding with a fee rate of ${fee_rate}"
filesize=$(stat -c%s ${cmdline_filename})
btc_cost=$(echo "scale=8; (($filesize) / 4 * $fee_rate) * 0.00000001" | bc)
echo "Filesize: $filesize"
echo "BTC COST: $btc_cost"
usd_cost=$(echo "scale=8; $btc_cost * $btc_price_usd" | bc)
echo "USD COST: $usd_cost"

[ "$skipcheck" = true ] || read -p "Press enter to continue...";

## Inscribe
ord --wallet $wallet_name ${ord_args} wallet inscribe ${cmdline_filename} --fee-rate ${fee_rate} &> $tmp_file
ord_success=$?

if [[ ${ord_success} -eq 0 ]]; then
    confirmation=$(cat ${tmp_file}  | jq -r '.commit')
    inscription=$(cat ${tmp_file} | jq -r '.inscription')
    inscr_url=${ord_explorer_url}/$inscription
    echo "Confirmation: http://mempool.space/tx/${confirmation}"
    
    # check_confirmation ${confirmation} details here
    
    # previously we were getting a presigned URL from AWS to add to the JSON:
    # aws_url=$(get_aws_url "${inscription}_${cmdline_filename}")
    # jq --arg aws_url "$aws_url" '. + {"aws_url": $aws_url}' | \
    
    if [ -f ${inscribe_log} ]; then
        echo "Appending to existing $inscribe_log in current directory"
        prep_json_to_log # this assumes $inscribe_log already contains an array
    else
        echo "Fetching log from aws"
        if [ "$aws_upload" = true ]; then
            fetch_json_log # download from aws to append
            prep_json_to_log # this assumes $inscribe_log already conatins an array
        else
            echo "[" > $inscribe_log
        fi
    fi
       
    time_now=$(date +"%Y%m%d_%H:%M")UTC
    status="inscribed-${time_now}"
    cat ${tmp_file} | jq --arg file "$cmdline_filename"  '. + {"filename": $file}' | \
        jq --arg fee_rate "$fee_rate" '. + {"fee_rate": $fee_rate}' | \
        jq --arg explorer "$inscr_url" '. + {"explorer": $explorer}' | \
        jq --arg description "$ord_description" '. + {"description": $description}' | \
        jq --arg filesize "$filesize" '. + {"filesize": $filesize}' | \
        jq --arg status "$status" '. + {"status": $status}' >> ${inscribe_log}
    close_json_file
    if [ "$aws_upload" = true ]; then
        send_file_to_aws "${cmdline_filename}" "${inscription}_${cmdline_filename}"
        send_file_to_aws "${inscribe_log}" "${inscribe_log}"
        aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths /${aws_s3_dir}/${inscribe_log}
    fi
    mv "${cmdline_filename}" ${script_dir}/done/${inscription}_${cmdline_filename}
else
    echo "Unsuccessful inscription!"
    echo "$(cat $tmp_file)"
fi

rm "${tmp_file}"
