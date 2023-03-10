import json
import os
import requests
import subprocess
from requests.auth import HTTPBasicAuth


CNTRPRTY_PASSWORD = "rpc"
blockcount = int(subprocess.check_output(['fednode', 'exec', 'bitcoin', 'bitcoin-cli', 'getblockcount']).decode('utf-8'))

url = "http://localhost:4000/api/"
headers = {'content-type': 'application/json'}
auth = HTTPBasicAuth('rpc', CNTRPRTY_PASSWORD)

def make_request(method, block_index):
  payload = {
    "method": method,
    "params": {
             "block_indexes": [block_index]
              },
    "jsonrpc": "2.0",
    "id": 0
  }
  response = requests.post(url, data=json.dumps(payload), headers=headers, auth=auth)
  output = (response.text)
  #print(response.text)
  dumps = json.dumps(output)
  #print(dumps)
  data = json.loads(dumps.encode('utf-8'))
  print(data)

for block_list in range(779652, blockcount):
 make_request("get_blocks",block_list)
