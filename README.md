[![SwiftFormat](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftformat.yml/badge.svg)](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftformat.yml) [![SwiftLint](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftlint.yml) 

# Just a Line - iOS
Just a Line is an [AR Experiment](https://experiments.withgoogle.com/ar) that lets you draw simple white lines in 3D space, on your own or together with a friend, and share your creation with a video. Draw by pressing your finger on the screen and moving the phone around the space.

This app was written in Swift using ARKit and ARCore. ARCore Cloud Anchors to enable Just a Line to pair two phones, allowing users to draw simultaneously in a shared space. Pairing works across Android and iOS devices, and drawings are synchronized live on Firebase Realtime Database.

This is not an official Google product, but an [AR Experiment](https://experiments.withgoogle.com/ar) that was developed at the Google Creative Lab in collaboration with [Uncorked Studios](https://www.uncorkedstudios.com/).

Just a Line is also developed for Android. The open source code for Android can be found [here](https://github.com/googlecreativelab/justaline-android).

## Get started
To build the project, first install all dependencies using [CocoaPods](https://guides.cocoapods.org/using/getting-started.html) by running

```
pod install
```

Then the project can be built using Xcode 16.

## Firebase Setup
You will need to set up a cloud project with Firebase, ARCore, and with nearby messages enabled before running the app. Follow the setup steps in the [ARCore Cloud Anchors Quickstart guide](https://developers.google.com/ar/develop/ios/cloud-anchors-quickstart-ios).

**Important Firebase Configuration Requirements:**
- **Anonymous Authentication** must be enabled in Firebase Authentication
- **Realtime Database** must be enabled and configured
- Ensure your `GoogleService-Info.plist` file is properly added to the project

The app uses Firebase Anonymous Authentication for user identification and Firebase Realtime Database for storing and synchronizing drawing data between devices.
