
import json
import os
import requests
import subprocess
import pprint
from requests.auth import HTTPBasicAuth


CNTRPRTY_PASSWORD = "rpc"

blockstart = 779652
blockend = int(subprocess.check_output(['fednode', 'exec', 'bitcoin', 'bitcoin-cli', 'getblockcount']).decode('utf-8'))

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
          stamp_data = description.split("Stamp:")[1].strip() if len(description.split("Stamp:")) > 1 else None # add this line
          #stamp_data = description.split("Stamp:")[1].strip() # add this line
          bindings = json.loads(bindings)
          message["bindings"] = {
            "description": bindings["description"],
            "tx_hash": bindings["tx_hash"],
            "asset": bindings["asset"],
            "asset_longname": bindings["asset_longname"],
            "block_index": bindings["block_index"],
            "status": bindings["status"],
            "tx_index": bindings["tx_index"],
            "stamp_data": stamp_data # add this line
          }
          output_list.append(message)
  json_string = json.dumps(output_list, indent=4)
  print(json_string)


#get_flocks(list(range(779652, blockend)))

blockrange = list(range(blockstart,blockend))

for i in range(0, len(blockrange), 249):
      get_flocks(blockrange[i:i+249])