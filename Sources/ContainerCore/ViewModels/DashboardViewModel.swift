// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var snapshot: ContainerDashboardSnapshot
    @Published public private(set) var isRefreshing = false
    @Published public var selectedContainerID: String?
    @Published public var selectedSection: DashboardSection = .containers

    // Lazy resource-inspect selection + enriched detail (held here, never in the polled snapshot,
    // so background polls cannot clobber it).
    @Published public private(set) var selectedVolumeID: String?
    @Published public private(set) var selectedNetworkID: String?
    @Published public private(set) var volumeDetail: ResourceSummary?
    @Published public private(set) var networkDetail: ResourceSummary?

    // Lazy logs state for the selected container.
    @Published public private(set) var containerLogs: String?
    @Published public var logsShowBoot: Bool = false
    @Published public private(set) var isLoadingLogs = false
    @Published public private(set) var logsErrorMessage: String?

    private let coordinator: PollingCoordinator
    private let configuration: PollingConfiguration
    private var mode: PollingMode = .background
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var volumeInspectTask: Task<Void, Never>?
    private var networkInspectTask: Task<Void, Never>?
    private var logsTask: Task<Void, Never>?
    private var loadedLogsContainerID: String?

    public init(
        coordinator: PollingCoordinator,
        configuration: PollingConfiguration = PollingConfiguration()
    ) {
        self.coordinator = coordinator
        self.configuration = configuration
        self.snapshot = ContainerDashboardSnapshot()
    }

    public convenience init(
        client: ContainerCLIClient = ProcessContainerCLIClient(),
        configuration: PollingConfiguration = PollingConfiguration()
    ) {
        self.init(
            coordinator: PollingCoordinator(client: client),
            configuration: configuration
        )
    }

    deinit {
        pollTask?.cancel()
        refreshTask?.cancel()
        volumeInspectTask?.cancel()
        networkInspectTask?.cancel()
        logsTask?.cancel()
    }

    public var selectedContainer: ContainerSummary? {
        guard let selectedContainerID else { return snapshot.containers.first }
        return snapshot.containers.first { $0.id == selectedContainerID }
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func setPopoverVisible(_ visible: Bool) {
        mode = visible ? .foreground : .background
        if visible {
            refreshNow()
        }
    }

    public func select(containerID: String?) {
        guard containerID != selectedContainerID else { return }
        selectedContainerID = containerID
        // The selected container changed; drop any logs loaded for the previous one.
        clearLogs()
    }

    public func selectVolume(_ id: String?) {
        selectedVolumeID = id
        volumeDetail = nil
        volumeInspectTask?.cancel()
        guard let id else { return }
        volumeInspectTask = Task { [weak self] in
            guard let self else { return }
            let detail = try? await self.coordinator.inspectVolume(name: id)
            guard !Task.isCancelled, self.selectedVolumeID == id, let detail else { return }
            self.volumeDetail = detail
        }
    }

    public func selectNetwork(_ id: String?) {
        selectedNetworkID = id
        networkDetail = nil
        networkInspectTask?.cancel()
        guard let id else { return }
        networkInspectTask = Task { [weak self] in
            guard let self else { return }
            let detail = try? await self.coordinator.inspectNetwork(name: id)
            guard !Task.isCancelled, self.selectedNetworkID == id, let detail else { return }
            self.networkDetail = detail
        }
    }

    /// Containers attached to the named network, derived client-side (no CLI call) by filtering the
    /// current snapshot — `network inspect` does not report attached containers.
    public func containers(attachedTo networkName: String) -> [ContainerSummary] {
        snapshot.containers.filter { $0.networks.contains(networkName) }
    }

    public func loadLogs(for containerID: String, boot: Bool) {
        logsTask?.cancel()
        logsErrorMessage = nil
        isLoadingLogs = true
        loadedLogsContainerID = containerID
        logsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.coordinator.containerLogs(id: containerID, lines: 200, boot: boot)
                guard !Task.isCancelled, self.selectedContainerID == containerID else { return }
                self.containerLogs = text
                self.isLoadingLogs = false
            } catch {
                guard !Task.isCancelled, self.selectedContainerID == containerID else { return }
                self.containerLogs = nil
                self.logsErrorMessage = error.localizedDescription
                self.isLoadingLogs = false
            }
        }
    }

    /// Re-fetch logs for the current selection (e.g. after toggling `logsShowBoot`).
    public func reloadLogs() {
        guard let id = selectedContainerID else { return }
        loadLogs(for: id, boot: logsShowBoot)
    }

    private func clearLogs() {
        logsTask?.cancel()
        logsTask = nil
        containerLogs = nil
        logsErrorMessage = nil
        isLoadingLogs = false
        loadedLogsContainerID = nil
    }

    public func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh(force: true)
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh(force: false)
            let interval = configuration.interval(for: mode)
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    private func refresh(force: Bool) async {
        isRefreshing = true
        let nextSnapshot = await coordinator.refresh(mode: mode, force: force)
        snapshot = nextSnapshot
        isRefreshing = false

        if let selectedContainerID,
           !snapshot.containers.contains(where: { $0.id == selectedContainerID }) {
            select(containerID: snapshot.containers.first?.id)
        } else if selectedContainerID == nil {
            select(containerID: snapshot.containers.first?.id)
        }
    }
}
