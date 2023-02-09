#!/bin/bash

ord wallet inscriptions > inscriptions.json
aws s3 cp inscriptions.json s3://hydren.io && rm inscriptions.json

