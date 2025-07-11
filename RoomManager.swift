// swiftlint:disable file_length
// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Firebase
import FirebaseAnalytics
import FirebaseAuth
import FirebaseDatabase
import Foundation

protocol RoomManagerDelegate: AnyObject {
    func localStrokeRemoved(_ stroke: Stroke)
    func updatePartnerAnchorReadiness(partnerReady: Bool, isHost: Bool)
    // swiftlint:disable:next discouraged_optional_boolean
    func partnerJoined(isHost: Bool, isPairing: Bool?)
    func pairingFailed()
    func partnerLost()
    func partnerStrokeUpdated(_ stroke: Stroke, id key: String)
    func partnerStrokeRemoved(id key: String)
    func anchorIdCreated(_ id: String)
    func anchorNotAvailable()
    func anchorResolved()
    func roomCreated(_ roomData: RoomData)
    func leaveRoom()
}

let kGLOBAL_ROOM_ROOT = "global_rooms"

// swiftlint:disable:next type_body_length
class RoomManager: StrokeUploaderDelegate {
    // MARK: Properties

    // MARK: Variables

    /// Auth
    var firebaseAuth: Auth?

    /// User ID
    var userUid: String?

    /// Store anchor id after it is added to prevent repeatedely resolving
    var anchorId: String?

    /// Delegate property for PairingManager
    weak var delegate: RoomManagerDelegate?

    var strokeUploader: StrokeUploadManager

    var hasStrokeData: Bool = false

    var isHost: Bool = false

    var ROOT_GLOBAL_ROOM = kGLOBAL_ROOM_ROOT + "/global_room_0"

    var isRoomResolved: Bool = false

    var isRetrying = false

    private let ROOT_FIREBASE_ROOMS = "rooms"

    private let DISPLAY_NAME_VALUE = "Just a Line"

    private var app: FirebaseApp?

    private var roomRef: DatabaseReference?

    private var roomKey: String?

    private var roomsListRef: DatabaseReference?
    private var participantsRef: DatabaseReference?
    private var strokesRef: DatabaseReference?

    private var globalRoomRef: DatabaseReference?

    private var anchorValueHandle: UInt?

    private var anchorRemovedHandle: UInt?

    private var partners = [String]()

    private var partnerAddedHandle: UInt?

    private var partnerUpdatedHandle: UInt?

    private var partnerRemovedHandle: UInt?

    private var partnerMovedHandle: UInt?

    private var strokeAddedHandle: UInt?

    private var strokeUpdatedHandle: UInt?

    private var strokeRemovedHandle: UInt?

    private var strokeMovedHandle: UInt?

    private var localStrokeUids = [String: Stroke]()

    /// Flag to indicate that we are using the global room, but pairing and resolving an anchor
    private var pairing: Bool = false

    // MARK: Computed Properties

    /// Current room data for sharing via Nearby Connections
    var currentRoomData: RoomData? {
        guard let roomKey else {
            return nil
        }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        return RoomData(code: roomKey, timestamp: timestamp)
    }

    // MARK: Lifecycle

    init() {
        strokeUploader = StrokeUploadManager()
        strokeUploader.delegate = self

        // Firebase setup
        firebaseAuth = Auth.auth()
        firebaseLogin()

        app = FirebaseApp.app()
        if app != nil {
            let rootRef = Database.database().reference()
            roomsListRef = rootRef.child(ROOT_FIREBASE_ROOMS)
            globalRoomRef = rootRef.child(ROOT_GLOBAL_ROOM)

            DatabaseReference.goOnline()
        } else {
            roomsListRef = nil
            globalRoomRef = nil
            fatalError("RoomManager: Could not connect to Firebase Database!")
        }
    }

    // MARK: Functions

    func updateGlobalRoomName(_ name: String) {
        print("updateGlobalRoomName: \(name)")
        let rootRef = Database.database().reference()
        ROOT_GLOBAL_ROOM = name
        globalRoomRef = rootRef.child(ROOT_GLOBAL_ROOM)
    }

    // MARK: - Firebase Status

    /// Check if Firebase is ready for operations
    func isFirebaseReady() -> Bool {
        print("userUid: \(String(describing: userUid)), roomsListRef: \(String(describing: roomsListRef))")
        return app != nil && userUid != nil && roomsListRef != nil
    }

    /// Wait for Firebase to be ready with completion handler
    func waitForFirebaseReady(completion: @escaping () -> Void) {
        if isFirebaseReady() {
            completion()
        } else {
            // Use a different approach to avoid capture issues
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("FirebaseAuthCompleted"), // swiftlint:disable:this legacy_objc_type
                object: nil,
                queue: .main
            ) { [weak self] _ in
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                if self?.isFirebaseReady() == true {
                    completion()
                } else {
                    // If still not ready, retry after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.waitForFirebaseReady(completion: completion)
                    }
                }
            }

            // Also set up a timeout fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                print("Firebase authentication timeout - proceeding anyway")
                completion()
            }
        }
    }

    // MARK: - Room Flow

    /// When pairing both users create a room
    func createRoom() {
        print("RoomManager:createRoom")

        // Check if Firebase is ready
        guard isFirebaseReady() else {
            print("RoomManager:createRoom: Firebase not ready, waiting for auth...")
            waitForFirebaseReady {
                self.createRoom()
            }
            return
        }

        if let room = roomsListRef?.childByAutoId() {
            updateRoomReference(room)
        }

        print("RoomManager:createRoom: Trying Room Number: \(String(describing: (roomRef?.key)))")

        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        self.roomRef?.child(FBKey.val(.updatedAtTimestamp)).setValue(timestamp)
        self.roomRef?.child(FBKey.val(.displayName)).setValue(self.DISPLAY_NAME_VALUE)

        pairing = true
        participateInRoom()

        if let roomString = roomKey {
            let roomData = RoomData(code: roomString, timestamp: timestamp)
            self.delegate?.roomCreated(roomData)
        } else {
            print("RoomManager:createRoom: Failed to create room - no room key")
            StateManager.updateState(.UNKNOWN_ERROR)
        }
    }

    /// Takes database ref for either new or joined room and updates the key and participants ref
    ///
    /// - Parameter room: Database Reference for firebase room
    func updateRoomReference(_ room: DatabaseReference) {
        roomRef = room
        roomKey = room.key
    }

    /// Add self as a participant in the current room
    func participateInRoom() {
        guard let uid = self.userUid, let partnersRef = roomRef?.child(FBKey.val(.participants)) else {
            print("RoomManager:participateInRoom: Missing uid or room reference")
            StateManager.updateState(.UNKNOWN_ERROR)
            return
        }

        participantsRef = partnersRef

        // Add to participants list with false value until room is resolved for the originating user to discover
        let participant = FBParticipant(readyToSetAnchor: false)
        participant.isPairing = pairing

        partnersRef.child(uid).setValue(participant.dictionaryValue()) { error, _ in
            if let error {
                print("RoomManager:participateInRoom: Error setting participant value: \(error.localizedDescription)")
                StateManager.updateState(.UNKNOWN_ERROR)
            } else {
                print("RoomManager:participateInRoom: Successfully joined room as participant")
            }
        }
        partnersRef.child(uid).onDisconnectSetValue(nil)
        self.partnerJoinedCallbacks(uid: uid, reference: partnersRef)
    }

    /// RoomData conveyed via Nearby
    func roomFound(_ roomData: RoomData) {
        if shouldJoinRoom(roomData) {
            self.delegate?.leaveRoom()

            joinRoom(roomKey: roomData.code)
        }
    }

    func findGlobalRoom(_ withPairing: Bool = false) {
        guard let globalRoom = globalRoomRef else {
            print("RoomManager:findGlobalRoom: No global room reference")
            StateManager.updateState(.UNKNOWN_ERROR)
            return
        }
        guard isFirebaseReady() else {
            print("RoomManager:findGlobalRoom: Firebase not ready, waiting for auth...")
            waitForFirebaseReady {
                self.findGlobalRoom(withPairing)
            }
            return
        }

        pairing = withPairing

        print("globalRoom reference URL: \(globalRoom.url)")
        globalRoom.observeSingleEvent(of: .value) { snapshot in
            print("Reference path: \(snapshot.ref.url)")
            if !snapshot.exists() {
                let parts = globalRoom.url.split(separator: "/")
                globalRoom.setValue(parts.last) { error, _ in
                    if let error {
                        print("Failed to setup global room: \(error.localizedDescription)")
                    } else {
                        print("Did setup global room: \(parts.last)")
                        // swiftlint:disable:next force_unwrapping
                        self.joinRoom(roomKey: String(parts.last!))
                    }
                }
            } else {
                if let optionalValue = snapshot.value, let roomString = optionalValue as? String {
                    print("RoomManager:findGlobalRoom: Found global room: \(roomString)")
                    self.joinRoom(roomKey: roomString)
                } else {
                    print("RoomManager:findGlobalRoom: No global room found")
                    StateManager.updateState(.GLOBAL_NO_ANCHOR)
                }
            }
        } withCancel: { error in
            print("RoomManager:findGlobalRoom: Error finding global room: \(error.localizedDescription)")
            StateManager.updateState(.GLOBAL_RESOLVE_ERROR)
        }
    }

    /// Adds user id to participants list, and begins watching for an anchor
    func joinRoom(roomKey: String) {
        print("RoomManager:joinRoom: Joining Room: \(roomKey)")
        guard isFirebaseReady() else {
            print("RoomManager:joinRoom: Firebase not ready, waiting for auth...")
            waitForFirebaseReady {
                self.joinRoom(roomKey: roomKey)
            }
            return
        }

        if let room = roomsListRef?.child(roomKey) {
            updateRoomReference(room)
            participateInRoom()
//            for stroke in localStrokeUids {
//                let strokeRef = room.child(FBKey.val(.lines)).childByAutoId()
//                stroke.value.fbReference = strokeRef
//                uploadStroke(stroke.value) {error, reference in
//                    if error == nil {
//                        print("Uploaded strok: \(String(describing: reference))")
//                    } else {
//                        print("Error uploading stroke: \(String(describing: error))")
//                    }
//                }
//            }
            #if JOIN_GLOBAL_ROOM
                // if pairing with another device, remove anchor to start fresh
                // otherwise try to obtain an existing anchor id
                if pairing == false {
                    self.observeAnchor()
                }
            #endif
        } else {
            print("Unable to find room: \(roomKey)")
        }
    }

    func resumeRoom() {
        if roomRef == nil {
            return
        }

        participateInRoom()
    }

    /// Sets Firebase flags for participant and anchor, begins observing stroke ref for child changes
    func resolveRoom() {
        print("RoomManager: resolveRoom: roomRef: \(String(describing: roomRef)), uid: \(String(describing: userUid))")
        guard let room = roomRef, let uid = userUid else {
            return
        }

        self.isRoomResolved = true

        let participant = FBParticipant(anchorResolved: true, isPairing: false)
        participantsRef?.child(uid).setValue(participant.dictionaryValue())
        room.child(FBKey.val(.anchor)).child(FBKey.val(.anchorResolutionError)).setValue(false)
    }

    func stopObservingLines() {
        print("Stopped observing lines")
        if let handle = strokeAddedHandle {
            strokesRef?.removeObserver(withHandle: handle)
        }

        if let handle = strokeUpdatedHandle {
            print("stroke update handle removed for \(String(describing: strokesRef))")
            strokesRef?.removeObserver(withHandle: handle)
        }

        if let handle = strokeRemovedHandle {
            strokesRef?.removeObserver(withHandle: handle)
        }

        if let handle = strokeMovedHandle {
            strokesRef?.removeObserver(withHandle: handle)
        }
        strokesRef?.removeAllObservers()
    }

    func leaveRoom() {
        isRoomResolved = false
        isHost = false

        partners.removeAll()
        localStrokeUids.removeAll()

        if let handle = partnerAddedHandle {
            participantsRef?.removeObserver(withHandle: handle)
        }

        if let handle = partnerUpdatedHandle {
            participantsRef?.removeObserver(withHandle: handle)
        }

        if let handle = partnerRemovedHandle {
            participantsRef?.removeObserver(withHandle: handle)
        }

        if let handle = partnerMovedHandle {
            participantsRef?.removeObserver(withHandle: handle)
        }

        stopObservingLines()
        participantsRef?.removeAllObservers()
        anchorId = nil
        anchorValueHandle = nil
        anchorRemovedHandle = nil
        partnerAddedHandle = nil
        partnerUpdatedHandle = nil
        partnerRemovedHandle = nil
        partnerMovedHandle = nil
        strokeAddedHandle = nil
        strokeUpdatedHandle = nil
        strokeRemovedHandle = nil
        strokeMovedHandle = nil
        strokesRef = nil

        guard let room = roomRef, let uid = userUid else {
            return
        }

        // remove user from participants list
        participantsRef?.child(uid).removeValue()
        participantsRef = nil

        if let handle = anchorValueHandle {
            room.removeObserver(withHandle: handle)
        }

        if let handle = anchorRemovedHandle {
            room.removeObserver(withHandle: handle)
        }
        room.removeAllObservers()

        roomRef = nil
        roomKey = nil
    }

    // MARK: Partner Callbacks

    /// Observers for "participants" DatabaseReference. When participant is initially added, their id is the key,
    /// and the value indicates whether the anchor has been resolved
    ///
    /// - Parameters:
    ///   - uid: userUid value
    ///   - reference: path to participants in FB
    func partnerJoinedCallbacks(uid: String, reference: DatabaseReference) { // swiftlint:disable:this function_body_length
        // Partner Added
        self.partnerAddedHandle = reference.observe(.childAdded) { snapshot in
            print("RoomManager:partnerJoinedCallbacks: Partner Added Observer: \(String(describing: snapshot))")

            if snapshot.key != uid {
                if let participantDict = snapshot.value as? [String: Any?] {
                    self.partners.append(snapshot.key)
                    let participant = FBParticipant.from(participantDict)
                    print("self.pairing: \(self.pairing) , participant: \(String(describing: participant))")
                    if participant?.isPairing == true, self.pairing == true {
                        // Host for global room pairing is alphabetical since we don't establish with Nearby pub/sub
                        let keyComparison = uid.compare(snapshot.key)
                        self.isHost = (keyComparison == ComparisonResult.orderedDescending) ? false : true

                        #if JOIN_GLOBAL_ROOM
                            let state: State = (self.isHost) ? .HOST_CONNECTED : .PARTNER_CONNECTED
                            StateManager.updateState(state)
                            print("RoomManager:partnerJoinedCallbacks: updated state to: \(state)")
                        #endif
                    }
                    self.delegate?.partnerJoined(isHost: self.isHost, isPairing: participant?.isPairing)
                }
            }
        } withCancel: { _ in
            print("RoomManager:Partner Added Observer Cancelled")
        }

        // Partner Changed
        self.partnerUpdatedHandle = reference.observe(.childChanged) { snapshot in
            print("RoomManager:partnerJoinedCallbacks: Partner Changed Observer")
            if let participantDict = snapshot.value as? [String: Any?], let participant = FBParticipant.from(participantDict),
               snapshot.key != uid {
                self.delegate?.updatePartnerAnchorReadiness(partnerReady: participant.readyToSetAnchor, isHost: self.isHost)

                // if host is true, we are pairing (when partner finishes resolving room, they set isPairing to false) and can resolve room
                // if partner, host still hasn't resolved room, so isPairing is still true
                if participant.anchorResolved == true, self.isHost == true { // || participant.isPairing == true)) {
                    self.delegate?.anchorResolved()
                }
            }
        } withCancel: { _ in
            print("RoomManager:Partner Changed Observer Cancelled")
        }

        // Partner Removed
        self.partnerRemovedHandle = reference.observe(.childRemoved) { snapshot in
            print("RoomManager:partnerJoinedCallbacks: Partner Removed Observer")
            if let partnerIndex = self.partners.index(of: snapshot.key) {
                self.partners.remove(at: partnerIndex)
                if self.partners.count < 1 {
                    self.delegate?.partnerLost()
                }
            }
            if let participantDict = snapshot.value as? [String: Any?], snapshot.key != uid {
                let participant = FBParticipant.from(participantDict)
                if participant?.isPairing == true {
                    StateManager.updateState(.CONNECTION_LOST)
                }
            }
        } withCancel: { _ in
            print("Partner Removed Observer Cancelled")
        }
    }

    // MARK: - Anchor Flow

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func observeAnchor() {
        print("observeAnchor: \(String(describing: roomRef))")
        guard let room = roomRef else {
            return
        }

        let anchorUpdateRef = room.child(FBKey.val(.anchor))
        print(String(describing: anchorUpdateRef))

        // Clear anchor before adding creation listener, except in global room when not pairing
        #if !JOIN_GLOBAL_ROOM
            print("NOT JOINING GLOBAL ROOM")
            anchorUpdateRef.removeValue()
        #else
            print("Joining Global Room, pairing: \(pairing)")
            if pairing == true {
                anchorUpdateRef.removeValue()
            }
        #endif
        print("Observing Anchor Value Reference: \(anchorUpdateRef)")
        // swiftlint:disable:next closure_body_length
        anchorValueHandle = anchorUpdateRef.observe(.value) { dataSnapshot in
            print("Anchor Value Data: \(dataSnapshot)")

            if let anchorValue = dataSnapshot.value as? [String: Any?] {
                print("RoomManager:observeAnchor: FBAnchor object found")

                // Create anchor object from Firebase model
                if let anchor = FBAnchor.from(anchorValue) {
                    // Return anchor
                    if anchor.anchorResolutionError == true {
                        // When Joining a global room, if there is a pre-exisintg anchor error, need to show special error
                        var shouldUseGlobalError = false
                        #if JOIN_GLOBAL_ROOM
                            if self.pairing == false {
                                shouldUseGlobalError = true
                            }
                        #endif

                        // Even in global pairing (not global joining), we want to set state to host or partner errors
                        if self.isHost || !shouldUseGlobalError {
                            StateManager.updateState(.HOST_RESOLVE_ERROR)
                        } else if !shouldUseGlobalError {
                            StateManager.updateState(.PARTNER_RESOLVE_ERROR)
                        } else {
                            StateManager.updateState(.GLOBAL_NO_ANCHOR)
                        }
                        self.delegate?.pairingFailed()

                        // If there's an anchor error, reset readyToSetAnchor value
                        if let uid = self.userUid {
                            self.participantsRef?.child(uid).child(FBKey.val(.readyToSetAnchor)).setValue(false)
                        }
                    } else if let anchorId = anchor.anchorId, self.isHost == false, self.anchorId != anchorId {
                        print("RoomManager:observeAnchor: Anchor ID found: \(String(describing: anchor.anchorId))")
                        self.anchorId = anchorId

                        var state: State = .PARTNER_CONNECTING
                        #if JOIN_GLOBAL_ROOM
                            if self.pairing == false {
                                state = .GLOBAL_CONNECTING
                            }
                        #endif

                        StateManager.updateState(state)
                        self.delegate?.anchorIdCreated(anchorId)
                    }

                    // Stop watching for anchor changes
//                    anchorUpdateRef.removeAllObservers()
                }
            } else {
                print("Failed to observe anchor")
                #if JOIN_GLOBAL_ROOM
                    if self.pairing == false {
//                    print("No anchor exists in global room, becoming host")
//                    self.isHost = true
//                    // Trigger anchor creation directly since there's no partner to wait for
//                    StateManager.updateState(.HOST_READY_AND_WAITING)
//                } else {
                        StateManager.updateState(.GLOBAL_NO_ANCHOR)
                    }
                #endif
            }
        } withCancel: { _ in
            print("RoomManager:observeAnchor: Anchor Observe Cancelled")
        }

        anchorRemovedHandle = room.observe(.childRemoved, with: { snapshot in
            if snapshot.key == FBKey.val(.anchor) {
                print("RoomManager:observeAnchor: Anchor object removed")
                self.delegate?.anchorNotAvailable()
            }
        })
    }

    func setReadyToSetAnchor() {
        print("RoomManager: setReadyToSetAnchor")
        guard let partnersRef = participantsRef, let uid = userUid else {
            return
        }

        self.observeAnchor()

        let participant = FBParticipant(readyToSetAnchor: true)
        partnersRef.child(uid).setValue(participant.dictionaryValue())
    }

    /// After resolving cloud anchor, set cloud identifier in Firebase for partner to discover
    func setAnchorId(_ identifier: String) {
        print("setAnchorId: \(identifier)")
        guard let room = roomRef else {
            return
        }

        self.anchorId = identifier
        let fbAnchor = FBAnchor(anchorId: identifier)
        room.child(FBKey.val(.anchor)).setValue(fbAnchor.dictionaryValue())
    }

    func retryResolvingAnchor() {
        isRoomResolved = false

        if let anchor = self.anchorId {
            isRetrying = true
            localStrokeUids.removeAll()
            delegate?.anchorIdCreated(anchor)
        } else {
            delegate?.pairingFailed()
        }
    }

    func anchorResolved() {
        if isRoomResolved == false {
            self.resolveRoom()
            self.observeLines()
            isHost = false
        }
    }

    func anchorFailedToResolve() {
        print("RoomManager: anchorFailedToResolve: \(String(describing: self.roomRef))")

        guard let room = roomRef else {
            return
        }

        print("RoomManager: anchorFailedToResolve: isRetrying: \(isRetrying), pairing: \(pairing)")

        if !isRetrying {
            // For global rooms, only send failure to Firebase if it is a hosting failure
            #if JOIN_GLOBAL_ROOM
                if pairing {
                    let fbAnchor = FBAnchor(anchorResolutionError: true)
                    room.child(FBKey.val(.anchor)).setValue(fbAnchor.dictionaryValue())
                }
            #else
                let fbAnchor = FBAnchor(anchorResolutionError: true)
                room.child(FBKey.val(.anchor)).setValue(fbAnchor.dictionaryValue())
            #endif
        }
    }

    // MARK: - Strokes

    /// Watch for changes to lines db ref
    func observeLines() {
        guard let room = roomRef, let uid = userUid else {
            return
        }

        strokesRef = room.child(FBKey.val(.lines))
        // swiftlint:disable:next force_unwrapping
        self.strokeUpdateCallbacks(uid: uid, reference: strokesRef!)
    }

    /// Gateway for all stroke changes besides clear all
    /// Updates locally drawn strokes or adds them if they do not already exist
    func updateStroke(_ stroke: Stroke, shouldRemove: Bool = false) {
        let localStrokeMatch = localStrokeUids.contains { _, localStroke -> Bool in
            localStroke == stroke
        }

        if localStrokeMatch == false {
            addStroke(stroke)
        }
        strokeUploader.queueStroke(stroke, remove: shouldRemove)
    }

    func clearAllStrokes() {
        guard let room = roomRef else {
            return
        }

        room.child(FBKey.val(.lines)).removeValue()
    }

    // MARK: StrokeUploadManager Delegate methods

    func uploadStroke(_ stroke: Stroke, completion: @escaping ((Error?, DatabaseReference) -> Void)) {
        print("RoomManager: uploadStroke")
        guard let fbStrokeRef = stroke.fbReference else {
            return
        }

        if stroke.previousPoints == nil {
            let dictValue = stroke.dictionaryValue()
            print("New Stroke dict: \(dictValue)")
            if dictValue.isEmpty || stroke.node == nil {
                print("RoomManager: uploadStroke: Stroke new upload cancelled, stroke removed")
                delegate?.localStrokeRemoved(stroke)
            } else {
                fbStrokeRef.setValue(dictValue, withCompletionBlock: completion)
            }
        } else {
            let dictValue = stroke.pointsUpdateDictionaryValue()
            print("Stroke update dict: \(dictValue)")
            if dictValue.isEmpty || stroke.node == nil {
                print("RoomManager: uploadStroke: Stroke update upload cancelled, stroke removed")
                delegate?.localStrokeRemoved(stroke)
            } else {
                fbStrokeRef.child(FBKey.val(.points)).updateChildValues(dictValue, withCompletionBlock: completion)
            }
        }
    }

    func removeStroke(_ stroke: Stroke) {
        delegate?.localStrokeRemoved(stroke)
        stroke.fbReference?.removeValue()
    }

    /// Login with existing id or create a new one
    private func firebaseLogin() {
        if let currentUser = firebaseAuth?.currentUser {
            userUid = currentUser.uid
            print("firebaseLogin: user uid \(String(describing: userUid))")
            // Notify that authentication is complete
            // swiftlint:disable:next legacy_objc_type
            NotificationCenter.default.post(name: NSNotification.Name("FirebaseAuthCompleted"), object: nil)
        } else {
            loginAnonymously()
        }
    }

    /// Create new user id with anonymous sign-in
    private func loginAnonymously() {
        firebaseAuth?.signInAnonymously(completion: { _, error in
            // need to handle error states
            if error == nil {
                if let currentUser = self.firebaseAuth?.currentUser {
                    self.userUid = currentUser.uid
                    print("loginAnonymously: user uid \(String(describing: self.userUid))")

                    // Notify that authentication is complete
                    // swiftlint:disable:next legacy_objc_type
                    NotificationCenter.default.post(name: NSNotification.Name("FirebaseAuthCompleted"), object: nil)
                }
            } else {
                print("Firebase anonymous login failed: \(error?.localizedDescription ?? "Unknown error")")
                // Retry authentication after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    print("Retrying Firebase authentication with loginAnonymously...")
                    self.loginAnonymously()
                }
                // Notify that authentication failed
                // swiftlint:disable:next legacy_objc_type
                NotificationCenter.default.post(name: NSNotification.Name("FirebaseAuthFailed"), object: error)
            }
        })
    }

    /// If no room has been created, join, otherwise only choose if my room number is lower
    private func shouldJoinRoom(_ roomData: RoomData) -> Bool {
        guard let roomString = self.roomKey else {
            return true
        }

        return roomString.compare(roomData.code) == ComparisonResult.orderedDescending
    }

    private func addStroke(_ stroke: Stroke) {
        print("RoomManager: addStroke \(String(describing: roomRef)) , \(String(describing: userUid))")
        guard let room = roomRef, let uid = userUid else {
            return
        }

        let strokeRef = room.child(FBKey.val(.lines)).childByAutoId()
        // swiftlint:disable:next force_unwrapping
        localStrokeUids[strokeRef.key!] = stroke
        stroke.creatorUid = uid
        stroke.fbReference = strokeRef
    }

    // MARK: Stroke Callbacks

    /// Observers for changes to partner's lines
    private func strokeUpdateCallbacks(uid _: String, reference: DatabaseReference) {
        print("Stroke Update Callbacks Reference: \(reference)")

        self.strokeAddedHandle = reference.observe(.childAdded) { snapshot in
            if let strokeValue = snapshot.value as? [String: Any?],
               self.localStrokeUids[snapshot.key] == nil,
               let stroke = Stroke.from(strokeValue) {
                print("RoomManager:strokeUpdateCallbacks: Partner Stroke Added Observer")
                stroke.drawnLocally = false
                self.delegate?.partnerStrokeUpdated(stroke, id: snapshot.key)
            } else if (snapshot.value as? [String: Any?]) != nil, self.localStrokeUids[snapshot.key] != nil {
                self.hasStrokeData = true
            } else {
                print("RoomManager:strokeUpdateCallbacks: Added Observer has wrong value: \(String(describing: snapshot.value))")
            }
        } withCancel: { _ in
            print("Partner Stroke Added Observer Cancelled")
        }

        self.strokeUpdatedHandle = reference.observe(.childChanged) { snapshot in
            if let strokeValue = snapshot.value as? [String: Any?], self.localStrokeUids[snapshot.key] == nil,
               let stroke = Stroke.from(strokeValue) {
//                    print("RoomManager:strokeUpdateCallbacks: Partner Stroke Changed Observer")
                stroke.drawnLocally = false
                self.delegate?.partnerStrokeUpdated(stroke, id: snapshot.key)
            }
        } withCancel: { _ in
            print("Partner Stroke Changed Observer Cancelled")
        }

        self.strokeRemovedHandle = reference.observe(.childRemoved) { snapshot in
            print("Partner Stroke Removed Observer")
            if let stroke = self.localStrokeUids[snapshot.key] {
                self.delegate?.localStrokeRemoved(stroke)
                self.localStrokeUids[snapshot.key] = nil
            } else {
                self.delegate?.partnerStrokeRemoved(id: snapshot.key)
            }
        } withCancel: { _ in
            print("RoomManager:strokeUpdateCallbacks: Partner Stroke Removed Observer Cancelled")
        }
    }
}
