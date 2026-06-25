// SPDX-License-Identifier: Apache-2.0

import AppKit
import ContainerCore
import SwiftUI

struct ImageRowView: View {
    let image: ImageSummary
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                Text(image.repositoryTag)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(DisplayFormatters.bytes(image.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if image.platformDisplay != "--" {
                    Text(image.platformDisplay)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(image.shortDigest)
                    .font(.system(.caption2, design: .monospaced))
                Spacer()
                Text(DisplayFormatters.relativeDate(image.createdAt))
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

struct ImageDetailView: View {
    let image: ImageSummary?

    var body: some View {
        Group {
            if let image {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        title(image)
                        statsGrid(image)
                        listSection(title: "Entrypoint", values: image.entrypoint)
                        listSection(title: "Cmd", values: image.command)
                        listSection(title: "Exposed Ports", values: image.exposedPorts)
                        listSection(title: "Env", values: image.env)
                    }
                    .padding(14)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Select an image")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func title(_ image: ImageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(image.repositoryTag)
                .font(.system(.title3, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if let digest = image.digest {
                HStack(spacing: 6) {
                    Text(digest)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    CopyButton(title: "Copy", value: digest)
                }
            }
            HStack {
                CopyButton(title: "ID", value: image.id)
                CopyButton(title: "Inspect", value: "container image inspect \(image.repositoryTag)")
            }
        }
    }

    private func statsGrid(_ image: ImageSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                StatCell(title: "Size", value: DisplayFormatters.bytes(image.sizeBytes))
                StatCell(title: "Platform", value: image.platformDisplay)
            }
            GridRow {
                StatCell(title: "Created", value: DisplayFormatters.relativeDate(image.createdAt))
                StatCell(title: "Layers", value: image.layerCount.map(String.init) ?? "--")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
