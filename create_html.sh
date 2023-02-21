#!/bin/bash

# create a html file with a gallery listing of all images
inscribe_log=inscribe_log.json
html_output=gallery.html
inscription_url_prefix=https://ordinals.com/inscription/
content_url_prefix=https://ordinals.com/preview/

echo "<html>
<head>
    <title>Inscription Gallery</title>
</head>
<body>
    <h1>Inscription Gallery</h1>
    <div>
        $(for inscription in $(jq -r '.[] | .inscription' $inscribe_log); do
            explorer_url=${inscription_url_prefix}${inscription}
            content_url=${content_url_prefix}${inscription}
	        alt_text=$(jq --arg description "$description" --arg inscription "$inscription" '.[] | select(.inscription == $inscription) | .description' $inscribe_log)
            echo "<a href=\"$explorer_url\"><img src=\"$content_url\" alt=\"$alt_text\"/>"
        done)
    </div>
</body>
</html>" > $html_output

aws s3 cp $html_output s3://hydren.io/inscribed/$html_output
aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths /inscribed/$html_output
