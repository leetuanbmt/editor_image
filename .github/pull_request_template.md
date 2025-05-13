## Checklist Review Code

### Cache và Bộ nhớ

- [ ] Đã xác minh cache hình ảnh được giải phóng
- [ ] Đã giới hạn kích thước ImageCache (maximumSize, maximumSizeBytes)
- [ ] Đã đóng tất cả StreamControllers sau khi sử dụng
- [ ] Đã gọi dispose cho tất cả resources (controllers, animations, etc.)

### Hiệu suất UI

- [ ] Sử dụng ListView.builder thay vì ListView thông thường cho danh sách lớn
- [ ] Tránh sử dụng UniqueKey() trong ListView items
- [ ] Sử dụng const constructor khi có thể
- [ ] Tránh build lại widget không cần thiết

### Xử lý hình ảnh

- [ ] Sử dụng đọc file bất đồng bộ (readAsBytes thay vì readAsBytesSync)
- [ ] Có cơ chế resize/optimize hình ảnh trước khi hiển thị
- [ ] Sử dụng memoryCache cho hình ảnh được sử dụng thường xuyên

### Lỗi và Xử lý ngoại lệ

- [ ] Có xử lý try/catch cho các thao tác I/O
- [ ] Có cơ chế phục hồi khi xảy ra lỗi
- [ ] Log lỗi đúng cách

### Code Style

- [ ] Code tuân thủ quy tắc format Dart
- [ ] Không còn warning từ Flutter analyze
- [ ] Đã thêm comments cho code phức tạp
