#!/bin/bash

# create a html file with a gallery listing of all images

echo "<html>
<head>
    <title>Inscription Gallery</title>
</head>
<body>
    <h1>Inscription Gallery</h1>
    <div>
        $(for explorer in $(jq -r '.[] | .explorer' $inscribe_log); do
            content_url=$(echo "$explorer" | sed "s@\(https://ordinals.com/inscriptions/\)\(.*\)\(i0\)@\1\2\3/content@g")
            echo "<a href=\"$explorer_url\"><img src=\"$url\"/>"
        done)
    </div>
</body>
</html>" > gallery.html
