#!/bin/zsh
# Renders every out/<size>/*.svg to PNG with headless Chrome (transparent background for layers).
set -e
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cd "$(dirname "$0")"
for d in out/*/; do
  for f in $d*.svg; do
    read W H < <(python3 -c "import re,sys;s=open('$f').read(300);m=re.search(r'width=\"(\d+)\" height=\"(\d+)\"',s);print(m[1],m[2])")
    abs="$PWD/$f"; png="${abs%.svg}.png"
    printf '<html><body style="margin:0;background:transparent"><img src="file://%s" width="%s" height="%s"></body></html>' "$abs" $W $H > /tmp/promo-wrap.html
    "$CH" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
      --screenshot="$png" --window-size=$W,$H "file:///tmp/promo-wrap.html" >/dev/null 2>&1
    echo "$png"
  done
done
