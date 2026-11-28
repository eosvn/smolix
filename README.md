# Smolix

Cuộn chuột mượt cho macOS: app nhỏ chạy trên thanh menu, thay thế Mos.

- Chỉ làm mượt **chuột có bánh xe**. Trackpad và Magic Mouse giữ nguyên.
- `Cmd`/`Ctrl` + cuộn (phóng to/thu nhỏ) được giữ nguyên như hệ thống gửi.
- `Shift` + cuộn → cuộn ngang mượt.
- Trong terminal (iTerm2, Terminal, Ghostty, Warp, WezTerm, Alacritty, kitty…) quãng cuộn được nhân với **Tốc độ trong Terminal**
  (mặc định 70%): iTerm2 + tmux biến mỗi vài pixel thành một lần cuộn nhiều dòng, nên cùng số pixel sẽ đi xa hơn hẳn trình duyệt.

## Tải về và cài đặt

Yêu cầu: macOS 14 trở lên, Mac chip Apple hoặc Intel.

**Cài bằng Homebrew:**

```sh
brew install --cask eosvn/tap/smolix
```

rồi làm tiếp từ bước 3 bên dưới.

**Hoặc cài bằng tay:**

1. Tải file **`Smolix-x.y.z.dmg`** mới nhất ở trang [Releases](https://github.com/eosvn/smolix/releases/latest).
2. Mở file `.dmg`, kéo **Smolix** vào thư mục **Applications**.
3. Mở Smolix từ Applications. macOS sẽ hỏi quyền **Trợ năng**: vào
   Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Trợ năng, bật Smolix.
   Sau tối đa 2 giây app tự hoạt động, không cần mở lại.
4. Biểu tượng con chuột trên thanh menu › **Cài đặt…** để chỉnh cảm giác cuộn và bật **Khởi động cùng máy**.

> Đang dùng Mos, SmoothScroll hay app cuộn mượt khác? Hãy tắt chúng (và gỡ khỏi Mục đăng nhập)
> để hai app không cùng xử lý cuộn chuột.

Cập nhật: từ bản 1.1.0, vào menu Smolix › **Kiểm tra cập nhật…** rồi bấm **Cài bản cập nhật**
(Smolix cũng tự kiểm tra mỗi ngày). Đang dùng 1.0.0 thì tải bản `.dmg` mới, kéo đè lên bản cũ một lần.
Quyền Trợ năng được giữ nguyên. Cài qua Homebrew cũng cập nhật trong app như vậy. Vì thế `brew upgrade`
bỏ qua Smolix, trừ khi chạy `brew upgrade --cask --greedy smolix`.

## Build từ mã nguồn

Cần Xcode hoặc Command Line Tools (Swift 6).

```sh
make install     # build, ký, chép vào /Applications/Smolix.app và mở
```

Các lệnh khác:

| Lệnh | Việc |
|---|---|
| `make app` | Chỉ build `build/Smolix.app` |
| `make dmg` | Build universal (Apple Silicon + Intel), đóng gói `build/Smolix-<version>.dmg`, ký và notarize nếu có Developer ID |
| `make release` | `make dmg` + tạo `appcast.xml` ký EdDSA cho bộ cập nhật trong app, đăng cả hai lên GitHub Release, cập nhật cask Homebrew |
| `make test` | Chạy unit test phần tính toán cuộn |
| `make logs` | Xem log trực tiếp (tap bị macOS tắt/bật lại, sự kiện bánh xe khi bật debug) |
| `make icon` | Vẽ lại icon app |

Bật log chi tiết từng nấc bánh xe (để tinh chỉnh):

```sh
defaults write dev.smolix.Smolix debugLogging -bool true   # rồi mở lại Smolix, chạy `make logs`
```

## Tùy chọn

| Tùy chọn | Ý nghĩa | Mặc định |
|---|---|---|
| Cuộn mượt | Công tắc đầu cửa sổ. Tắt thì chuột cuộn như mặc định của macOS | Bật |
| Đảo chiều cuộn chuột | Chỉ đảo chuột, không ảnh hưởng trackpad | Tắt |
| Tốc độ trong Terminal | Hệ số quãng cuộn khi con trỏ nằm trên cửa sổ terminal | 70% |
| Bước cuộn | Số pixel cho mỗi nấc bánh xe khi cuộn chậm | 52 px |
| Tăng tốc | Quay bánh xe nhanh thì mỗi nấc đi xa hơn (dựa trên gia tốc cuộn của macOS). 0 = mỗi nấc luôn đúng bằng bước cuộn | ×1.00 |
| Độ mượt | Thời gian để một lần cuộn đi được ~95% quãng đường | 320 ms |
| Trượt khi cuộn nhanh | Quay bánh xe nhanh thì thời gian trượt dài thêm tối đa bấy nhiêu %; cuộn chậm không đổi | +100% |
| Khởi động cùng máy | Dùng Mục đăng nhập của macOS | Tắt |
| Ẩn biểu tượng | Ẩn icon trên thanh menu; mở lại app từ Applications để vào cài đặt | Tắt |

## Thiết kế để không tự thoát

Mos 3.5.0 crash (SIGABRT) bên trong `SkyLight processEventTapData` với lỗi
"pointer being freed was not allocated", tức là lỗi quản lý bộ nhớ quanh event tap.
Smolix tránh loại lỗi đó như sau:

- Mọi thứ (event tap, hoạt ảnh, cài đặt) chạy trên **main thread**: không lock, không data race.
- Không bao giờ giữ lại `CGEvent` hay `CGEventTapProxy` sau khi callback trả về.
  Callback chỉ trả event gốc (cho qua) hoặc `nil` (nuốt). Cuộn mượt được phát bằng
  event **mới** qua `CGEvent.post(tap:)`, không dùng `tapPostEvent` với proxy cũ.
- Một bộ giám sát chạy mỗi 2 giây: tap bị macOS tắt thì bật lại, tap hỏng thì tạo lại,
  quyền Trợ năng bị thu hồi thì gỡ tap và chờ được cấp lại.
  Ngoài ra tap được tạo lại sau khi máy thức dậy hoặc chuyển phiên người dùng.
- Hoạt ảnh đồng bộ với tần số quét màn hình (`CADisplayLink`, 120 Hz trên ProMotion), dừng hẳn
  khi không cuộn nên không tốn pin.

## Cấu trúc

```
Sources/SmolixCore/   Tính toán thuần (quãng đường mỗi nấc, ease-out theo thời gian thực), có unit test
Sources/Smolix/       App: ScrollEngine (event tap + hoạt ảnh), menu bar, cửa sổ cài đặt SwiftUI, Updater (Sparkle)
App/                  Info.plist, AppIcon.icns
scripts/              build-app.sh, install.sh, make-dmg.sh, release.sh, setup-signing.sh, make-icon.swift
ReleaseNotes/         Ghi chú từng phiên bản (hiện trong cửa sổ cập nhật và trên GitHub Release)
```

### Ký code và phát hành

Script build tự chọn chứng chỉ:

1. **Developer ID Application** (Apple Developer Program) nếu có trong keychain. Đây là chứng chỉ dùng cho
   bản phát hành: `make dmg` sẽ ký, gửi Apple notarize và staple vé vào `.dmg`, nên máy nào mở cũng
   không bị Gatekeeper chặn. Cần thiết lập một lần:
   ```sh
   xcrun notarytool store-credentials smolix-notary --apple-id <apple-id> --team-id <TEAM_ID>
   ```
   (mật khẩu là app-specific password tạo ở account.apple.com).
2. Nếu không có, dùng chứng chỉ tự ký **"Smolix Local Signing"** (chỉ hợp để build cho chính máy mình).

### Đăng bản mới

App tự cập nhật bằng [Sparkle](https://sparkle-project.org): nó đọc
`https://github.com/eosvn/smolix/releases/latest/download/appcast.xml`, tức file `appcast.xml`
đính kèm ở release mới nhất.

1. Trong `App/Info.plist`: tăng `CFBundleShortVersionString` (ví dụ `1.2.0`) và **tăng `CFBundleVersion` thêm 1**.
   Sparkle so sánh bằng `CFBundleVersion`.
2. Viết `ReleaseNotes/<version>.md` (Markdown ngắn, hiện trong cửa sổ cập nhật).
3. Commit, push, rồi `make release`. Lệnh này build, notarize, tạo `appcast.xml` ký EdDSA, đăng release,
   rồi cập nhật version và sha256 trong cask Homebrew
   ([eosvn/homebrew-tap](https://github.com/eosvn/homebrew-tap), file `Casks/smolix.rb`).

`appcast.xml` được ký bằng khóa EdDSA trong keychain đăng nhập (account `smolix`). Public key nằm ở
`SUPublicEDKey` trong `Info.plist`. **Hãy sao lưu khóa này**: mất khóa thì không phát hành bản cập nhật
được nữa, người dùng phải tự tải về cài lại.

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account smolix -x smolix-sparkle-key.txt  # xuất khóa ra file, cất vào trình quản lý mật khẩu rồi xóa file
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account smolix -f smolix-sparkle-key.txt  # nạp lại trên máy khác
```

macOS gắn quyền Trợ năng với chữ ký của app. Build ký ad-hoc sẽ đổi danh tính sau mỗi lần build,
khiến quyền âm thầm mất tác dụng. `scripts/setup-signing.sh` (tự chạy ở lần build đầu) tạo một
chứng chỉ tự ký **"Smolix Local Signing"** trong keychain riêng `.signing/smolix.keychain-db`
(không đụng keychain đăng nhập), nên quyền được giữ qua các lần build lại.
Xóa thư mục `.signing/` thì lần build sau sẽ tạo chứng chỉ mới và phải cấp quyền lại.

## Giấy phép

[MIT](LICENSE)
