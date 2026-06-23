import AppKit
import Combine
import ContainerCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let viewModel: DashboardViewModel
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        configureWindow()
        observeSnapshot()
        showInitialUI()
    }

    func stop() {
        viewModel.stop()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "shippingbox.fill",
            accessibilityDescription: "Apple container"
        ) ?? NSImage(
            systemSymbolName: "shippingbox",
            accessibilityDescription: "Apple container"
        )
        button.imagePosition = .imageLeading
        button.title = "ctr 0"
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 720, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(viewModel: viewModel) { [weak self] in
                self?.stop()
                NSApp.terminate(nil)
            }
        )
    }

    private func configureWindow() {
        let contentView = DashboardView(viewModel: viewModel) { [weak self] in
            self?.stop()
            NSApp.terminate(nil)
        }
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ContainerMenuBar"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("ContainerMenuBarDashboard")
        window.isReleasedWhenClosed = false
        self.window = window
    }

    private func observeSnapshot() {
        viewModel.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusItem(snapshot: snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(snapshot: ContainerDashboardSnapshot) {
        guard let button = statusItem.button else { return }
        button.title = snapshot.system.serviceRunning
            ? "ctr \(snapshot.runningCount)"
            : "ctr !"
        button.toolTip = snapshot.system.serviceRunning
            ? "\(snapshot.runningCount) running, \(snapshot.containers.count) total"
            : "Apple container service is not running"
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showInitialUI() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.showWindow()
            self.showPopover()
        }
    }

    private func showWindow() {
        viewModel.setPopoverVisible(true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        viewModel.setPopoverVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        viewModel.setPopoverVisible(false)
        popover.performClose(nil)
    }
}
