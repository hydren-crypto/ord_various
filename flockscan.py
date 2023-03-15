

import json
import time
import base64
import magic
import os
import boto3
import requests
import subprocess
import pprint
from requests.auth import HTTPBasicAuth

# FIXME: need to check if stamp_base64 is a valid base64 string, if not it won't become a stamp
# this will exclude the initial tests with text in the string suck as stamp:"data:image/png;base64,[base64]" 
# this exclusion / malformatting can be tested with stamps prior to block 779652

aws_access_key_id = ""
aws_secret_access_key = ""
aws_cloudfront_distribution_id = ""
cntrprty_user = "rpc"
cntrprty_password = "rpc"
cntrprty_api_url = "http://api.counterparty.io:4000/api/"

# import private vars, may over-ride the above
if os.path.exists('private_vars.py'):
    from private_vars import *

# if the aws_cloudfront_distribution_id is not set these will be ignored
aws_s3_bucketname = "stampchain.io"
aws_s3_dir = "stamps/"

# saved in script dir
json_output = "stamp.json"

# the first official stamps
blockstart = 779652
blockend = int(subprocess.check_output(['fednode', 'exec', 'bitcoin', 'bitcoin-cli', 'getblockcount']).decode('utf-8'))
blockrange = list(range(blockstart,blockend))

# API VARS
headers = {'content-type': 'application/json'}
auth = HTTPBasicAuth(cntrprty_user, cntrprty_password)

s3_client = boto3.client(
    's3',
    aws_access_key_id=aws_access_key_id,
    aws_secret_access_key=aws_secret_access_key
    )


       
def convert_base64_to_file(base64_string, item):
    binary_data = base64.b64decode(base64_string)
    if type(base64_string) != str:
        print(base64_string)
        return "invalid_base64"
    file_type = magic.from_buffer(binary_data, mime=True)
    _, file_extension = file_type.split("/")
    tx_hash = item.get("tx_hash")
    filename = f"{tx_hash}.{file_extension}"
    with open(filename, "wb") as f:
        f.write(binary_data)
    item["stamp_url"] = "https://" + aws_s3_bucketname + "/" + aws_s3_dir  + filename
    return filename

def get_s3_objects(bucket_name, s3_client):
    result = []
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=bucket_name)
    
    for page in pages:
        if 'Contents' in page:
            for obj in page['Contents']:
                result.append(obj['Key'])
    
    return result

def invalidate_s3_file(file_path):
    command = ["aws", "cloudfront", "create-invalidation", "--distribution-id", aws_cloudfront_distribution_id, "--paths", file_path]
    subprocess.run(command, stdout=subprocess.DEVNULL)

def upload_file_to_s3_aws_cli(file_path, bucket_name, s3_path):
    subprocess.run(["aws", "s3", "cp", file_path, f"s3://{bucket_name}/{s3_path}"], stdout=subprocess.DEVNULL)
    return True

def upload_file_to_s3_boto3(file_path, bucket_name, s3_key, s3_client):
    with open(file_path, 'rb') as f:
        s3_client.upload_fileobj(f, bucket_name, s3_key)

def convert_json_array_files(json_string_array, bucket_name, s3_path):
    json_dict = json.loads(json_string_array)
    for item in json_dict:
        base64_string = item.get("stamp_base64")
        file_path = convert_base64_to_file(base64_string, item)
        if upload_file_to_s3_aws_cli(file_path, bucket_name, s3_path):
            os.remove(file_path)

    return json.dumps(json_dict)

def get_flocks(block_indexes):
  payload = {
    "method": "get_blocks",
    "params": {
             "block_indexes": block_indexes
              },
    "jsonrpc": "2.0",
    "id": 0
  }
  response = requests.post(cntrprty_api_url, data=json.dumps(payload), headers=headers, auth=auth)
  output = response.text
  data = json.loads(output)
  result = data["result"]
  output_list = []
  for i in range(len(result)):
    block_data = result[i]
    messages = block_data["_messages"]
    for message in messages:
      # in message index [9142396,9142291] there is no identifying difference in the category  or command ffield
      # only the  lock status  changed from false to true. the simplest method is to only allow the first trx of the asseet in as a stamp
      # this also means that if a user creates an asset with lock = fales and a blank description field. then they
      # add a stamp: formatted description and change the lock status to true it would then be counted as a stamp.

      if message["category"] == "issuances" and message["command"] == "insert":
        bindings = message["bindings"]
        # and an iff bindings["status"] == "valid"  ?
        description = json.loads(bindings)["description"]
        if description.lower().find("stamp:") != -1:
          stamp_search = description[description.lower().find("stamp:")+6:]
          stamp_base64 = stamp_search.strip() if len(stamp_search) > 1 else None  
          bindings = json.loads(bindings)
          asset = bindings["asset"]
          # Check if the asset already exists in the output_list
          if not any(item["bindings"]["asset"] == asset for item in output_list):
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

  json_string = json.dumps(sorted_list, indent=4)

  flattened_list = []
  for message in sorted_list:
      flattened_dict = {}
      # flattened_dict["description"] = message["bindings"]["description"]
      flattened_dict["stamp"] = message["stamp"]
      flattened_dict["message_index"] = message["message_index"]
      flattened_dict["block_index"] = message["block_index"]
      flattened_dict["tx_hash"] = message["bindings"]["tx_hash"]
      flattened_dict["asset"] = message["bindings"]["asset"]
      flattened_dict["asset_longname"] = message["bindings"]["asset_longname"]
      flattened_dict["block_index"] = message["bindings"]["block_index"]
      flattened_dict["tx_index"] = message["bindings"]["tx_index"]
      flattened_dict["stamp_base64"] = message["bindings"]["stamp_base64"]
      flattened_list.append(flattened_dict)

  #json_string = json.dumps(flattened_list, indent=4)
  #print(json_string)

  return flattened_list # Return the flattened list


combined_list = []
for i in range(0, len(blockrange), 249):
    combined_list += get_flocks(blockrange[i:i+249])

i = 0
for message in combined_list:
  message["stamp"] = i
  i += 1


json_string = json.dumps(combined_list, indent=4)
final_array_with_url=(convert_json_array_files(json_string,aws_s3_bucketname,aws_s3_dir))
print(final_array_with_url)

with open(json_output, 'w') as f:
    f.write(final_array_with_url)

if aws_secret_access_key != "" and aws_acccess_key_id != "":
# pending check for existing file list, we will not upload if it exists
    s3_client = boto3.client(
        's3',
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key
        )
    s3_objects = get_s3_objects(bucket_name, s3_client)
    # s3_key should be == to stamps/txid.png
    if s3_key not in s3_objects:
        print(f'Uploading {local_file_path} to {s3_key}')
        upload_file_to_s3(local_file_path, bucket_name, s3_key, s3_client)


if aws_s3_bucketname != "" and aws_s3_dir != "" and aws_cloudfront_distribution_id != "":
    upload_file_to_s3_aws_cli(json_output,aws_s3_bucketname,"")
    # can purge local file upon successful upload
    # os.remove(json_output)
    invalidate_s3_file("/" + json_output)
