import json
from io import BytesIO
import io
import re
import time
import base64
import magic
import os
import boto3
from PIL import Image
import requests
import subprocess
import pprint
from requests.auth import HTTPBasicAuth
import sys

# FIXME: need to check if stamp_base64 is a valid base64 string, if not it won't become a stamp
# this will exclude the initial tests with text in the string suck as stamp:"data:image/png;base64,[base64]" 
# this exclusion / malformatting can be tested with stamps prior to block 779652

# this script is intended to be run from block 779652 and build the entire stampchain
# modifications will be needed for a version to look at only current blocks and append to an existing stampchain

aws_access_key_id = ""
aws_secret_access_key = ""
aws_cloudfront_distribution_id = ""
cntrprty_user = "rpc"
cntrprty_password = "rpc"
cntrprty_api_url = "http://127.0.0.1:4000/api/"
blockchain_api_url = "https://blockchain.info/"
diskless = True # if True, will not save stamps to disk and upload them directly to s3

# import private vars, may over-ride the above
if os.path.exists('private_vars.py'):
    from private_vars import *

# if the aws_cloudfront_distribution_id is not set these will be ignored
aws_s3_bucketname = "stampchain.io"
aws_s3_image_dir = "stamps/"
s3_client = boto3.client(
    's3',
    aws_access_key_id=aws_access_key_id,
    aws_secret_access_key=aws_secret_access_key
    )


# saved in script dir
json_output = "stamp.json"

# the first official stamps
blockstart = 779652
blockend = requests.get(blockchain_api_url + 'q/getblockcount').json()
# blockend = int(subprocess.check_output(['fednode', 'exec', 'bitcoin', 'bitcoin-cli', 'getblockcount']).decode('utf-8'))
blockrange = list(range(blockstart,blockend))

# API VARS
headers = {'content-type': 'application/json'}
auth = HTTPBasicAuth(cntrprty_user, cntrprty_password)
       


def get_s3_objects(bucket_name, s3_client):
    result = []
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=bucket_name)
    
    for page in pages:
        if 'Contents' in page:
            for obj in page['Contents']:
                result.append(obj['Key'])
    
    return result

def is_base64_image(base64_string):
    try:
        image_data = base64.b64decode(base64_string)
        image = Image.open(io.BytesIO(image_data))
        image.verify()
        return True
    except Exception as e:
        print(f"Invalid base64 image string: {e}")
        return False

def invalidate_s3_file(file_path):
    command = ["aws", "cloudfront", "create-invalidation", "--distribution-id", aws_cloudfront_distribution_id, "--paths", file_path]
    subprocess.run(command, stdout=subprocess.DEVNULL)

def invalidate_s3_file(file_path, aws_cloudfront_distribution_id):
    client = boto3.client('cloudfront')
    response = client.create_invalidation(
        DistributionId=aws_cloudfront_distribution_id,
        InvalidationBatch={
            'Paths': {
                'Quantity': 1,
                'Items': [
                    file_path
                ]
            },
            'CallerReference': str(hash(file_path))
        }
    )
    return response


def convert_base64_to_file(base64_string, item, local_file_path=None):
    try:
        binary_data = base64.b64decode(base64_string)
        print(binary_data)
        file_type = magic.from_buffer(binary_data, mime=True)
        _, file_extension = file_type.split("/")
    except Exception as e:
        print(f"Error decoding base64 or detecting mime type: {e}")
        return None
    
    tx_hash = item["bindings"].get("tx_hash")
    filename = f"{tx_hash}.{file_extension}"
    print("FOUND FILENAME ", filename)
    s3_file_path = aws_s3_image_dir + filename

    if local_file_path is None and diskless:
        # Write the file directly to S3
        with BytesIO(binary_data) as file_obj:
            file_obj.seek(0)  # Reset the file pointer to the beginning
            upload_file_to_s3(file_obj, aws_s3_bucketname, s3_file_path, s3_client, diskless=True)
    else:
            with open(filename, "wb") as f:
                f.write(binary_data)
            local_file_path = filename

            upload_file_to_s3(local_file_path, aws_s3_bucketname, s3_file_path, s3_client)

    # Save the URL back to the array
    item["stamp_url"] = f"https://{aws_s3_bucketname}/{aws_s3_image_dir}{filename}"
    
    # Return the filename
    return filename if filename != 'None.png' else None 


def upload_file_to_s3(file_obj_or_path, bucket_name, s3_file_path, s3_client, diskless=False):
    try:
        if diskless:
            s3_client.upload_fileobj(file_obj_or_path, bucket_name, s3_file_path)
        else:
            s3_client.upload_file(file_obj_or_path, bucket_name, s3_file_path)
        #print(f'Successfully uploaded file to {bucket_name}/{s3_file_path}')
    except Exception as e:
        print(f"failure uploading to aws {e}")
    

def parse_json_array_convert_base64_to_file_and_upload(json_string, aws_s3_bucketname, aws_s3_image_dir):
    json_data = json.loads(json_string)
    valid_json_components = []

    for item in json_data:
        json_component = json.dumps(item)
        if item.get("command") == "insert" and item.get("category") == "issuances":
            bindings = item.get("bindings")
            if bindings:
                stamp_base64 = bindings.get("stamp_base64")
                tx_hash = bindings.get("tx_hash")
                
                if stamp_base64 and tx_hash:
                    try:
                        imgdata = base64.b64decode(stamp_base64)
                        filename = f"{tx_hash}.png"
                        s3 = boto3.client('s3')
                        
                        with io.BytesIO(imgdata) as file_obj:
                            try:
                                s3.upload_fileobj(file_obj, aws_s3_bucketname, f"{aws_s3_image_dir}/{filename}")
                                print(f"Processed filename: {filename}")
                                item["stamp_url"] = f"https://stampchain.io/stamps/{filename}"
                                valid_json_components.append(json_component)
                            except NoCredentialsError as e:
                                print(f"Unable to upload {filename} to S3. Error: {e}")
                    except Exception as e:
                        print(f"Error processing base64 image for {tx_hash}: {e}")
                else:
                    print(f"Removed invalid component: {json_component}")
            else:
                print(f"Removed invalid component: {json_component}")
        else:
            print(f"Removed invalid component: {json_component}")

    print(f"Final valid_json_components: {valid_json_components}")
    return valid_json_components


def process_messages(messages):
    output_list = []

    for message in messages:
        if message["category"] == "issuances" and message["command"] == "insert":
            bindings = message["bindings"]
            description = json.loads(bindings)["description"]

            if description.lower().find("stamp:") != -1:
                stamp_search = description[description.lower().find("stamp:") + 6:]
                stamp_base64 = stamp_search.strip() if len(stamp_search) > 1 else None
                bindings = json.loads(bindings)
                asset = bindings["asset"]

                if not any(item["bindings"]["asset"] == asset for item in output_list) and is_base64_image(stamp_base64):
                    message["bindings"] = {
                        "description": bindings["description"],
                        "tx_hash": bindings["tx_hash"],
                        "asset": bindings["asset"],
                        "asset_longname": bindings["asset_longname"],
                        "block_index": bindings["block_index"],
                        "status": bindings["status"],
                        "tx_index": bindings["tx_index"],
                        "stamp_base64": stamp_base64
                    }
                    output_list.append(message)

    return output_list


def get_block_data(block_indexes):
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
    return data["result"]


combined_list = []
for i in range(0, len(blockrange), 249):
    block_indexes = blockrange[i:i + 249]
    result = get_block_data(block_indexes)

    for block_data in result:
        messages = block_data["_messages"]
        combined_list += process_messages(messages)


# Sort the combined_list by message_index
combined_list = sorted(combined_list, key=lambda k: k['message_index'])

# Deduplicate the list by "asset" key
unique_assets = {}
unique_list = []

for message in combined_list:
    asset = message["bindings"]["asset"]  # Access the "asset" key from the "bindings" object
    if asset not in unique_assets:
        unique_assets[asset] = True
        unique_list.append(message)

# Assign new "stamp" key-value pair to the dictionary
for i, message in enumerate(unique_list):
    message["stamp"] = i

json_string = json.dumps(unique_list, indent=4)
final_array_with_url = (parse_json_array_convert_base64_to_file_and_upload(json_string, aws_s3_bucketname, aws_s3_image_dir))
print(final_array_with_url)



with open(json_output, 'w') as f:
    f.write(final_array_with_url)

if aws_secret_access_key != "" and aws_access_key_id != "":
# pending check for existing file list, we will not upload if it exists
    s3_objects = get_s3_objects(aws_s3_bucketname, s3_client)
    # s3_key should be == to stamps/txid.png
    #print(s3_objects)
    #if s3_key not in s3_objects:
    #    print(f'Uploading {local_file_path} to {s3_key}')
    #    upload_file_to_s3(local_file_path, bucket_name, s3_key, s3_client)

# upload json_output file to root dir of s3 bucket
if aws_s3_bucketname != "" and aws_cloudfront_distribution_id != "":
    upload_file_to_s3(json_output,aws_s3_bucketname,json_output,s3_client)
    # can purge local file upon successful upload
    # os.remove(json_output)
    invalidate_s3_file("/" + json_output, aws_cloudfront_distribution_id)
    #invalidate_s3_file("/" + json_output)
