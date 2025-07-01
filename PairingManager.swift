// swiftlint:disable file_length no_grouping_extension
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

import ARCore
import FirebaseAnalytics
import Foundation
import NearbyConnections
import RealityKit

protocol PairingManagerDelegate: AnyObject {
    func localStrokeRemoved(_ stroke: Stroke)
    func partnerStrokeUpdated(_ stroke: Stroke, id key: String)
    func partnerStrokeRemoved(id key: String)
    func cloudAnchorResolved(_ anchor: GARAnchor)
    func partnerJoined(isHost: Bool)
    func partnerLost()
    func createAnchor()
    func anchorWasReset()
    func offlineDetected()
    func isTracking() -> Bool
}

// swiftlint:disable:next type_body_length
class PairingManager: NSObject {
    // MARK: Properties

    /// Delegate property for ViewController
    weak var delegate: PairingManagerDelegate?

    /// RoomManager handles Firebase interactions
    let roomManager: RoomManager

    /// GoogleAR Session
    var gSession: GARSession?

    @objc var garAnchor: GARAnchor?

    var reachability = Reachability.forInternetConnection()

    var anchorObserver: NSKeyValueObservation?

    var isPairingOrPaired = false

    var readyToSetAnchor = false

    var partnerReadyToSetAnchor = false

    var firebaseKey: String = ""

    var pairingTimeout: Timer?

    var discoveryTimeout: Timer?

    /// Nearby Connections components
    private var advertiser: Advertiser?
    private var discoverer: Discoverer?
    private var connectionManager: ConnectionManager?

    /// Connection state
    private var connectedEndpoints: Set<String> = []
    private var pendingConnections: Set<String> = []

    // Service ID for Nearby Connections
    private let serviceID = "com.google.justaline.nearby"

    // MARK: Lifecycle

    // MARK: Methods

    override init() {
        roomManager = RoomManager()

        // swiftlint:disable:next legacy_objc_type
        var myDict: NSDictionary?
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            // swiftlint:disable:next legacy_objc_type
            myDict = NSDictionary(contentsOfFile: path)
        }

        if let myDict, let key = myDict["API_KEY"] as? String {
            print("PairingManager: Setting Firebase API key: \(key)")
            firebaseKey = key
        }

        super.init()

        createGSession()
        setupNearbyConnections()
    }

    // MARK: Functions

    func createGSession() {
        if gSession == nil {
            do {
                try gSession = GARSession(apiKey: firebaseKey, bundleIdentifier: nil)
                print("Created GoogleAR session: \(String(describing: gSession))")
            } catch let error as NSError {
                print("PairingManager: Couldn't start GoogleAR session: \(error)")
            }
            let configuration = GARSessionConfiguration()
            configuration.cloudAnchorMode = .enabled
            var error: NSError?
            gSession?.setConfiguration(configuration, error: &error)
            if let error {
                print("Failed to configure the GARSession: \(error)")
            }
        }
    }

    func setGlobalRoomName(_ name: String) {
        roomManager.updateGlobalRoomName(name)
    }

    func beginGlobalSession(_ withPairing: Bool) {
        print("PairingManager: beginGlobalSession")
        configureReachability()

        isPairingOrPaired = true

        roomManager.delegate = self

        if let session = gSession {
            print("PairingManager: gSession: \(session.description)")
            session.delegate = self
            session.delegateQueue = DispatchQueue.main
        } else {
            print("PairingManager: Couldn't start GoogleAR session")
        }

        if reachability?.currentReachabilityStatus() == .NotReachable {
            StateManager.updateState(.OFFLINE)
        } else if withPairing == true {
            StateManager.updateState(.LOOKING)
        }
        roomManager.findGlobalRoom(withPairing)
    }

    func beginPairing() {
        print("PairingManager: beginPairing")
        configureReachability()

        beginDiscoveryTimeout()

        isPairingOrPaired = true

        roomManager.delegate = self

        if let session = gSession {
            session.delegate = self
            session.delegateQueue = DispatchQueue.main
        }

        // Start advertising and discovering using Nearby Connections
        startNearbyConnections()

        // swiftlint:disable:next force_cast
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if appDelegate.pairingState == nil || appDelegate.pairingState != .OFFLINE {
            StateManager.updateState(.LOOKING)

            // build a room for potential use (if end up being the host)
            roomManager.createRoom()
        }
    }

    func resumeSession(fromDate _: Date) {
        roomManager.resumeRoom()
    }

    func configureReachability() {
        let unreachableBlock = {
            DispatchQueue.main.async {
                StateManager.updateState(.OFFLINE)

                if self.isPairingOrPaired {
                    self.delegate?.offlineDetected()
                }
            }
        }

        // Check current state
        if let reachable = reachability?.isReachable(), reachable == false {
            unreachableBlock()
        }

        reachability?.reachableBlock = { reachability in
            if reachability?.currentReachabilityStatus() == .ReachableViaWiFi {
                print("Reachable via WiFi")
                StateManager.updateState(.NO_STATE)
            } else {
                print("Reachable via Cellular")
                StateManager.updateState(.NO_STATE)
            }
        }
        reachability?.unreachableBlock = { _ in
            print("Not reachable")
            unreachableBlock()
        }

        reachability?.startNotifier()
    }

    /// Send updated stroke to Firebase
    func updateStroke(_ stroke: Stroke) {
        roomManager.updateStroke(stroke)
    }

    func removeStroke(_ stroke: Stroke) {
        roomManager.updateStroke(stroke, shouldRemove: true)
    }

    func clearAllStrokes() {
        roomManager.clearAllStrokes()
    }

    /// Once host has made an initial drawing to share, and tapped done, send an ARAnchor based at drawing's node position to GARSession
    func setAnchor(_ anchor: ARAnchor) {
        print("PairingManager: setAnchor: Attempting to Host Cloud Anchor")
        do {
            try self.garAnchor = self.gSession?.hostCloudAnchor(anchor)
            NSLog("Attempting to Host Cloud Anchor: %@ with ARAnchor: %@", garAnchor?.identifier.uuidString ?? "NO ANCHOR", String(describing: anchor))
        } catch let error as NSError {
            print("PairingManager: setAnchor: Hosting cloud anchor failed: \(error)")
        }
    }

    func setReadyToSetAnchor() {
        print("PairingManager: setReadyToSetAnchor: isHost: \(roomManager.isHost), partnerReadyToSetAnchor: \(partnerReadyToSetAnchor)")
        readyToSetAnchor = true
        roomManager.setReadyToSetAnchor()

        if roomManager.isHost, partnerReadyToSetAnchor {
            sendSetAnchorEvent()
        } else if roomManager.isHost {
            StateManager.updateState(.HOST_READY_AND_WAITING)
        } else if partnerReadyToSetAnchor {
            StateManager.updateState(.PARTNER_CONNECTING)
            beginPairingTimeout()
        } else {
            #if !JOIN_GLOBAL_ROOM
                StateManager.updateState(.PARTNER_READY_AND_WAITING)
            #else
                sendSetAnchorEvent()
            #endif
        }
    }

    func sendSetAnchorEvent() {
        print("sendSetAnchorEvent")
        delegate?.createAnchor()
        #if !JOIN_GLOBAL_ROOM
            StateManager.updateState(.HOST_CONNECTING)
        #endif
        beginPairingTimeout()
    }

    func retryResolvingAnchor() {
        print("PairingManager: retryResolvingAnchor")

        roomManager.retryResolvingAnchor()
        beginPairingTimeout()
    }

    func stopObservingLines() {
        roomManager.stopObservingLines()
    }

    func beginDiscoveryTimeout() {
        if discoveryTimeout == nil {
            discoveryTimeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false, block: { _ in
                print("PairingManager: beginDiscoveryTimeout - Discovery Timed Out")
                self.stopRoomDiscovery()
                StateManager.updateState(.DISCOVERY_TIMEOUT)

                self.roomManager.anchorFailedToResolve()
                Analytics.logEvent(AnalyticsKey.val(.pair_error_discovery_timeout), parameters: nil)
            })
        }
    }

    func cancelDiscoveryTimeout() {
        discoveryTimeout?.invalidate()
        discoveryTimeout = nil
    }

    func beginPairingTimeout() {
        if pairingTimeout == nil {
            pairingTimeout = Timer.scheduledTimer(withTimeInterval: 60, repeats: false, block: { _ in
                print("PairingManager: beginPairingTimeout - Pairing Timed Out")
                if self.gSession != nil {
                    self.gSession = nil
                    self.createGSession()
                }
                self.roomManager.isRetrying = false
                self.roomManager.anchorFailedToResolve()

                let params = [AnalyticsKey.val(.pair_error_sync_reason): AnalyticsKey.val(.pair_error_sync_reason_timeout)]
                Analytics.logEvent(AnalyticsKey.val(.pair_error_sync), parameters: params)
            })
        }
    }

    func cancelPairingTimeout() {
        self.roomManager.isRetrying = false
        pairingTimeout?.invalidate()
        pairingTimeout = nil
    }

    /// Stop Nearby Connections
    func stopRoomDiscovery() {
        stopNearbyConnections()
        cancelDiscoveryTimeout()
    }

    func roomCreated(_ roomData: RoomData) {
        print("Room Created with Room Number: \(roomData.code)")
        // With Nearby Connections, we'll send room data when connections are established
        // Store room data for sending to connected endpoints
    }

    func leaveRoom() {
        roomManager.leaveRoom()
        stopRoomDiscovery()
        readyToSetAnchor = false
        partnerReadyToSetAnchor = false
    }

    func cancelPairing() {
        isPairingOrPaired = false
        leaveRoom()
        resetGSession()
    }

    func resetGSession() {
        print("PairingManager: resetGSession")
        gSession = nil

        // restart gar session so that it is available next time
        createGSession()
    }

    private func setupNearbyConnections() {
        // Initialize Nearby Connections components
        connectionManager = ConnectionManager(serviceID: Config.serviceID, strategy: .cluster)
        // swiftlint:disable:next force_unwrapping
        advertiser = Advertiser(connectionManager: connectionManager!)
        // swiftlint:disable:next force_unwrapping
        discoverer = Discoverer(connectionManager: connectionManager!)

        // Set delegates
        advertiser?.delegate = self
        discoverer?.delegate = self
        connectionManager?.delegate = self
    }

    private func startNearbyConnections() {
        // Start both advertising and discovering
        startAdvertising()
        startDiscovering()
    }

    private func startAdvertising() {
        guard let advertiser else {
            return
        }

        let deviceName = UIDevice.current.name
        let advertisingData = deviceName.data(using: .utf8) ?? Data()

        do {
            try advertiser.startAdvertising(using: advertisingData)
            print("Started advertising for Nearby Connections")
        } catch {
            print("Failed to start advertising: \(error)")
        }
    }

    private func startDiscovering() {
        guard let discoverer else {
            return
        }

        do {
            try discoverer.startDiscovery()
            print("Started discovering for Nearby Connections")
        } catch {
            print("Failed to start discovery: \(error)")
        }
    }

    private func sendRoomData(_ roomData: RoomData, to endpointID: String) {
        guard let connectionManager else {
            return
        }

        let messageData = roomData.getMessageData()

        do {
            try connectionManager.send(messageData, to: [endpointID])
        } catch {
            print("Failed to send room data: \(error)")
        }
    }

    private func stopNearbyConnections() {
        advertiser?.stopAdvertising()
        discoverer?.stopDiscovery()
//        connectionManager?.disconnect(from: EndpointID, )

        connectedEndpoints.removeAll()
        pendingConnections.removeAll()
    }
}

// MARK: - Nearby Connections Delegate Extensions

extension PairingManager: AdvertiserDelegate {
    func advertiser(
        _: Advertiser,
        didReceiveConnectionRequestFrom endpointID: String,
        with _: Data,
        connectionRequestHandler: @escaping (Bool) -> Void
    ) {
        print("Received connection request from: \(endpointID)")

        // Accept the connection request
        connectionRequestHandler(true)
        pendingConnections.insert(endpointID)
    }

    func advertiser(
        _: Advertiser,
        didFailToStartAdvertisingWithError error: Error
    ) {
        print("Failed to start advertising: \(error)")
    }
}

extension PairingManager: DiscovererDelegate {
    func discoverer(
        _ discoverer: Discoverer,
        didFind endpointID: String,
        with _: Data
    ) {
        print("Found endpoint: \(endpointID)")

        // Request connection to the found endpoint
        let deviceName = UIDevice.current.name
        let connectionData = deviceName.data(using: .utf8) ?? Data()

        do {
            try discoverer.requestConnection(to: endpointID, using: connectionData)
            pendingConnections.insert(endpointID)
        } catch {
            print("Failed to request connection: \(error)")
        }
    }

    func discoverer(
        _: Discoverer,
        didLose endpointID: String
    ) {
        print("Lost endpoint: \(endpointID)")
        connectedEndpoints.remove(endpointID)
        pendingConnections.remove(endpointID)
    }

    func discoverer(
        _: Discoverer,
        didFailToStartDiscoveryWithError error: Error
    ) {
        print("Failed to start discovery: \(error)")
    }
}

extension PairingManager: ConnectionManagerDelegate {
    func connectionManager(
        _: NearbyConnections.ConnectionManager,
        didChangeTo state: NearbyConnections.ConnectionState,
        for endpointID: NearbyConnections.EndpointID
    ) {
        print("ConnectionManagerDelegate: didChangeTo: \(state), for: \(endpointID)")
    }

    func connectionManager(
        _: NearbyConnections.ConnectionManager,
        didReceiveTransferUpdate update: NearbyConnections.TransferUpdate,
        from endpointID: NearbyConnections.EndpointID,
        forPayload _: NearbyConnections.PayloadID
    ) {
        print("ConnectionManagerDelegate: didReceiveTransferUpdate: \(update), for: \(endpointID)")
    }

    // swiftlint:disable:next function_parameter_count
    func connectionManager(
        _: NearbyConnections.ConnectionManager,
        didStartReceivingResourceWithID payloadID: NearbyConnections.PayloadID,
        from endpointID: NearbyConnections.EndpointID,
        at _: URL,
        withName _: String,
        cancellationToken _: NearbyConnections.CancellationToken
    ) {
        print("ConnectionManagerDelegate: didStartReceivingResourceWithID: \(payloadID), for: \(endpointID)")
    }

    func connectionManager(
        _: NearbyConnections.ConnectionManager,
        didReceive _: InputStream,
        withID payloadID: NearbyConnections.PayloadID,
        from endpointID: NearbyConnections.EndpointID,
        cancellationToken _: NearbyConnections.CancellationToken
    ) {
        print("ConnectionManagerDelegate: didReceive stream: \(payloadID), for: \(endpointID)")
    }

    func connectionManager(
        _: NearbyConnections.ConnectionManager,
        didReceive _: Data,
        withID payloadID: NearbyConnections.PayloadID,
        from endpointID: NearbyConnections.EndpointID
    ) {
        print("dConnectionManagerDelegate: idReceive data: \(payloadID), for: \(endpointID)")
    }

    func connectionManager(
        _: ConnectionManager,
        didReceive verificationCode: String,
        from endpointID: String,
        verificationHandler: @escaping (Bool) -> Void
    ) {
        print("ConnectionManagerDelegate: Received verification code: \(verificationCode) from: \(endpointID)")

        // Auto-accept verification for simplicity
        // In a production app, you might want to show this code to the user
        verificationHandler(true)
    }

    func connectionManager(_: ConnectionManager, didConnect endpointID: String) {
        print("ConnectionManagerDelegate: Connected to endpoint: \(endpointID)")

        connectedEndpoints.insert(endpointID)
        pendingConnections.remove(endpointID)

        // Notify delegate of partner joined
        delegate?.partnerJoined(isHost: !roomManager.isHost)

        // Send room data if we have it
        if let roomData = roomManager.currentRoomData {
            sendRoomData(roomData, to: endpointID)
        }

        // Stop discovery once connected
        discoverer?.stopDiscovery()
        cancelDiscoveryTimeout()
    }

    func connectionManager(_: ConnectionManager, didDisconnectFrom endpointID: String) {
        print("ConnectionManagerDelegate: Disconnected from endpoint: \(endpointID)")

        connectedEndpoints.remove(endpointID)
        pendingConnections.remove(endpointID)

        if connectedEndpoints.isEmpty {
            delegate?.partnerLost()
        }
    }

    func connectionManager(_: ConnectionManager, didReceive data: Data, from endpointID: String) {
        print("ConnectionManagerDelegate: Received data from: \(endpointID)")

        // Handle received room data
        handleReceivedRoomData(data)
    }

    func connectionManager(_: ConnectionManager, didFailToConnect endpointID: String, withError error: Error) {
        print("ConnectionManagerDelegate: Failed to connect to \(endpointID): \(error)")

        pendingConnections.remove(endpointID)
    }

    func handleReceivedRoomData(_ data: Data) {
        // Parse the received room data and handle accordingly
        // This logic would be similar to the original message handling
        let roomData = RoomData(data)
        roomManager.roomFound(roomData)
    }
}

// MARK: - RoomManagerDelegate

extension PairingManager: RoomManagerDelegate {
    func anchorIdCreated(_ id: String) {
        print("RoomManagerDelegate: Resolving GARAnchor: \(id)")
        if self.gSession == nil {
            print("There is a problem with your co-presence session")
            pairingFailed()
            #if JOIN_GLOBAL_ROOM
                StateManager.updateState(.GLOBAL_RESOLVE_ERROR)
            #else
                StateManager.updateState(.PARTNER_RESOLVE_ERROR)
            #endif
            cancelPairingTimeout()
        }

        do {
            try self.garAnchor = self.gSession?.resolveCloudAnchor(id)
        } catch let error as NSError {
            print("PairingManager:anchorIdCreated: Resolve Cloud Anchor Failed with Error: \(error)")
            pairingFailed()
            roomManager.anchorFailedToResolve()
            #if JOIN_GLOBAL_ROOM
                StateManager.updateState(.GLOBAL_RESOLVE_ERROR)
            #else
                StateManager.updateState(.PARTNER_RESOLVE_ERROR)
            #endif
            cancelPairingTimeout()
        }
    }

    func anchorResolved() {
        StateManager.updateState(.SYNCED)
        Analytics.logEvent(AnalyticsKey.val(.pair_success), parameters: nil)
        cancelPairingTimeout()
        roomManager.anchorResolved()
    }

    func anchorNotAvailable() {
        if isPairingOrPaired, roomManager.isRoomResolved {
            self.leaveRoom()
            delegate?.anchorWasReset()
        }
    }

    func localStrokeRemoved(_ stroke: Stroke) {
        delegate?.localStrokeRemoved(stroke)
    }

    func partnerStrokeUpdated(_ stroke: Stroke, id key: String) {
        delegate?.partnerStrokeUpdated(stroke, id: key)
    }

    func partnerStrokeRemoved(id key: String) {
        delegate?.partnerStrokeRemoved(id: key)
    }

    // swiftlint:disable:next discouraged_optional_boolean
    func partnerJoined(isHost: Bool, isPairing: Bool?) {
        print("PairingManager: partnerJoined: isHost: \(isHost)")
        delegate?.partnerJoined(isHost: isHost)

        #if JOIN_GLOBAL_ROOM

        #else
            if let pairing = isPairing, pairing == true {
                if isHost {
                    StateManager.updateState(.HOST_CONNECTED)
                } else {
                    StateManager.updateState(.PARTNER_CONNECTED)
                }
                stopRoomDiscovery()
            }
        #endif
    }

    func partnerLost() {
        if isPairingOrPaired == true {
            self.delegate?.partnerLost()
        }
    }

    func pairingFailed() {
        print("Pairing Failed")
        readyToSetAnchor = false
        partnerReadyToSetAnchor = false
    }

    func updatePartnerAnchorReadiness(partnerReady: Bool, isHost: Bool) {
        print("PairingManager: updatePartnerAnchorReadiness: partnerReady: \(partnerReady), isHost: \(isHost)")
        partnerReadyToSetAnchor = partnerReady

        if partnerReady, isHost {
            if readyToSetAnchor {
                sendSetAnchorEvent()
            }
        } else if partnerReady {
            if readyToSetAnchor {
                StateManager.updateState(.PARTNER_CONNECTING)
                beginPairingTimeout()
            }
        } else {
            partnerReadyToSetAnchor = false
        }
    }
}

// MARK: - GARSessionDelegate

extension PairingManager: GARSessionDelegate {
    // swiftlint:disable:next cyclomatic_complexity
    private static func stringFromCloudState(_ cloudState: GARCloudAnchorState) -> String {
        switch cloudState {
        case .none:
            "None"

        case .success:
            "Success"

        case .errorInternal:
            "ErrorInternal"

        case .errorNotAuthorized:
            "ErrorNotAuthorized"

        case .errorResourceExhausted:
            "ErrorResourceExhausted"

        case .errorHostingDatasetProcessingFailed:
            "ErrorHostingDatasetProcessingFailed"

        case .errorCloudIdNotFound:
            "ErrorCloudIdNotFound"

        case .errorResolvingSdkVersionTooNew:
            "ErrorResolvingSdkVersionTooNew"

        case .errorResolvingSdkVersionTooOld:
            "ErrorResolvingSdkVersionTooOld"

        case .errorHostingServiceUnavailable:
            "ErrorHostingServiceUnavailable"

        default:
            // Not handling deprecated enum values that will never be returned.
            "Unknown"
        }
    }

    func session(_ session: GARSession, didResolve anchor: GARAnchor) {
        print("GARAnchor Resolved: \(String(describing: session))")
        self.delegate?.cloudAnchorResolved(anchor)
        self.anchorResolved()
    }

    func session(_ session: GARSession, didHost anchor: GARAnchor) {
        print("GARSession did host anchor: \(String(describing: session))")
        delegate?.cloudAnchorResolved(anchor)

        if anchor.cloudState == .success {
            roomManager.setAnchorId(anchor.identifier.uuidString)
        } else {
            failHostAnchor(anchor)
        }
    }

    func session(_: GARSession, didFailToResolve anchor: GARAnchor) {
        print("GARSession did fail to resolve anchor: \(Self.stringFromCloudState(anchor.cloudState))")
        #if JOIN_GLOBAL_ROOM
            StateManager.updateState(.GLOBAL_RESOLVE_ERROR)
        #else
            StateManager.updateState(.PARTNER_RESOLVE_ERROR)
        #endif
        pairingFailed()
        roomManager.anchorFailedToResolve()
        cancelPairingTimeout()

        var reason = ""
        if delegate?.isTracking() != nil {
            reason = String(anchor.cloudState.rawValue)
        } else {
            reason = AnalyticsKey.val(.pair_error_sync_reason_not_tracking)
        }
        let params = [AnalyticsKey.val(.pair_error_sync_reason): reason]
        Analytics.logEvent(AnalyticsKey.val(.pair_error_sync), parameters: params)
    }

    func session(_: GARSession, didFailToHost anchor: GARAnchor) {
        failHostAnchor(anchor)
    }

    func failHostAnchor(_ anchor: GARAnchor) {
        print("🚨 GARSession did fail to host anchor: \(Self.stringFromCloudState(anchor.cloudState))")
        StateManager.updateState(.HOST_ANCHOR_ERROR)

        pairingFailed()
        roomManager.anchorFailedToResolve()
        cancelPairingTimeout()

        let params = [AnalyticsKey.val(.pair_error_sync_reason): String(anchor.cloudState.rawValue)]
        Analytics.logEvent(AnalyticsKey.val(.pair_error_sync), parameters: params)
    }
}
