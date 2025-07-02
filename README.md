[![SwiftFormat](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftformat.yml/badge.svg)](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftformat.yml) [![SwiftLint](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/hbmartin/justaline-ios-resurrected/actions/workflows/swiftlint.yml) ![Swift](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift)[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/hbmartin/justaline-ios)

# Just a Line - iOS
<img src="media/demo1.gif" />

<img src="media/demo2.gif" />

## Overview

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

## Architecture

<img src="media/arch.svg" />

### Manager Pattern

The application extensively uses the Manager pattern to separate concerns and coordinate complex operations. Each manager has a specific responsibility:

*   **`PairingManager`**: Orchestrates multi-device collaboration ([PairingManager.swift36](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/PairingManager.swift#L36-L36))
*   **`RoomManager`**: Handles Firebase operations and room lifecycle ([RoomManager.swift41](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/RoomManager.swift#L41-L41))
*   **`StateManager`**: Coordinates UI state transitions (referenced throughout)
*   **`StrokeUploadManager`**: Manages batched stroke uploads ([RoomManager.swift58](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/RoomManager.swift#L58-L58))

### Delegate Pattern

Communication between managers uses the delegate pattern to maintain loose coupling while enabling coordinated behavior:

*   **`PairingManagerDelegate`**: Notifies AR controller of collaboration events ([PairingManager.swift22-33](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/PairingManager.swift#L22-L33))
*   **`RoomManagerDelegate`**: Handles Firebase room events ([RoomManager.swift22-36](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/RoomManager.swift#L22-L36))
*   **`InterfaceViewControllerDelegate`**: Forwards UI interactions to main controller

### Observer Pattern

Firebase integration uses the observer pattern for real-time synchronization:

*   **Stroke Updates**: `observe(.childAdded)`, `observe(.childChanged)` ([RoomManager.swift841-866](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/RoomManager.swift#L841-L866))
*   **Participant Changes**: `observe(.childAdded)`, `observe(.childRemoved)` ([RoomManager.swift476-536](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/RoomManager.swift#L476-L536))
*   **Anchor Resolution**: `observe(.value)` for anchor state changes ([RoomManager.swift563-628](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/RoomManager.swift#L563-L628))

### State Machine Pattern

The UI state management implements a state machine that coordinates complex pairing flows with appropriate user feedback and error handling across network operations and AR anchor resolution.

Sources: [PairingManager.swift1-804](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/PairingManager.swift#L1-L804) [RoomManager.swift1-881](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/RoomManager.swift#L1-L881) [ViewControllers/ViewController.swift1-397](https://github.com/hbmartin/justaline-ios-resurrected/blob/0f2b383e/ViewControllers/ViewController.swift#L1-L397)
