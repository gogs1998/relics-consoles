#!/bin/zsh
# Runs the UI tests on simulator $1 (UDID) under the shared build lock.
cd "$(dirname "$0")/.."
L=/private/tmp/duo-build.lock; while [ -e $L ] && kill -0 $(cat $L) 2>/dev/null; do sleep 20; done; echo $$ > $L; trap 'rm -f $L' EXIT
xcodebuild -project DuoEmulator.xcodeproj -scheme DuoEmulator -destination "id=$1" -derivedDataPath build/DerivedData test
