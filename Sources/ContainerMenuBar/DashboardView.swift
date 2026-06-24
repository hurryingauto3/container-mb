// SPDX-License-Identifier: Apache-2.0

import AppKit
import ContainerCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            sectionPicker
            Divider()
            content
        }
        .frame(minWidth: 700, idealWidth: 720, maxWidth: 780, minHeight: 580, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.snapshot.system.serviceRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(viewModel.snapshot.system.serviceRunning ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple container")
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(AppVersion.current)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("ContainerMenuBar \(AppVersion.current)")
                .accessibilityLabel("App version \(AppVersion.current)")
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
            }
            Button {
                viewModel.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            Button {
                onQuit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            MetricBadge(title: "Running", value: "\(viewModel.snapshot.runningCount)")
            MetricBadge(title: "Total", value: "\(viewModel.snapshot.containers.count)")
            MetricBadge(title: "Networks", value: "\(viewModel.snapshot.networks.count)")
            MetricBadge(title: "Volumes", value: "\(viewModel.snapshot.volumes.count)")
            Spacer()
            Text("Updated \(DisplayFormatters.relativeDate(viewModel.snapshot.lastUpdated))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $viewModel.selectedSection) {
            ForEach(DashboardSection.allCases) { section in
                Text(sectionLabel(for: section)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.snapshot.system.installed {
            EmptyStateView(title: "container CLI not found", detail: "Install Apple container and make sure it is available on PATH.")
        } else {
            switch viewModel.selectedSection {
            case .containers:
                containersContent
            case .volumes:
                ResourceListView(
                    resources: viewModel.snapshot.volumes,
                    systemImage: "externaldrive",
                    emptyTitle: "No volumes",
                    emptyDetail: "Create one with `container volume create <name>`."
                )
            case .networks:
                ResourceListView(
                    resources: viewModel.snapshot.networks,
                    systemImage: "network",
                    emptyTitle: "No networks",
                    emptyDetail: "Networks created by Apple container will appear here."
                )
            }
        }
    }

    @ViewBuilder
    private var containersContent: some View {
        if let error = viewModel.snapshot.errorMessage, viewModel.snapshot.containers.isEmpty {
            EmptyStateView(title: "Unable to read containers", detail: error)
        } else if viewModel.snapshot.containers.isEmpty {
            EmptyStateView(title: "No containers", detail: "Apple container is installed and reachable.")
        } else {
            HStack(spacing: 0) {
                containerList
                    .frame(width: 310)
                Divider()
                ContainerDetailView(
                    container: viewModel.selectedContainer,
                    stats: viewModel.selectedContainer.flatMap { viewModel.snapshot.statsByID[$0.id] }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sectionLabel(for section: DashboardSection) -> String {
        "\(section.title) (\(count(for: section)))"
    }

    private func count(for section: DashboardSection) -> Int {
        switch section {
        case .containers: return viewModel.snapshot.containers.count
        case .volumes: return viewModel.snapshot.volumes.count
        case .networks: return viewModel.snapshot.networks.count
        }
    }

    private var containerList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(viewModel.snapshot.containers) { container in
                    ContainerRowView(
                        container: container,
                        stats: viewModel.snapshot.statsByID[container.id],
                        selected: viewModel.selectedContainerID == container.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.select(containerID: container.id)
                    }
                }
            }
            .padding(10)
        }
    }

    private var statusLine: String {
        if let version = viewModel.snapshot.system.version, !version.isEmpty {
            return version
        }
        if let message = viewModel.snapshot.system.message {
            return message
        }
        return viewModel.snapshot.system.serviceRunning ? "system running" : "system unavailable"
    }
}

private struct MetricBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .frame(width: 76, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
