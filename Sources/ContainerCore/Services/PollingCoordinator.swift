// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum PollingMode: Equatable, Sendable {
    case foreground
    case background
}

public struct PollingConfiguration: Equatable, Sendable {
    public let foregroundInterval: TimeInterval
    public let backgroundInterval: TimeInterval

    public init(foregroundInterval: TimeInterval = 5, backgroundInterval: TimeInterval = 30) {
        self.foregroundInterval = foregroundInterval
        self.backgroundInterval = backgroundInterval
    }

    public func interval(for mode: PollingMode) -> TimeInterval {
        mode == .foreground ? foregroundInterval : backgroundInterval
    }
}

public actor PollingCoordinator {
    private let client: ContainerCLIClient
    private var cachedSnapshot = ContainerDashboardSnapshot()
    private var cachedNetworks: [ResourceSummary] = []
    private var cachedVolumes: [ResourceSummary] = []
    private var cachedImages: [ImageSummary] = []
    private var cachedDiskUsage: DiskUsage?
    private var cachedStatsByID: [String: ContainerStatsSnapshot] = [:]
    private var previousStatsByID: [String: ContainerStatsSnapshot] = [:]
    private var previousStatsDate: Date?
    private var lastContainerSignature = ""
    private var isRefreshing = false

    public init(client: ContainerCLIClient) {
        self.client = client
    }

    public func snapshot() -> ContainerDashboardSnapshot {
        cachedSnapshot
    }

    public func refresh(mode: PollingMode, force: Bool = false) async -> ContainerDashboardSnapshot {
        if isRefreshing {
            return staleSnapshot(message: "Refresh already in progress")
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let system = await client.systemState()

        do {
            let containers = try await client.listContainers()
            let signature = containers
                .map { "\($0.id):\($0.state.rawValue)" }
                .sorted()
                .joined(separator: "|")

            if shouldRefreshStats(mode: mode, force: force, signature: signature) {
                let sampledAt = Date()
                let stats = try await client.stats()
                cachedStatsByID = dictionaryByID(enrichCPUPercent(stats: stats, sampledAt: sampledAt))
            }

            if mode == .foreground || force || cachedNetworks.isEmpty {
                cachedNetworks = (try? await client.listNetworks()) ?? cachedNetworks
            }

            if mode == .foreground || force || cachedVolumes.isEmpty {
                cachedVolumes = (try? await client.listVolumes()) ?? cachedVolumes
            }

            if mode == .foreground || force || cachedImages.isEmpty {
                cachedImages = (try? await client.listImages()) ?? cachedImages
            }

            // `system df` is cheap (no double-sample like `stats`), so refresh it on every poll
            // rather than gating it behind the stats signature: disk usage changes when images
            // or volumes change even if the running container set does not. Both foreground (5s)
            // and background (30s) cadences are slow relative to its cost.
            cachedDiskUsage = (try? await client.diskUsage()) ?? cachedDiskUsage

            lastContainerSignature = signature
            cachedSnapshot = ContainerDashboardSnapshot(
                containers: containers,
                statsByID: cachedStatsByID,
                networks: cachedNetworks,
                volumes: cachedVolumes,
                images: cachedImages,
                diskUsage: cachedDiskUsage,
                system: system,
                lastUpdated: Date(),
                isStale: false
            )
            return cachedSnapshot
        } catch {
            cachedSnapshot = ContainerDashboardSnapshot(
                containers: cachedSnapshot.containers,
                statsByID: cachedStatsByID,
                networks: cachedNetworks,
                volumes: cachedVolumes,
                images: cachedImages,
                diskUsage: cachedDiskUsage,
                system: system,
                lastUpdated: cachedSnapshot.lastUpdated,
                isStale: true,
                errorMessage: error.localizedDescription
            )
            return cachedSnapshot
        }
    }

    private func shouldRefreshStats(mode: PollingMode, force: Bool, signature: String) -> Bool {
        guard cachedSnapshot.containers.contains(where: { $0.state.isRunning }) || signature.contains("running") else {
            return force
        }

        return force
            || mode == .foreground
            || cachedStatsByID.isEmpty
            || signature != lastContainerSignature
    }

    private func dictionaryByID(_ stats: [ContainerStatsSnapshot]) -> [String: ContainerStatsSnapshot] {
        Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0) })
    }

    private func enrichCPUPercent(
        stats: [ContainerStatsSnapshot],
        sampledAt: Date
    ) -> [ContainerStatsSnapshot] {
        defer {
            previousStatsByID = dictionaryByID(stats)
            previousStatsDate = sampledAt
        }

        guard let previousStatsDate else { return stats }
        let elapsedUsec = sampledAt.timeIntervalSince(previousStatsDate) * 1_000_000
        guard elapsedUsec > 0 else { return stats }

        return stats.map { current in
            guard
                let currentUsec = current.cpuUsageUsec,
                let previousUsec = previousStatsByID[current.id]?.cpuUsageUsec,
                currentUsec >= previousUsec
            else {
                return current
            }

            let cpuDelta = Double(currentUsec - previousUsec)
            let cpuPercent = (cpuDelta / elapsedUsec) * 100
            return ContainerStatsSnapshot(
                id: current.id,
                memoryUsageBytes: current.memoryUsageBytes,
                memoryLimitBytes: current.memoryLimitBytes,
                cpuUsageUsec: current.cpuUsageUsec,
                cpuPercent: cpuPercent,
                networkRxBytes: current.networkRxBytes,
                networkTxBytes: current.networkTxBytes,
                blockReadBytes: current.blockReadBytes,
                blockWriteBytes: current.blockWriteBytes,
                processCount: current.processCount
            )
        }
    }

    private func staleSnapshot(message: String) -> ContainerDashboardSnapshot {
        ContainerDashboardSnapshot(
            containers: cachedSnapshot.containers,
            statsByID: cachedSnapshot.statsByID,
            networks: cachedSnapshot.networks,
            volumes: cachedSnapshot.volumes,
            images: cachedSnapshot.images,
            diskUsage: cachedSnapshot.diskUsage,
            system: cachedSnapshot.system,
            lastUpdated: cachedSnapshot.lastUpdated,
            isStale: true,
            errorMessage: message
        )
    }
}
