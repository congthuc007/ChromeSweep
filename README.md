# Chrome Sweep

Tiện ích Windows để dọn cache Google Chrome và Microsoft Edge theo từng hồ sơ và xóa file tạm cũ của hệ thống.

**Tác giả** · Nguyễn Công Thức  
**Giấy phép mã nguồn** · [MIT](LICENSE)

## Bắt đầu

Mở `Chrome Sweep.exe` rồi chọn **Chrome** hoặc **Edge** để xem hồ sơ và dung lượng cache có thể dọn. EXE đã chứa các thành phần cần thiết và chạy trên Windows có Windows PowerShell 5.1 và .NET Framework 4.x.

### Dọn cache trình duyệt

1. Tích các hồ sơ muốn dọn. Nhấn **Ctrl+A** để chọn mọi hồ sơ có cache hoặc **Ctrl+Shift+A** để bỏ chọn.
2. Thoát trình duyệt đã chọn. Nếu trình duyệt còn chạy nền, bấm **Tắt hết Chrome** hoặc **Tắt hết Edge** và xác nhận. Lưu nội dung đang nhập và hoàn tất các lượt tải xuống trước khi dùng nút này. Ứng dụng thử đóng cửa sổ bình thường rồi buộc tắt tiến trình còn lại trong phiên Windows hiện tại.
3. Bấm **Xóa cache đã chọn**. Ứng dụng sẽ quét lại sau khi dọn.

Ứng dụng dọn `Cache`, `Code Cache` và `GPUCache` của các hồ sơ đã chọn trong thư mục dữ liệu mặc định của trình duyệt đã chọn. Thao tác này giữ lại cookie, dữ liệu đăng nhập, lịch sử, dấu trang, mật khẩu, thông tin tự động điền và extension.

### Dọn file tạm Windows

Bấm **Dọn file tạm** để quét `%LOCALAPPDATA%\Temp` và `%WINDIR%\Temp`. Chỉ các file có cả ngày tạo và ngày sửa cũ hơn 7 ngày mới đủ điều kiện. Ứng dụng bỏ qua file bị khóa, mục thiếu quyền và liên kết thư mục. Có thể chạy thao tác này khi trình duyệt đang mở.

## Mã nguồn

| Thành phần | Vai trò |
| --- | --- |
| `src/Launcher.cs` | Mở ứng dụng và nạp các tài nguyên nhúng trong EXE. |
| `src/ChromeCacheCleaner.GUI.ps1` | Giao diện Windows Forms. |
| `src/ChromeCacheCleaner.ps1` | Quét hồ sơ và thực hiện các thao tác dọn. |
| `src/ChromeCacheCleaner.cmd` | Mở giao diện trực tiếp từ mã nguồn. |
| `assets/` | Ảnh PNG gốc và icon ICO có 10 kích thước từ 16 đến 256 px. |
| `build.ps1` | Đóng gói script và icon thành EXE. |

## Build lại

Mở PowerShell trong thư mục dự án và chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

Script sử dụng trình biên dịch C# đi kèm .NET Framework 4.x và tạo `Chrome Sweep.exe` trong thư mục dự án.

## Giấy phép

Mã nguồn và tài liệu được cấp phép theo [MIT](LICENSE). Giấy phép này không cấp quyền sử dụng nhãn hiệu Google Chrome.
