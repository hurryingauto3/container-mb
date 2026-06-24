import AppKit
import ContainerCore
import SwiftUI

struct ContainerRowView: View {
    let container: ContainerSummary
    let stats: ContainerStatsSnapshot?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(container.state.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(container.shortID)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(container.state.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(container.image)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 10) {
                Label(DisplayFormatters.percent(stats?.cpuPercent), systemImage: "cpu")
                Label(DisplayFormatters.bytes(stats?.memoryUsageBytes), systemImage: "memorychip")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }
}

struct ContainerDetailView: View {
    let container: ContainerSummary?
    let stats: ContainerStatsSnapshot?

    var body: some View {
        Group {
            if let container {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        title(container)
                        statsGrid
                        portSection(container)
                        commandSection(container)
                        resourceSection(container)
                        listSection(title: "Networks", values: container.networks)
                        listSection(title: "IP Addresses", values: container.ipAddresses)
                        listSection(title: "Mounts", values: container.mounts)
                        labelsSection(container)
                    }
                    .padding(14)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Select a container")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func title(_ container: ContainerSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(container.shortID)
                    .font(.system(.title3, design: .monospaced))
                Spacer()
                Text(container.state.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(container.state.isRunning ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(container.image)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack {
                CopyButton(title: "ID", value: container.id)
                CopyButton(title: "Logs", value: "container logs \(container.id)")
                CopyButton(title: "Inspect", value: "container inspect \(container.id)")
            }
        }
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                StatCell(title: "CPU", value: DisplayFormatters.percent(stats?.cpuPercent))
                StatCell(title: "Memory", value: memoryDisplay)
            }
            GridRow {
                StatCell(title: "Network", value: networkDisplay)
                StatCell(title: "Block I/O", value: blockDisplay)
            }
            GridRow {
                StatCell(title: "Processes", value: stats?.processCount.map(String.init) ?? "--")
                StatCell(title: "CPU usec", value: stats?.cpuUsageUsec.map(String.init) ?? "--")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func portSection(_ container: ContainerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ports")
            if container.ports.isEmpty {
                Text("--")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(container.ports) { port in
                    HStack {
                        Text(port.mappingDisplay)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        CopyButton(title: "Copy", value: port.hostDisplay)
                    }
                }
            }
        }
    }

    private func commandSection(_ container: ContainerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Command")
            Text(DisplayFormatters.command(container.command))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private func resourceSection(_ container: ContainerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Limits")
            HStack(spacing: 14) {
                Text("CPU \(container.resources.cpus.map(String.init) ?? "--")")
                Text("Memory \(DisplayFormatters.bytes(container.resources.memoryBytes))")
                Text("Storage \(DisplayFormatters.bytes(container.resources.storageBytes))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func listSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            if values.isEmpty {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func labelsSection(_ container: ContainerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Labels")
            if container.labels.isEmpty {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(container.labels.keys.sorted(), id: \.self) { key in
                    Text("\(key)=\(container.labels[key] ?? "")")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var memoryDisplay: String {
        "\(DisplayFormatters.bytes(stats?.memoryUsageBytes)) / \(DisplayFormatters.bytes(stats?.memoryLimitBytes))"
    }

    private var networkDisplay: String {
        "\(DisplayFormatters.bytes(stats?.networkRxBytes)) / \(DisplayFormatters.bytes(stats?.networkTxBytes))"
    }

    private var blockDisplay: String {
        "\(DisplayFormatters.bytes(stats?.blockReadBytes)) / \(DisplayFormatters.bytes(stats?.blockWriteBytes))"
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}

private struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CopyButton: View {
    let title: String
    let value: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Label(title, systemImage: "doc.on.doc")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .help(value)
    }
}

struct ResourceListView: View {
    let resources: [ResourceSummary]
    let systemImage: String
    let emptyTitle: String
    let emptyDetail: String

    var body: some View {
        if resources.isEmpty {
            EmptyStateView(title: emptyTitle, detail: emptyDetail)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(resources) { resource in
                        ResourceCardView(resource: resource, systemImage: systemImage)
                    }
                }
                .padding(14)
            }
        }
    }
}

private struct ResourceCardView: View {
    let resource: ResourceSummary
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(resource.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if resource.id != resource.name {
                    Text(resource.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            if !resource.attributes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(resource.attributes) { attribute in
                        HStack(alignment: .top, spacing: 8) {
                            Text(attribute.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(attribute.value)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else if let detail = resource.detail {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
