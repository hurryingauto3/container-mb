// SPDX-License-Identifier: Apache-2.0

import ContainerCore
import Darwin
import Foundation

@main
enum SmokeTests {
    static func main() async {
        var suite = TestSuite()

        await suite.run("parses managed container shape") {
            try testParsesManagedContainerShape()
        }
        await suite.run("parses stats with missing fields") {
            try testParsesStatsWithMissingFields()
        }
        await suite.run("parses system status table") {
            try testParsesSystemStatusTable()
        }
        await suite.run("app version is well-formed semver") {
            try testAppVersionIsWellFormed()
        }
        await suite.run("parses live container address shape") {
            try testParsesLiveContainerAddressShape()
        }
        await suite.run("parses live network and volume detail") {
            try testParsesLiveResourceDetail()
        }
        await suite.run("background refresh skips unchanged stats") {
            try await testBackgroundRefreshSkipsStatsWhenUnchanged()
        }
        await suite.run("refresh computes CPU percent") {
            try await testRefreshComputesCPUPercent()
        }

        suite.finish()
    }
}

private struct TestSuite {
    private var failures: [String] = []

    mutating func run(_ name: String, body: () async throws -> Void) async {
        do {
            try await body()
            print("PASS \(name)")
        } catch {
            failures.append("\(name): \(error)")
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("All smoke tests passed")
            exit(0)
        }

        print("\nFailures:")
        for failure in failures {
            print("- \(failure)")
        }
        exit(1)
    }
}

private struct ExpectationFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw ExpectationFailure(message: message)
    }
}

private func testParsesManagedContainerShape() throws {
    let data = Data(
        """
        [
          {
            "id": "abcdef1234567890",
            "configuration": {
              "id": "abcdef1234567890",
              "image": { "reference": "postgres:14.10" },
              "publishedPorts": [
                {
                  "hostAddress": "127.0.0.1",
                  "hostPort": 5437,
                  "containerPort": 5432,
                  "proto": "tcp",
                  "count": 1
                }
              ],
              "labels": { "project": "policy" },
              "networks": [{ "network": "tg-policy-service" }],
              "mounts": [
                {
                  "source": "/tmp/postgres",
                  "destination": "/var/lib/postgresql/data",
                  "readOnly": false
                }
              ],
              "initProcess": {
                "executable": "/usr/local/bin/postgres",
                "arguments": ["-D", "/data"]
              },
              "resources": {
                "cpus": 2,
                "memoryInBytes": 2147483648,
                "storage": 10737418240
              },
              "creationDate": "2026-06-23T10:00:00Z"
            },
            "status": {
              "state": "running",
              "networks": [{ "address": "192.168.64.10" }],
              "startedDate": "2026-06-23T10:01:00Z"
            }
          }
        ]
        """.utf8
    )

    let containers = try ContainerJSONMapper.containers(from: data)

    try expect(containers.count == 1, "expected one container")
    try expect(containers[0].id == "abcdef1234567890", "id mismatch")
    try expect(containers[0].shortID == "abcdef123456", "short id mismatch")
    try expect(containers[0].image == "postgres:14.10", "image mismatch")
    try expect(containers[0].state == .running, "state mismatch")
    try expect(containers[0].ports.first?.mappingDisplay == "127.0.0.1:5437 -> 5432/tcp", "port mismatch")
    try expect(containers[0].labels["project"] == "policy", "label mismatch")
    try expect(containers[0].networks == ["tg-policy-service"], "network mismatch")
    try expect(containers[0].ipAddresses == ["192.168.64.10"], "ip mismatch")
    try expect(containers[0].mounts == ["/tmp/postgres -> /var/lib/postgresql/data"], "mount mismatch")
    try expect(containers[0].command == "/usr/local/bin/postgres -D /data", "command mismatch")
    try expect(containers[0].resources.cpus == 2, "cpu limit mismatch")
    try expect(containers[0].resources.memoryBytes == 2147483648, "memory limit mismatch")
}

private func testParsesStatsWithMissingFields() throws {
    let data = Data(
        """
        [
          {
            "id": "abcdef1234567890",
            "memoryUsageBytes": 1024,
            "cpuUsageUsec": 2000000,
            "networkRxBytes": 512,
            "numProcesses": 7
          }
        ]
        """.utf8
    )

    let stats = try ContainerJSONMapper.stats(from: data)

    try expect(stats.count == 1, "expected one stats row")
    try expect(stats[0].id == "abcdef1234567890", "stats id mismatch")
    try expect(stats[0].memoryUsageBytes == 1024, "memory mismatch")
    try expect(stats[0].memoryLimitBytes == nil, "memory limit should be nil")
    try expect(stats[0].cpuUsageUsec == 2000000, "cpu mismatch")
    try expect(stats[0].cpuPercent == nil, "cpu percent should be nil")
    try expect(stats[0].networkRxBytes == 512, "network rx mismatch")
    try expect(stats[0].processCount == 7, "process count mismatch")
}

private func testParsesSystemStatusTable() throws {
    let state = ContainerJSONMapper.systemState(
        fromStatusOutput: """
        FIELD              VALUE
        status             running
        apiServer.version  1.0.0
        """,
        version: "container CLI version 1.0.0"
    )

    try expect(state.installed, "system should be installed")
    try expect(state.serviceRunning, "system should be running")
    try expect(state.version == "container CLI version 1.0.0", "version mismatch")
}

// The packaging script parses AppVersion.marketing into the bundle's CFBundleShortVersionString,
// which Info.plist requires to be a dotted numeric string; guard the format so a release can't
// silently produce an invalid Info.plist.
private func testAppVersionIsWellFormed() throws {
    let components = AppVersion.marketing.split(separator: ".", omittingEmptySubsequences: false)
    try expect(components.count == 3, "marketing version must be MAJOR.MINOR.PATCH: \(AppVersion.marketing)")
    try expect(
        components.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) },
        "each version component must be a non-empty number: \(AppVersion.marketing)"
    )
    try expect(AppVersion.current == "v\(AppVersion.marketing)", "current must prefix marketing with 'v'")
}

// Regression: the live `container list` JSON puts addresses under status.networks[].ipv4Address
// in CIDR form, which the mapper previously ignored (it only matched ipAddress/address/ip).
private func testParsesLiveContainerAddressShape() throws {
    let data = Data(
        """
        [
          {
            "configuration": {
              "id": "web",
              "image": { "reference": "docker.io/library/nginx:alpine" },
              "publishedPorts": [
                { "containerPort": 80, "count": 1, "hostAddress": "0.0.0.0", "hostPort": 8080, "proto": "tcp" }
              ],
              "networks": [{ "network": "default", "options": { "hostname": "web", "mtu": 1280 } }]
            },
            "id": "web",
            "status": {
              "networks": [
                {
                  "hostname": "web",
                  "ipv4Address": "192.168.64.2/24",
                  "ipv4Gateway": "192.168.64.1",
                  "ipv6Address": "fd37:5540:3aa9:5b60:f442:99ff:fe4e:7281/64",
                  "macAddress": "f6:42:99:4e:72:81",
                  "network": "default"
                }
              ],
              "startedDate": "2026-06-24T01:58:23Z",
              "state": "running"
            }
          }
        ]
        """.utf8
    )

    let containers = try ContainerJSONMapper.containers(from: data)

    try expect(containers.count == 1, "expected one container")
    try expect(containers[0].image == "docker.io/library/nginx:alpine", "image mismatch")
    try expect(containers[0].ports.first?.mappingDisplay == "localhost:8080 -> 80/tcp", "port mismatch")
    try expect(
        containers[0].ipAddresses == [
            "192.168.64.2",
            "fd37:5540:3aa9:5b60:f442:99ff:fe4e:7281",
        ],
        "ip mismatch: \(containers[0].ipAddresses)"
    )
}

// Regression: live `network list` reports the subnet under status.ipv4Subnet, and `volume list`
// reports source/driver under configuration; the mapper previously only read top-level keys.
private func testParsesLiveResourceDetail() throws {
    let networkData = Data(
        """
        [
          {
            "configuration": { "mode": "nat", "name": "default", "plugin": "container-network-vmnet" },
            "id": "default",
            "status": { "ipv4Gateway": "192.168.64.1", "ipv4Subnet": "192.168.64.0/24" }
          }
        ]
        """.utf8
    )

    let networks = try ContainerJSONMapper.resources(from: networkData)
    try expect(networks.count == 1, "expected one network")
    try expect(networks[0].id == "default", "network id mismatch")
    try expect(networks[0].name == "default", "network name mismatch")
    try expect(networks[0].detail == "192.168.64.0/24", "network detail mismatch: \(networks[0].detail ?? "nil")")
    try expect(
        networks[0].attributes == [
            ResourceAttribute(label: "Mode", value: "nat"),
            ResourceAttribute(label: "Subnet", value: "192.168.64.0/24"),
            ResourceAttribute(label: "Gateway", value: "192.168.64.1"),
            ResourceAttribute(label: "Plugin", value: "container-network-vmnet"),
        ],
        "network attributes mismatch: \(networks[0].attributes)"
    )

    let volumeData = Data(
        """
        [
          {
            "configuration": {
              "driver": "local",
              "format": "ext4",
              "name": "testvol",
              "sizeInBytes": 549755813888,
              "source": "/Users/me/Library/Application Support/com.apple.container/volumes/testvol/volume.img"
            },
            "id": "testvol"
          }
        ]
        """.utf8
    )

    let volumes = try ContainerJSONMapper.resources(from: volumeData)
    try expect(volumes.count == 1, "expected one volume")
    try expect(volumes[0].id == "testvol", "volume id mismatch")
    try expect(volumes[0].name == "testvol", "volume name mismatch")
    try expect(
        volumes[0].detail == "/Users/me/Library/Application Support/com.apple.container/volumes/testvol/volume.img",
        "volume detail mismatch: \(volumes[0].detail ?? "nil")"
    )
    try expect(
        volumes[0].attributes == [
            ResourceAttribute(label: "Driver", value: "local"),
            ResourceAttribute(label: "Format", value: "ext4"),
            ResourceAttribute(label: "Size", value: "512.0 GiB"),
            ResourceAttribute(label: "Source", value: "/Users/me/Library/Application Support/com.apple.container/volumes/testvol/volume.img"),
        ],
        "volume attributes mismatch: \(volumes[0].attributes)"
    )
}

private func testBackgroundRefreshSkipsStatsWhenUnchanged() async throws {
    let client = MockContainerCLIClient()
    let coordinator = PollingCoordinator(client: client)

    _ = await coordinator.refresh(mode: .background)
    var count = await client.statsCallCount()
    try expect(count == 1, "first background refresh should collect stats")

    _ = await coordinator.refresh(mode: .background)
    count = await client.statsCallCount()
    try expect(count == 1, "second unchanged background refresh should skip stats")

    _ = await coordinator.refresh(mode: .foreground)
    count = await client.statsCallCount()
    try expect(count == 2, "foreground refresh should collect stats")
}

private func testRefreshComputesCPUPercent() async throws {
    let client = MockContainerCLIClient()
    let coordinator = PollingCoordinator(client: client)

    _ = await coordinator.refresh(mode: .foreground)
    let snapshot = await coordinator.refresh(mode: .foreground)

    let cpuPercent = snapshot.statsByID["abcdef1234567890"]?.cpuPercent
    try expect(cpuPercent != nil, "cpu percent should be computed")
    try expect((cpuPercent ?? 0) > 0, "cpu percent should be greater than zero")
}

private actor MockContainerCLIClient: ContainerCLIClient {
    private var statsCalls = 0

    func listContainers() async throws -> [ContainerSummary] {
        [
            ContainerSummary(
                id: "abcdef1234567890",
                image: "postgres:14.10",
                state: .running,
                raw: .object(["id": .string("abcdef1234567890")])
            )
        ]
    }

    func stats() async throws -> [ContainerStatsSnapshot] {
        statsCalls += 1
        return [
            ContainerStatsSnapshot(
                id: "abcdef1234567890",
                memoryUsageBytes: 1024,
                memoryLimitBytes: 2048,
                cpuUsageUsec: UInt64(statsCalls * 1_000_000),
                processCount: 3
            )
        ]
    }

    func inspectContainers(ids: [String]) async throws -> [ContainerSummary] {
        try await listContainers().filter { ids.contains($0.id) }
    }

    func listNetworks() async throws -> [ResourceSummary] {
        [ResourceSummary(id: "default", name: "default", detail: "192.168.64.0/24")]
    }

    func listVolumes() async throws -> [ResourceSummary] {
        [ResourceSummary(id: "postgres", name: "postgres")]
    }

    func systemState() async -> ContainerSystemState {
        ContainerSystemState(installed: true, serviceRunning: true, version: "1.0.0")
    }

    func statsCallCount() -> Int {
        statsCalls
    }
}
