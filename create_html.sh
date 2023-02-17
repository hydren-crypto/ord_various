#!/bin/bash

# create a html file with a gallery listing of all images
inscribe_log=inscribe_log.json
html_output=gallery.html

echo "<html>
<head>
    <title>Inscription Gallery</title>
</head>
<body>
    <h1>Inscription Gallery</h1>
    <div>
        $(for explorer_url in $(jq -r '.[] | .explorer' $inscribe_log); do
            content_url=$(echo "$explorer_url" | sed -E 's/\/inscription\//\/content\//g')
            echo "<a href=\"$explorer_url\"><img src=\"$content_url\"/>"
        done)
    </div>
</body>
</html>" > $html_output

aws s3 cp $html_output s3://hydren.io/inscribed/$html_output
aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths /inscribed/$html_output
