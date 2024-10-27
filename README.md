# Script Quản lý Apache Web Server và DNS

## Lưu ý quan trọng
⚠️ **Trước khi chạy script, bạn cần đảm bảo:**
1. Đã cài đặt và cấu hình DNS Server (BIND) trên máy chủ
2. DNS Server đang hoạt động và có thể phân giải tên miền
3. Cấu hình DNS đã được thiết lập đúng trong file `/etc/named.conf`
4. Firewall đã mở port 53 cho dịch vụ DNS hoac tat
5. SELinux đã được cấu hình phù hợp cho DNS
6. Nếu cẩn thận nên tạo 1 snapshot để phòng hờ hư không thể fix thì revert về
7. Máy client cần trỏ dns về dns của máy chủ web

## Tổng quan
Script Bash này cung cấp giải pháp tự động để quản lý Apache web server và cấu hình DNS trên hệ thống CentOS/RHEL. Nó cung cấp một bộ tính năng toàn diện để thiết lập và quản lý môi trường web hosting, bao gồm cấu hình domain, quản lý vùng DNS và nhiều môi trường runtime khác nhau.

## Tính năng
- Cấu hình và quản lý vùng DNS
- Thiết lập Virtual host cho Apache
- Hỗ trợ nhiều môi trường runtime:
  - Tomcat
  - PHP
  - Node.js
  - Website tĩnh
- Cài đặt hệ quản trị cơ sở dữ liệu:
  - MySQL (MariaDB)
  - PostgreSQL
  - MongoDB
- Tự động tạo backup cho các file cấu hình
- Quản lý và liệt kê domain
- Gỡ bỏ web server với các kiểm tra an toàn

## Yêu cầu hệ thống
- Hệ điều hành: CentOS 7/RHEL
- Quyền root hoặc sudo
- Kết nối internet để cài đặt gói
- Yêu cầu tối thiểu:
  - RAM: 2GB (khuyến nghị)
  - Ổ cứng trống: 10GB (khuyến nghị)

## Cài đặt và sử dụng script
1. Tải script về máy:
```bash
curl -O https://raw.githubusercontent.com/ntSagn/Script-Web-Server/refs/heads/main/webserver.sh
```

2. Cấp quyền thực thi:
```bash
chmod +x webserver.sh
```

3. Chạy script với quyền root:
```bash
sudo ./webserver.sh
```

4. Sử dụng menu tương tác để chọn các thao tác:
   - Tùy chọn 1: Cài đặt các gói phụ thuộc
   - Tùy chọn 2: Thêm domain mới và vùng DNS
   - Tùy chọn 3: Liệt kê domain đang hoạt động
   - Tùy chọn 4: Thêm hosting cho domain
   - Tùy chọn 5: Cài đặt Web Runtime
   - Tùy chọn 6: Cài đặt DBMS
   - Tùy chọn 7: Gỡ bỏ web server
   - Tùy chọn 8: Tắt tường lửa
   - Tùy chọn 9: Thoát

## Lưu ý quan trọng

### Luu y
- Kiểm tra cài đặt firewall để đảm bảo truy cập đúng các dịch vụ web
- Download source web tinh neu can voi lenh sau: "curl -O https://raw.githubusercontent.com/ntSagn/Script-Web-Server/refs/heads/main/static.zip" va giai nen bang lenh "unzip static.zip -d /var/www/html/sgu.edu.vn" voi sgu.edu.vn la ten mien ban muon paste source vao chon yes neu dang ton tai file index.html mau
- Download file sql db source php:"wget --no-check-certificate 'https://drive.google.com/uc?export=download&id=1CMyTg0x6B8te4Q9yCWUk2Lj3NBD5powf' -O databasephp.sql" sau do thiet lap mysqld va tao db sau do dumb file sql vao
- Download file source web php tu link drive:"https://drive.google.com/file/d/1FJzdm-dX3py2DbOphN56XnsIpvGlHt3k/view" va sau do giai nen nhu tren (wget ko xai duoc vi dung luong file)

### Các file cấu hình
Script quản lý các file cấu hình sau:
- Cấu hình Apache: `/etc/httpd/conf.d/`
- File vùng DNS: `/var/named/`
- Cấu hình Named: `/etc/named.rfc1912.zones`

### Quản lý backup
- Backup tự động được tạo với hậu tố timestamp
- Định dạng file backup: `filename.bak.YYYY-MM-DD_HH:MM:SS`
- Định kỳ rà soát và dọn dẹp các backup cũ

### Quản lý dịch vụ
Script xử lý các dịch vụ sau:
- httpd (Apache)
- named (DNS)
- Các dịch vụ database (tùy vào cài đặt)
- Các dịch vụ runtime (tùy vào cấu hình)

## Xử lý sự cố
1. Nếu dịch vụ không khởi động:
   - Kiểm tra log: `journalctl -xe`
   - Kiểm tra cú pháp cấu hình
   - Đảm bảo không có xung đột cổng

2. Nếu vùng DNS không hoạt động:
   - Kiểm tra trạng thái dịch vụ named
   - Kiểm tra quyền file zone
   - Xác thực cú pháp cấu hình DNS

3. Nếu dịch vụ web không truy cập được:
   - Kiểm tra cài đặt firewall
   - Xác thực cấu hình Apache
   - Đảm bảo ngữ cảnh SELinux phù hợp

## Bảo trì
- Thường xuyên kiểm tra log hệ thống
- Theo dõi dung lượng ổ đĩa
- Rà soát và dọn dẹp backup cũ
- Cập nhật hệ thống thường xuyên

## Giới hạn
- Thiết kế cho hệ thống CentOS/RHEL
- Yêu cầu quyền root
- Cần kết nối internet để cài đặt gói
- Một số tính năng có thể cần thêm tài nguyên hệ thống

## Hỗ trợ
Khi gặp sự cố:
1. Kiểm tra yêu cầu hệ thống
2. Kiểm tra log hệ thống
3. Đảm bảo đã đáp ứng tất cả điều kiện tiên quyết
4. Rà soát file cấu hình tìm lỗi
