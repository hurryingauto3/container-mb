// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ContainerRuntimeState: String, Codable, Equatable, Sendable {
    case running
    case stopped
    case created
    case exited
    case unknown

    public init(rawStatus: String?) {
        let normalized = rawStatus?.lowercased() ?? ""
        switch normalized {
        case "running":
            self = .running
        case "stopped":
            self = .stopped
        case "created":
            self = .created
        case "exited":
            self = .exited
        default:
            self = .unknown
        }
    }

    public var isRunning: Bool { self == .running }
}

public struct ContainerPort: Identifiable, Equatable, Sendable {
    public var id: String {
        "\(hostAddress):\(hostPort ?? 0)->\(containerPort ?? 0)/\(protocolName)"
    }

    public let hostAddress: String
    public let hostPort: UInt16?
    public let containerPort: UInt16?
    public let protocolName: String
    public let count: UInt16

    public init(
        hostAddress: String,
        hostPort: UInt16?,
        containerPort: UInt16?,
        protocolName: String,
        count: UInt16 = 1
    ) {
        self.hostAddress = hostAddress
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocolName = protocolName
        self.count = count
    }

    public var hostDisplay: String {
        guard let hostPort else { return "unpublished" }
        let address = hostAddress.isEmpty || hostAddress == "0.0.0.0" ? "localhost" : hostAddress
        return "\(address):\(hostPort)"
    }

    public var mappingDisplay: String {
        let container = containerPort.map(String.init) ?? "?"
        return "\(hostDisplay) -> \(container)/\(protocolName)"
    }
}

public struct ContainerStatsSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let memoryUsageBytes: UInt64?
    public let memoryLimitBytes: UInt64?
    public let cpuUsageUsec: UInt64?
    public let cpuPercent: Double?
    public let networkRxBytes: UInt64?
    public let networkTxBytes: UInt64?
    public let blockReadBytes: UInt64?
    public let blockWriteBytes: UInt64?
    public let processCount: UInt64?

    public init(
        id: String,
        memoryUsageBytes: UInt64? = nil,
        memoryLimitBytes: UInt64? = nil,
        cpuUsageUsec: UInt64? = nil,
        cpuPercent: Double? = nil,
        networkRxBytes: UInt64? = nil,
        networkTxBytes: UInt64? = nil,
        blockReadBytes: UInt64? = nil,
        blockWriteBytes: UInt64? = nil,
        processCount: UInt64? = nil
    ) {
        self.id = id
        self.memoryUsageBytes = memoryUsageBytes
        self.memoryLimitBytes = memoryLimitBytes
        self.cpuUsageUsec = cpuUsageUsec
        self.cpuPercent = cpuPercent
        self.networkRxBytes = networkRxBytes
        self.networkTxBytes = networkTxBytes
        self.blockReadBytes = blockReadBytes
        self.blockWriteBytes = blockWriteBytes
        self.processCount = processCount
    }
}

public struct ResourceLimit: Equatable, Sendable {
    public let cpus: Int?
    public let memoryBytes: UInt64?
    public let storageBytes: UInt64?

    public init(cpus: Int? = nil, memoryBytes: UInt64? = nil, storageBytes: UInt64? = nil) {
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.storageBytes = storageBytes
    }
}

public struct ContainerSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let image: String
    public let state: ContainerRuntimeState
    public let createdAt: Date?
    public let startedAt: Date?
    public let ipAddresses: [String]
    public let ports: [ContainerPort]
    public let labels: [String: String]
    public let mounts: [String]
    public let networks: [String]
    public let command: String?
    public let resources: ResourceLimit
    public let raw: JSONValue

    public init(
        id: String,
        image: String,
        state: ContainerRuntimeState,
        createdAt: Date? = nil,
        startedAt: Date? = nil,
        ipAddresses: [String] = [],
        ports: [ContainerPort] = [],
        labels: [String: String] = [:],
        mounts: [String] = [],
        networks: [String] = [],
        command: String? = nil,
        resources: ResourceLimit = ResourceLimit(),
        raw: JSONValue
    ) {
        self.id = id
        self.image = image
        self.state = state
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.ipAddresses = ipAddresses
        self.ports = ports
        self.labels = labels
        self.mounts = mounts
        self.networks = networks
        self.command = command
        self.resources = resources
        self.raw = raw
    }

    public var shortID: String { String(id.prefix(12)) }
}

public struct ResourceAttribute: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var id: String { label }
}

public struct ResourceSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String?
    public let attributes: [ResourceAttribute]

    public init(
        id: String,
        name: String,
        detail: String? = nil,
        attributes: [ResourceAttribute] = []
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.attributes = attributes
    }
}

public enum DashboardSection: String, CaseIterable, Identifiable, Equatable, Sendable {
    case containers
    case volumes
    case networks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .containers: return "Containers"
        case .volumes: return "Volumes"
        case .networks: return "Networks"
        }
    }
}

public struct ContainerSystemState: Equatable, Sendable {
    public let installed: Bool
    public let serviceRunning: Bool
    public let version: String?
    public let message: String?

    public init(
        installed: Bool,
        serviceRunning: Bool,
        version: String? = nil,
        message: String? = nil
    ) {
        self.installed = installed
        self.serviceRunning = serviceRunning
        self.version = version
        self.message = message
    }

    public static let unknown = ContainerSystemState(
        installed: false,
        serviceRunning: false,
        message: "container CLI not found"
    )
}

public struct ContainerDashboardSnapshot: Equatable, Sendable {
    public let containers: [ContainerSummary]
    public let statsByID: [String: ContainerStatsSnapshot]
    public let networks: [ResourceSummary]
    public let volumes: [ResourceSummary]
    public let system: ContainerSystemState
    public let lastUpdated: Date
    public let isStale: Bool
    public let errorMessage: String?

    public init(
        containers: [ContainerSummary] = [],
        statsByID: [String: ContainerStatsSnapshot] = [:],
        networks: [ResourceSummary] = [],
        volumes: [ResourceSummary] = [],
        system: ContainerSystemState = .unknown,
        lastUpdated: Date = Date(),
        isStale: Bool = false,
        errorMessage: String? = nil
    ) {
        self.containers = containers
        self.statsByID = statsByID
        self.networks = networks
        self.volumes = volumes
        self.system = system
        self.lastUpdated = lastUpdated
        self.isStale = isStale
        self.errorMessage = errorMessage
    }

    public var runningCount: Int {
        containers.filter { $0.state.isRunning }.count
    }
}
