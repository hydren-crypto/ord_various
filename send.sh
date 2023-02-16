#!/bin/bash

# wrapper on ord to send and log json output

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

usage(){
    echo "Usage: $0 [--fee|-f <fee_rate>] [--skip|-s] <to_address> <inscription>"
    echo "  --description|-d <description> - description of send"
    echo "  --fee|-f <fee_rate>  - fee rate to use (default: $fee_rate)"
    echo "  --skip|-s            - skip confirmation"
    echo "  <to_address>         - address to send to"
    echo "  <inscription>        - inscription to send"
    exit 0
}

get_fee_rates

tmp_file=tmp_send_out.txt
inscribe_log=inscribe_log.json
fee_rate=$fee_rate_1440
skipcheck=false
wallet_name=ord
send_description=_

while [[ $1 =~ ^- ]]; do
    case $1 in
       "--description"|"-d")
            shift
            send_description=$1
            ;;
        "--fee"|"-f")
            shift
            fee_rate=$1
            ;;
        "--skip"|"-s")
            skipcheck=true
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

to_address=$1
shift
inscription=$1
shift

if [ -z "$to_address" ]; then
  echo "ERROR: to_address not specified"
  exit 1
fi

if [ -z "$inscription" ]; then
  echo "ERROR: inscription not specified"
  exit 1
fi

echo "Proceeding with a fee rate of ${fee_rate}"
display_fee_rates
[ "$skipcheck" = true ] || read -p "Press enter to continue...";


confirmation=$(ord --wallet $wallet_name wallet send $to_address $inscription --fee-rate $fee_rate 2>&1)
send_status=$?
if [[ $send_status -eq 0 ]]; then
    echo "Successful confirmation: $confirmation"
    # jq --arg inscription "$inscription" '.[] | select(.inscription == $inscription)' $inscribe_log
    echo "Updating $inscribe_log with confirmation"
    success_status="sent-$send_description-$confirmation-to-$to_address"
    jq --arg inscription "$inscription" --arg success_status "$success_status" 'map(if .inscription == $inscription then .status = $success_status else . end)' $inscribe_log > $tmp_file
#    mv $tmp_file $inscribe_log
else
    echo "Adding failure message to $inscribe_log"
    failed_status="failed-send-$send_description-$confirmation"
    echo "$confirmation"
    jq --arg inscription "$inscription" --arg failed_status "$failed_status" 'map(if .inscription == $inscription then .status = $failed_status else . end)' $inscribe_log > $tmp_file
#    mv $tmp_file $inscribe_log
fi

echo "THIS IS TESTING - SEE $tmp_file and copy to $inscribe_log manually if good" 
#rm "${tmp_file}"
