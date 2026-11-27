import AppKit
import SmolixCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let engine: ScrollEngine
    private var window: NSWindow?

    init(settings: AppSettings, engine: ScrollEngine) {
        self.settings = settings
        self.engine = engine
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, engine: engine))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Smolix"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: ScrollEngine

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            statusSection
            feelSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 500, height: Self.height)
        .onAppear(perform: refreshLoginState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginState()
            engine.healthCheck()
        }
    }

    /// Fits every section; the occasional hint row (permission, login approval) scrolls a little.
    private static let height: CGFloat = 662

    // MARK: Sections

    /// Status and the master switch in one row.
    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cuộn mượt")
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if engine.state == .needsPermission {
                    Button("Mở Cài đặt Trợ năng") { Accessibility.openSystemSettings() }
                } else {
                    Toggle("Bật cuộn mượt", isOn: $settings.smoothEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            if engine.state == .needsPermission {
                Text("Vào Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Trợ năng, bật Smolix. App sẽ tự hoạt động ngay khi được cấp quyền.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feelSection: some View {
        Section {
            sliderRow(
                title: "Bước cuộn",
                caption: "Quãng cuộn mỗi nấc bánh xe",
                value: $settings.step,
                range: ScrollParameters.stepRange,
                step: 1,
                format: { "\(Int($0.rounded())) px" }
            )
            sliderRow(
                title: "Tăng tốc",
                caption: "Quay nhanh tay thì đi xa hơn",
                value: $settings.acceleration,
                range: ScrollParameters.accelerationRange,
                step: 0.05,
                format: { $0 < 0.01 ? "Tắt" : String(format: "×%.2f", $0) }
            )
            sliderRow(
                title: "Độ mượt",
                caption: "Thời gian trượt mỗi lần cuộn",
                value: $settings.durationMs,
                range: ScrollParameters.durationRange,
                step: 10,
                format: { "\(Int($0.rounded())) ms" }
            )
            sliderRow(
                title: "Trượt khi cuộn nhanh",
                caption: "Quay nhanh thì trang trôi lâu hơn",
                value: $settings.glide,
                range: ScrollParameters.glideRange,
                step: 0.1,
                format: { $0 < 0.05 ? "Tắt" : "+\(Int(($0 * 100).rounded()))%" }
            )
            sliderRow(
                title: "Tốc độ trong Terminal",
                caption: "Terminal và tmux vốn cuộn xa hơn",
                value: $settings.terminalSpeed,
                range: AppSettings.terminalSpeedRange,
                step: 0.05,
                format: { "\(Int(($0 * 100).rounded()))%" }
            )
        } header: {
            Text("Cảm giác cuộn")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text("Chỉ áp dụng cho chuột có bánh xe. Trackpad và Magic Mouse giữ nguyên.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("Khôi phục mặc định") { settings.resetScrollFeel() }
                    .controlSize(.small)
            }
        }
        .disabled(!settings.smoothEnabled)
    }

    private var generalSection: some View {
        Section("Chung") {
            Toggle("Đảo chiều cuộn chuột", isOn: $settings.reverseEnabled)

            Toggle("Khởi động cùng máy", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            if loginNeedsApproval {
                HStack {
                    Text("Cần cho phép Smolix trong Cài đặt hệ thống › Mục đăng nhập.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Mở") { LoginItem.openSystemSettings() }
                        .controlSize(.small)
                }
            }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle(isOn: $settings.hideMenuBarIcon) {
                Text("Ẩn biểu tượng trên thanh menu")
                if settings.hideMenuBarIcon {
                    Text("Mở lại Smolix từ thư mục Applications để vào cửa sổ này.")
                }
            }
        }
    }

    /// One line per setting: name and a short hint on the left, slider and value on the right.
    private func sliderRow(
        title: String,
        caption: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                // Snap by rounding instead of `Slider(step:)`, which draws a dense row of tick marks.
                Slider(
                    value: Binding(
                        get: { value.wrappedValue },
                        set: { value.wrappedValue = ($0 / step).rounded() * step }
                    ),
                    in: range
                )
                .labelsHidden()
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
            .frame(width: 220)
        } label: {
            Text(title)
            Text(caption)
        }
    }

    // MARK: Status / login helpers

    private var statusText: String {
        switch engine.state {
        case .running: settings.smoothEnabled ? "Đang hoạt động" : "Đang tắt, chuột cuộn như mặc định của macOS"
        case .needsPermission: "Cần quyền Trợ năng"
        case .failed: "Không chặn được cuộn chuột, đang thử lại…"
        case .starting: "Đang khởi động…"
        }
    }

    private var statusColor: Color {
        switch engine.state {
        case .running: settings.smoothEnabled ? .green : .gray
        case .needsPermission: .orange
        case .failed: .red
        case .starting: .gray
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Không đổi được: \(error.localizedDescription)"
        }
        refreshLoginState()
    }

    private func refreshLoginState() {
        launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
        loginNeedsApproval = LoginItem.needsApproval
    }
}
