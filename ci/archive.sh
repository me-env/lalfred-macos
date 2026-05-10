#!/bin/sh

xcodebuild -exportArchive \
  -archivePath build/LAlfred.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist


