//
//  Copyright 2023 Google LLC
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import NearbyConnections

struct Payload: Identifiable {
    // MARK: Nested Types

    enum PayloadType {
        case bytes
        case stream
        case file
    }

    enum Status {
        case inProgress(Progress)
        case success
        case failure
        case canceled
    }

    // MARK: Properties

    let id: PayloadID
    let isIncoming: Bool
    let cancellationToken: CancellationToken?
    let data: Data?
    var type: PayloadType
    var status: Status

    // MARK: Lifecycle

    // Convenience initializer for creating outgoing data payloads
    init(data: Data) {
        self.id = PayloadID(Int64.random(in: 1 ... Int64.max))
        self.type = .bytes
        self.status = .success
        self.isIncoming = false
        self.cancellationToken = nil
        self.data = data
    }

    // Full initializer for incoming payloads from NearbyConnections
    init(id: PayloadID, type: PayloadType, status: Status, isIncoming: Bool, cancellationToken: CancellationToken?, data: Data?) {
        self.id = id
        self.type = type
        self.status = status
        self.isIncoming = isIncoming
        self.cancellationToken = cancellationToken
        self.data = data
    }
}
