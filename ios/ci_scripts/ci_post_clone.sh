#!/bin/sh
# Xcode Cloud runs this right after cloning the repo. Novabolt is a Flutter
# app, so before Xcode can archive it we need Flutter (to fetch packages and
# write ios/Flutter/Generated.xcconfig) and CocoaPods (to create the Pods
# support files). Keep FLUTTER_VERSION in step with the version you build
# releases with locally (`flutter --version`).
set -e

FLUTTER_VERSION=3.41.9
export LANG=en_US.UTF-8

cd "$CI_PRIMARY_REPOSITORY_PATH"

git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

flutter config --no-analytics
flutter precache --ios
flutter pub get

HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
cd ios && pod install

exit 0
