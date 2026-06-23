import Combine
import Foundation

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var snapshot: ContainerDashboardSnapshot
    @Published public private(set) var isRefreshing = false
    @Published public var selectedContainerID: String?

    private let coordinator: PollingCoordinator
    private let configuration: PollingConfiguration
    private var mode: PollingMode = .background
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

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
        selectedContainerID = containerID
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
            self.selectedContainerID = snapshot.containers.first?.id
        } else if selectedContainerID == nil {
            selectedContainerID = snapshot.containers.first?.id
        }
    }
}
