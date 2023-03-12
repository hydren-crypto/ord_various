import json
import os
import requests
import subprocess
import pprint
from requests.auth import HTTPBasicAuth


CNTRPRTY_PASSWORD = "rpc"

blockstart = 779652
blockend = int(subprocess.check_output(['fednode', 'exec', 'bitcoin', 'bitcoin-cli', 'getblockcount']).decode('utf-8'))
blockrange = list(range(blockstart,blockend))

url = "http://localhost:4000/api/"
headers = {'content-type': 'application/json'}
auth = HTTPBasicAuth('rpc', CNTRPRTY_PASSWORD)

def get_flocks(block_indexes):
  payload = {
    "method": "get_blocks",
    "params": {
             "block_indexes": block_indexes
              },
    "jsonrpc": "2.0",
    "id": 0
  }
  response = requests.post(url, data=json.dumps(payload), headers=headers, auth=auth)
  output = response.text
  data = json.loads(output)
  result = data["result"]
  output_list = []
  for i in range(len(result)):
    block_data = result[i]
    messages = block_data["_messages"]
    for message in messages:
      if message["category"] == "issuances":
        bindings = message["bindings"]
        description = json.loads(bindings)["description"]
        if "stamp:" in description.lower():
          
          stamp_search = description.lower().split("stamp:")[1]
          stamp_base64 = stamp_search.strip() if len(stamp_search) > 1 else None
          bindings = json.loads(bindings)
          message["bindings"] = {
            "description": bindings["description"],
            "tx_hash": bindings["tx_hash"],
            "asset": bindings["asset"],
            "asset_longname": bindings["asset_longname"],
            "block_index": bindings["block_index"],
            "status": bindings["status"],
            "tx_index": bindings["tx_index"],
            "stamp_base64": stamp_base64 # add this line                                                       
          }
          output_list.append(message)

  # Sort the list by message_index
  sorted_list = sorted(output_list, key=lambda k: k['message_index'])

  # Add a new "stamp" key-value pair to the dictionary
  i = 0
  for message in sorted_list:
    message["stamp"] = i
    i += 1

  # Print the formatted JSON string
  json_string = json.dumps(sorted_list, indent=4)
  #print(json_string)

  flattened_list = []
  for message in sorted_list:
      flattened_dict = {}
      #flattened_dict["description"] = message["bindings"]["description"]
      flattened_dict["message_index"] = message["message_index"]
      flattened_dict["block_index"] = message["block_index"]
      flattened_dict["tx_hash"] = message["bindings"]["tx_hash"]
      flattened_dict["asset"] = message["bindings"]["asset"]
      flattened_dict["asset_longname"] = message["bindings"]["asset_longname"]
      flattened_dict["block_index"] = message["bindings"]["block_index"]
      flattened_dict["tx_index"] = message["bindings"]["tx_index"]
      flattened_dict["stamp_base64"] = message["bindings"]["stamp_base64"]
      flattened_list.append(flattened_dict)

  # Print the formatted JSON string
  #json_string = json.dumps(flattened_list, indent=4)
  #print(json_string)

  return flattened_list # Return the flattened list


# Combine the results of all the calls into one list
combined_list = []
for i in range(0, len(blockrange), 249):
      combined_list += get_flocks(blockrange[i:i+249])

# Print the combined list
json_string = json.dumps(combined_list, indent=4)
print(json_string)
