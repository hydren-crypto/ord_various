#!/bin/bash

aws s3 cp inscribe_log.json s3://hydren.io/inscribed/
set -x
echo "$CLOUDFRONT_ID"
aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths /inscribed/inscribe_log.json
