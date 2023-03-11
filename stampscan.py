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
  output = (response.text)
  dumps = json.dumps(output)
#  data = json.loads(dumps.encode('utf-8'))
  data = json.loads(dumps)
  print(data)
  #result = data["result"]


#get_flocks(list(range(779652, blockend)))

blockrange = list(range(blockstart,blockend))

for i in range(0, len(blockrange), 249):
      get_flocks(blockrange[i:i+249])
