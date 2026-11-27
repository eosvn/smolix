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
        HStack(alignment: .top, spacing: 0) {
            Form {
                statusSection
                generalSection
                feelSection
            }
            .formStyle(.grouped)
            .frame(width: 420)

            Divider()

            TestScrollArea()
                .frame(width: 230)
        }
        .frame(height: 780)
        .onAppear(perform: refreshLoginState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginState()
            engine.healthCheck()
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(statusText)
                Spacer()
                if engine.state == .needsPermission {
                    Button("Mở Cài đặt Trợ năng") { Accessibility.openSystemSettings() }
                }
            }
            if engine.state == .needsPermission {
                Text("Vào Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Trợ năng, bật Smolix. App sẽ tự hoạt động ngay khi được cấp quyền.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generalSection: some View {
        Section("Chung") {
            Toggle("Bật cuộn mượt", isOn: $settings.smoothEnabled)
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

            Toggle("Ẩn biểu tượng trên thanh menu", isOn: $settings.hideMenuBarIcon)
            if settings.hideMenuBarIcon {
                Text("Mở lại Smolix từ thư mục Applications để quay lại cửa sổ này.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feelSection: some View {
        Section {
            sliderRow(
                title: "Bước cuộn",
                caption: "Khoảng cách cho mỗi nấc bánh xe",
                value: $settings.step,
                range: ScrollParameters.stepRange,
                step: 1,
                format: { "\(Int($0.rounded())) px" }
            )
            sliderRow(
                title: "Tăng tốc",
                caption: "Cuộn nhanh tay thì đi xa hơn",
                value: $settings.acceleration,
                range: ScrollParameters.accelerationRange,
                step: 0.05,
                format: { $0 < 0.01 ? "Tắt" : String(format: "×%.2f", $0) }
            )
            sliderRow(
                title: "Độ mượt",
                caption: "Thời gian trượt cho mỗi lần cuộn",
                value: $settings.durationMs,
                range: ScrollParameters.durationRange,
                step: 10,
                format: { "\(Int($0.rounded())) ms" }
            )
            sliderRow(
                title: "Trượt khi cuộn nhanh",
                caption: "Quay nhanh tay thì trang trôi lâu hơn, cuộn chậm không đổi",
                value: $settings.glide,
                range: ScrollParameters.glideRange,
                step: 0.1,
                format: { $0 < 0.05 ? "Tắt" : "+\(Int(($0 * 100).rounded()))%" }
            )
            sliderRow(
                title: "Tốc độ trong Terminal",
                caption: "So với các app khác. iTerm2, Terminal, Ghostty… (nhất là có tmux) tự nhân quãng cuộn lên",
                value: $settings.terminalSpeed,
                range: AppSettings.terminalSpeedRange,
                step: 0.05,
                format: { "\(Int(($0 * 100).rounded()))%" }
            )
            HStack {
                Spacer()
                Button("Khôi phục mặc định") { settings.resetScrollFeel() }
            }
        } header: {
            Text("Cảm giác cuộn")
        } footer: {
            Text("Thay đổi có hiệu lực ngay, cuộn thử ở khung bên phải. Chỉ áp dụng cho chuột có bánh xe; trackpad và Magic Mouse giữ nguyên.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!settings.smoothEnabled)
    }

    private func sliderRow(
        title: String,
        caption: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // Snap by rounding instead of `Slider(step:)`, which draws a dense row of tick marks.
            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = ($0 / step).rounded() * step }
                ),
                in: range
            )
            .labelsHidden()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Status / login helpers

    private var statusText: String {
        switch engine.state {
        case .running: settings.smoothEnabled ? "Đang hoạt động" : "Đang tạm tắt cuộn mượt"
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

/// A long list to try the scroll feel right inside the settings window.
private struct TestScrollArea: View {
    private let lines: [String] = (1...120).map { i in
        switch i % 6 {
        case 0: "\(i). Cuộn thử để cảm nhận độ mượt"
        case 1: "\(i). Bánh xe chuột, từng nấc một"
        case 2: "\(i). Quay nhanh tay để thử tăng tốc"
        case 3: "\(i). Đổi chiều giữa chừng"
        case 4: "\(i). Giữ Shift để cuộn ngang"
        default: "\(i). Smolix"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Thử cuộn ở đây")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.body, design: .rounded))
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .frame(minWidth: 380, alignment: .leading)
                            .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : .clear)
                    }
                }
            }
        }
    }
}
