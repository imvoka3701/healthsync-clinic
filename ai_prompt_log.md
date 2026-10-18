# Nhật Ký Tương Tác Cùng AI (AI Prompt Log)
**Dự án:** Khắc phục khủng hoảng thiết kế CSDL Phòng khám HealthSync  
**Vai trò Học viên:** System Analyst & Database Administrator  
**Vai trò AI:** Data Modeling Assistant & Technical Critic

---

## 📌 Prompt 1: Phân tích Anti-pattern của cờ Boolean trong quản lý vòng đời
- **Mục đích:** Tìm hiểu lý do kỹ thuật tại sao `is_active BOOLEAN` là một thiết kế tồi cho quy trình nghiệp vụ nhiều trạng thái.
- **User Prompt:**
  > *"Trong thiết kế cơ sở dữ liệu quan hệ, tại sao việc dùng một cột `is_active` (kiểu TINYINT/BOOLEAN) để theo dõi vòng đời của một Đơn hàng hoặc Lịch hẹn lại là một thiết kế tồi (Anti-pattern)? Tôi nên thay thế bằng cấu trúc nào để phản ánh chuẩn 5 trạng thái: PENDING, CONFIRMED, CHECKED_IN, COMPLETED, CANCELLED?"*
- **AI Response Summary & Quyết định thiết kế:**
  - `BOOLEAN` chỉ biểu diễn được 2 giá trị (Nhị phân 0 hoặc 1), chỉ phù hợp cho cờ bật/tắt (Toggle Flag) như `is_email_verified`.
  - Một thực thể kinh doanh luôn có một máy trạng thái hữu hạn (Finite State Machine). Khi dùng boolean, lập trình viên sẽ phải tạo thêm hàng loạt cờ con như `is_confirmed`, `is_checked_in`, `is_completed`, `is_cancelled` dẫn đến trạng thái xung đột không kiểm soát được (ví dụ: vừa `is_completed = true` lại vừa `is_cancelled = true`).
  - **Quyết định:** Sử dụng kiểu dữ liệu `ENUM('PENDING', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'PENDING'`.

---

## 📌 Prompt 2: Lựa chọn kiểu dữ liệu tài chính (Financial Precision)
- **Mục đích:** Đảm bảo độ chính xác tuyệt đối cho `deposit_amount` và `penalty_fee`, tránh thất thoát kế toán.
- **User Prompt:**
  > *"Khi thiết kế cột `deposit_amount` và `penalty_fee` trong MySQL phục vụ tính toán tài chính và cấn trừ cọc, tôi nên dùng kiểu dữ liệu FLOAT, DOUBLE hay DECIMAL? Nguy cơ làm tròn số nhị phân trong kế toán diễn ra như thế nào?"*
- **AI Response Summary & Quyết định thiết kế:**
  - `FLOAT` và `DOUBLE` là kiểu dữ liệu số chấm động xấp xỉ theo chuẩn IEEE 754. Hệ nhị phân không thể biểu diễn chính xác các phân số thập phân (như 0.1 hay 0.05), dẫn đến hiện tượng sai số làm tròn tích lũy khi tính tổng `SUM()` hoặc nhân chia.
  - `DECIMAL(M, D)` là kiểu dữ liệu số có độ chính xác cố định (Fixed-point representation), lưu trữ từng chữ số dưới dạng chuỗi byte nhị phân, đảm bảo $0.1 + 0.2 = 0.3$ chính xác 100%.
  - **Quyết định:** Định nghĩa cột dạng `DECIMAL(12, 2)` (tối đa 999 tỷ VND, 2 chữ số thập phân), kèm ràng buộc `CHECK (deposit_amount >= 0)` và `CHECK (penalty_fee <= deposit_amount)`.

---

## 📌 Prompt 3: Cú pháp tái cấu trúc bảng bằng ALTER TABLE an toàn
- **Mục đích:** Ôn lại cú pháp sửa bảng trong môi trường production mà không làm gián đoạn hay mất dữ liệu hiện hữu.
- **User Prompt:**
  > *"Hãy cho tôi xem cú pháp chuẩn trong MySQL để: (1) Xóa cột `is_active` cũ, (2) Thêm cột `status` kiểu ENUM, (3) Thêm các cột tài chính `deposit_amount`, `penalty_fee`, `cancel_reason` vào bảng `Appointments` đang có dữ liệu."*
- **AI Response Summary & Áp dụng mã nguồn:**
  ```sql
  ALTER TABLE Appointments
      DROP COLUMN is_active,
      ADD COLUMN status ENUM('PENDING', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'PENDING' AFTER appointment_date,
      ADD COLUMN deposit_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 AFTER status,
      ADD COLUMN penalty_fee DECIMAL(12, 2) NOT NULL DEFAULT 0.00 AFTER deposit_amount,
      ADD COLUMN cancel_reason VARCHAR(255) NULL AFTER penalty_fee,
      ADD CONSTRAINT chk_penalty_limit CHECK (penalty_fee <= deposit_amount);
  ```

---

## 📌 Prompt 4: Chặn hành vi chèn dữ liệu phi logic bằng Database Trigger
- **Mục đích:** Đảm bảo toàn vẹn ở tầng dữ liệu sâu nhất, không phụ thuộc hoàn toàn vào code backend.
- **User Prompt:**
  > *"Nếu tầng ứng dụng có lỗ hổng hoặc ai đó chạy script INSERT trực tiếp một đơn thuốc vào bảng `Prescriptions` cho một lịch hẹn đang ở trạng thái `PENDING` (chưa khám), làm thế nào để tôi dùng Trigger trong MySQL để ném ra Exception và chặn đứng giao dịch?"*
- **AI Response Summary & Áp dụng:**
  - Sử dụng trigger `BEFORE INSERT` kết hợp cấu trúc `SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '...'` để hủy bỏ thao tác ngay khi phát hiện `Appointments.status != 'COMPLETED'`.

---

## 📌 Prompt 5: Chiến lược toàn vẹn khóa ngoại (Foreign Key Strategy)
- **Mục đích:** Thiết lập đúng hành vi xóa/sửa dữ liệu (`ON DELETE` / `ON UPDATE`).
- **User Prompt:**
  > *"Với bảng `Appointments`, khi liên kết tới `Patients` và `Doctors` tôi nên dùng `ON DELETE RESTRICT` hay `ON DELETE CASCADE`? Còn với bảng `Prescriptions` liên kết tới `Appointments` thì sao?"*
- **AI Response Summary & Quyết định:**
  - Đối với `Patients` và `Doctors`: Bắt buộc dùng `ON DELETE RESTRICT`. Phòng khám không được phép xóa bác sĩ hoặc bệnh nhân nếu họ đã có lịch sử khám bệnh (vi phạm lưu trữ hồ sơ bệnh án y khoa).
  - Đối với `Prescriptions`: Dùng `ON DELETE CASCADE` với `Appointments` (Đơn thuốc là thực thể phụ thuộc trực tiếp vào buổi khám, nếu buổi khám đó bị xóa hoàn toàn thì đơn thuốc tương ứng cũng sẽ được dọn sạch).
