<img src="assets/ChromeSweep.png" width="96" alt="Logo Chrome Sweep">

# Chrome Sweep

Chrome Sweep là tiện ích Windows để dọn cache Google Chrome và Microsoft Edge theo từng hồ sơ, đồng thời dọn file tạm cũ của Windows.

**Tác giả** · Nguyễn Công Thức ([@congthuc007](https://github.com/congthuc007))

**Giấy phép mã nguồn** · [MIT](LICENSE)

## Tải và chạy

Tải [ChromeSweep.exe](https://github.com/congthuc007/ChromeSweep/releases/latest/download/ChromeSweep.exe) từ [bản phát hành mới nhất](https://github.com/congthuc007/ChromeSweep/releases/latest), rồi bấm đúp để mở. EXE chứa sẵn giao diện, script dọn và icon. Máy cần Windows PowerShell 5.1 và .NET Framework 4.x.

## Chức năng

| Chức năng | Cách hoạt động |
| --- | --- |
| **Quét hồ sơ Chrome và Edge** | Chọn trình duyệt để xem tên, thư mục và dung lượng cache của từng hồ sơ. Khi đổi trình duyệt, ứng dụng quét lại và bỏ lựa chọn cũ. |
| **Chọn nhanh** | Tích từng hồ sơ, dùng **Ctrl+A** để chọn mọi hồ sơ có cache hoặc **Ctrl+Shift+A** để bỏ chọn. Giao diện hiển thị tổng dung lượng cache đang được chọn. |
| **Quét lại** | Cập nhật danh sách hồ sơ và dung lượng cache của trình duyệt đang chọn. |
| **Tắt hết Chrome hoặc Edge** | Sau khi xác nhận, ứng dụng thử đóng cửa sổ bình thường, rồi buộc tắt các tiến trình còn chạy của trình duyệt đã chọn trong phiên Windows hiện tại. |
| **Xóa cache đã chọn** | Dọn ba thư mục cache của các hồ sơ đã tích, báo dung lượng file đã dọn và tự quét lại. |
| **Dọn file tạm Windows** | Quét hai thư mục Temp, xóa các file đủ điều kiện rồi báo số file, dung lượng và số mục bị bỏ qua. Có thể dùng khi trình duyệt đang mở. |

## Cách dọn

### Cache Chrome và Edge

1. Chọn **Chrome** hoặc **Edge** và tích các hồ sơ cần dọn.
2. Thoát trình duyệt đã chọn. Nếu trình duyệt vẫn chạy nền, lưu nội dung đang nhập và hoàn tất các lượt tải xuống trước khi dùng **Tắt hết Chrome** hoặc **Tắt hết Edge**.
3. Bấm **Xóa cache đã chọn**. Sau khi dọn, danh sách sẽ hiển thị dung lượng mới.

Ứng dụng chỉ quét hồ sơ `Default` và `Profile N` trong thư mục dữ liệu mặc định của trình duyệt. Trong các hồ sơ được chọn, ứng dụng chỉ dọn `Cache`, `Code Cache` và `GPUCache`. Cookie, phiên đăng nhập, lịch sử, dấu trang, mật khẩu, thông tin tự động điền, extension và dữ liệu lưu của website nằm ngoài phạm vi dọn.

### File tạm Windows

Bấm **Dọn file tạm** để quét `%LOCALAPPDATA%\Temp` và `%WINDIR%\Temp`. Chỉ file có cả ngày tạo lẫn ngày sửa cũ hơn 7 ngày mới đủ điều kiện. File đang khóa, mục thiếu quyền và đường dẫn liên kết được bỏ qua.

## Mã nguồn

| Đường dẫn | Vai trò |
| --- | --- |
| [`src/Launcher.cs`](src/Launcher.cs) | Mở ứng dụng và nạp tài nguyên nhúng trong EXE. |
| [`src/ChromeCacheCleaner.GUI.ps1`](src/ChromeCacheCleaner.GUI.ps1) | Giao diện Windows Forms. |
| [`src/ChromeCacheCleaner.ps1`](src/ChromeCacheCleaner.ps1) | Quét hồ sơ, dọn dữ liệu và quản lý tiến trình trình duyệt. |
| [`src/ChromeCacheCleaner.cmd`](src/ChromeCacheCleaner.cmd) | Mở giao diện trực tiếp từ mã nguồn. |
| [`assets/`](assets/) | Logo PNG gốc và icon ICO với 10 kích thước từ 16 đến 256 px. |
| [`build.ps1`](build.ps1) | Đóng gói script và icon thành EXE. |

## Build lại

Mở PowerShell trong thư mục dự án và chạy lệnh sau:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

Script dùng trình biên dịch C# của .NET Framework 4.x và tạo `Chrome Sweep.exe` trong thư mục dự án.

## Giấy phép

Mã nguồn và tài liệu sử dụng [giấy phép MIT](LICENSE). Bản quyền © 2026 Nguyễn Công Thức.
