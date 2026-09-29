import SwiftUI

@main
struct SensorDashboardApp: App {
    @StateObject private var sensor = SensorManager()
    var body: some Scene {
        WindowGroup { SensorView().environmentObject(sensor).tint(Color("AccentColor")) }
    }
}
struct SensorView: View {
    @EnvironmentObject private var sensor: SensorManager
    @Environment(\.scenePhase) private var phase
    @State private var export: ExportFile?
    var body: some View {
        NavigationView {
            List {
                Section {
                    Label(
                        sensor.status,
                        systemImage: sensor.demo
                            ? "play.rectangle" : "antenna.radiowaves.left.and.right"
                    ).font(.subheadline)
                    if sensor.scanning || sensor.connecting { ProgressView() }
                    if sensor.connected || sensor.connecting || sensor.demo {
                        Button(sensor.demo ? "Stop demo" : "Disconnect", role: .destructive) {
                            sensor.disconnect()
                        }
                    } else {
                        Button(sensor.scanning ? "Stop scan" : "Scan for sensors") {
                            if sensor.scanning { sensor.stopScan() } else { sensor.scan() }
                        }
                        Button("Explore demo readings") { sensor.startDemo() }
                    }
                } footer: {
                    Text(
                        "Heart Rate service (180D) · foreground sessions only. Starting a session replaces the previous readings. Export first to keep them."
                    )
                }
                if !sensor.samples.isEmpty {
                    Section(sensor.deviceName ?? "Current session") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(sensor.latest.map { "\($0.beatsPerMinute)" } ?? "—").font(
                                .system(size: 56, weight: .medium, design: .rounded)
                            ).monospacedDigit()
                            Text("bpm").foregroundColor(.secondary)
                            Spacer()
                            if sensor.sessionIsDemo {
                                Text("DEMO").font(.caption.bold()).padding(8).background(
                                    Color.accentColor.opacity(0.12)
                                ).cornerRadius(8)
                            }
                        }.accessibilityElement(children: .combine)
                        PulseChart(samples: Array(sensor.samples.suffix(60))).frame(height: 130)
                        HStack {
                            Text("Last \(min(60, sensor.samples.count)) readings")
                            Spacer()
                            Text("\(sensor.samples.count) in session")
                        }.font(.caption).foregroundColor(.secondary)
                        if let contact = sensor.latest?.contactDetected {
                            Label(
                                contact ? "Skin contact detected" : "No skin contact",
                                systemImage: contact ? "checkmark.circle" : "exclamationmark.circle"
                            )
                        }
                        if let battery = sensor.battery {
                            LabeledValue(label: "Battery", value: "\(battery)%")
                        }
                        if let energy = sensor.latest?.energyExpended {
                            LabeledValue(label: "Sensor energy counter", value: "\(energy) kJ")
                        }
                        if let intervals = sensor.latest?.rrIntervals, !intervals.isEmpty {
                            LabeledValue(
                                label: "Latest RR interval",
                                value: String(format: "%.0f ms", intervals.last! * 1000))
                        }
                        Button("Export session CSV") {
                            do { export = ExportFile(url: try sensor.export()) } catch {
                                sensor.error = error.localizedDescription
                            }
                        }
                    }
                }
                if !sensor.devices.isEmpty && !sensor.connected && !sensor.connecting
                    && !sensor.demo
                {
                    Section("Nearby sensors") {
                        ForEach(sensor.devices) { device in
                            Button {
                                sensor.connect(device)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name).foregroundColor(.primary)
                                        Text(
                                            device.rssi.map { "\($0) dBm" } ?? "Signal unavailable"
                                        ).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
                Section("About this dashboard") {
                    Text(
                        "Works with Bluetooth LE sensors advertising the standard Heart Rate service. Battery and RR intervals appear only when supplied by the sensor."
                    ).foregroundColor(.secondary)
                    Text(
                        "A development tool, not a medical device. Readings stay in memory and are cleared when the app closes."
                    ).font(.caption).foregroundColor(.secondary)
                }
            }.navigationTitle("Sensor Dashboard")
        }.navigationViewStyle(.stack)
            .onChange(of: phase) { if $0 == .background { sensor.pauseForBackground() } }
            .onAppear {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--demo"), sensor.samples.isEmpty
                    {
                        sensor.startDemo()
                    }
                #endif
            }
            .sheet(item: $export) { ActivitySheet(items: [$0.url]) }
            .alert(
                "Sensor",
                isPresented: Binding(
                    get: { sensor.error != nil }, set: { if !$0 { sensor.error = nil } })
            ) {
                Button("OK") { sensor.error = nil }
            } message: {
                Text(sensor.error ?? "")
            }
    }
}
struct LabeledValue: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary).monospacedDigit()
        }
    }
}
struct PulseChart: View {
    let samples: [SensorSample]
    var body: some View {
        let values = samples.map { Double($0.bpm) }
        let lower = max(0, (values.min() ?? 60) - 5)
        let upper = (values.max() ?? 100) + 5
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(upper)) bpm").font(.caption2).foregroundColor(.secondary)
            GeometryReader { proxy in
                Path { path in
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(
                            x: proxy.size.width * Double(index) / Double(max(1, values.count - 1)),
                            y: proxy.size.height * (1 - (value - lower) / (upper - lower)))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            Text("\(Int(lower)) bpm").font(.caption2).foregroundColor(.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel(
            "Heart-rate chart, \(values.count) readings, minimum \(Int(values.min() ?? 0)), maximum \(Int(values.max() ?? 0)) beats per minute"
        )
    }
}
struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
