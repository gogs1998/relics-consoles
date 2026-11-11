#!/bin/zsh
# Simulator build under the shared-Mac lock, DerivedData inside build/. Usage: Tools/build.sh [extra xcodebuild args]
cd "$(dirname "$0")/.."
FREE=$(df -g ~ | awk 'NR==2 {print $4}')
if [ "$FREE" -lt 4 ]; then echo "error: less than 4 GB free ($FREE GB); not building"; exit 1; fi
L=/private/tmp/duo-build.lock; while [ -e $L ] && kill -0 $(cat $L) 2>/dev/null; do sleep 20; done; echo $$ > $L; trap 'rm -f $L' EXIT
xcodebuild -project DuoEmulator.xcodeproj -scheme DuoEmulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData build "$@"
