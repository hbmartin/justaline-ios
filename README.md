A work in progress for 2025 - see the [modernization plan](https://github.com/hbmartin/justaline-ios/blob/master/MODERNIZATION_PLAN.md)

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
You will need to set up a cloud project with Firebase, ARCore, and with nearby messages enabled before running the app. Follow the setup steps in the [ARCore Cloud Anchors Quickstart guide](https://developers.google.com/ar/develop/ios/cloud-anchors-quickstart-ios).
