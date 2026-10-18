# Báo Cáo Chẩn Đoán Tính Nhất Quán (Gap Analysis Report)
**Dự án:** Số hóa quy trình khám bệnh - Phòng khám Đa khoa HealthSync  
**Người thực hiện:** System Analyst & Database Administrator  
**Mục tiêu:** Rà soát và xử lý các điểm vênh (Inconsistencies) giữa UML Activity Diagram và Cơ sở dữ liệu MySQL

---

## 1. Tóm tắt chẩn đoán: 4 "Lỗ hổng" cốt tử trong thiết kế cũ (Legacy DB)

Bản thiết kế cơ sở dữ liệu ban đầu của lập trình viên backend đã bộc lộ sự thiếu hụt trầm trọng so với luồng nghiệp vụ do Business Analyst (BA) đưa ra:

| STT | Nghiệp vụ theo Activity Diagram | Hiện trạng Legacy Database | Hậu quả kỹ thuật & Nghiệp vụ |
|:---:|---|---|---|
| **1** | Vòng đời lịch hẹn gồm 5 trạng thái liên tục: `PENDING` &rarr; `CONFIRMED` &rarr; `CHECKED_IN` &rarr; `COMPLETED` / `CANCELLED` | Chỉ dùng duy nhất một cột cờ Boolean `is_active` (`TRUE`/`FALSE`) | **Anti-pattern nghiêm trọng:** Không thể biết bệnh nhân đang ở bước nào (đã cọc chưa, đã đến phòng khám chưa, đã khám xong hay đã hủy). Gây tê liệt toàn bộ luồng xử lý trên giao diện. |
| **2** | Bệnh nhân đặt cọc tiền giữ chỗ (`Deposit`), nếu hủy lịch sau khi xác nhận thì bị phạt cọc (`Penalty Fee`) | Hoàn toàn không có cột lưu trữ tiền tệ và lý do hủy | **Thất thoát tài chính:** Kế toán không thể biết bệnh nhân đã cọc bao nhiêu, lý do hủy là gì, và số tiền phạt bị giữ lại là bao nhiêu để tính toán tiền hoàn cọc (`Refund`). |
| **3** | Bác sĩ kê đơn thuốc ngay sau khi khám xong (`COMPLETED`) | Hoàn toàn không có bảng `Prescriptions` (Đơn thuốc) | **Gãy đổ nghiệp vụ cốt lõi:** Bác sĩ không thể lưu trữ thông tin thuốc và hướng dẫn điều trị vào hệ thống; dược sĩ tại quầy thuốc không có dữ liệu để xuất thuốc. |
| **4** | Rủi ro tính toán sai lệch tiền tệ | Không định nghĩa kiểu dữ liệu tài chính chuyên dụng | Nếu lập trình viên dùng kiểu `FLOAT` hoặc `DOUBLE` sẽ phát sinh lỗi làm tròn nhị phân (Float precision error), gây lệch sổ sách kế toán. |

---

## 2. Trả lời các câu hỏi vấn đáp chuyên môn (Defense & Rationale)

### Câu hỏi 1: Nếu một lịch hẹn đang ở trạng thái `PENDING` (chưa khám), nhưng có người cố tình chèn (INSERT) một đơn thuốc vào bảng `Prescriptions`, làm thế nào để chặn hành động phi logic này ở tầng cơ sở dữ liệu?
**Trả lời:**  
Để bảo vệ toàn vẹn logic nghiệp vụ ở mức sâu nhất (Database-level constraint), ta không nên chỉ phụ thuộc vào tầng ứng dụng (Backend API) vì API có thể bị lỗi (bug) hoặc bị can thiệp qua các script import dữ liệu.  
**Giải pháp:** Xây dựng **Database Trigger** loại `BEFORE INSERT` trên bảng `Prescriptions`:
- Trigger sẽ truy vấn trạng thái (`status`) của lịch hẹn tương ứng trong bảng `Appointments`.
- Nếu `status != 'COMPLETED'`, trigger kích hoạt lệnh `SIGNAL SQLSTATE '45000'` kèm thông báo lỗi cụ thể, lập tức hủy giao dịch (Rollback) và ngăn chặn bản ghi rác xâm nhập CSDL.

```sql
DELIMITER //
CREATE TRIGGER trg_check_prescription_eligibility
BEFORE INSERT ON Prescriptions
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT status INTO v_status FROM Appointments WHERE appointment_id = NEW.appointment_id;
    IF v_status != 'COMPLETED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Chỉ được kê đơn thuốc cho lịch hẹn đã hoàn tất (COMPLETED)!';
    END IF;
END //
DELIMITER ;
```

---

### Câu hỏi 2: Tại sao việc lưu `penalty_fee` lại quan trọng đối với tính toàn vẹn hệ thống? Nếu kế toán muốn đối soát doanh thu cuối tháng, sự thiếu hụt cột này sẽ gây ra hậu quả gì?
**Trả lời:**
- **Ý nghĩa:** `penalty_fee` (Phí phạt hủy lịch) là một dòng tiền doanh thu thực tế phát sinh từ chính sách phòng khám. Đồng thời, nó là căn cứ toán học duy nhất để xác định số tiền phòng khám phải chuyển trả lại cho bệnh nhân:  
  $$\text{Tiền hoàn trả (Refund)} = \text{Tiền cọc (Deposit Amount)} - \text{Phí phạt (Penalty Fee)}$$
- **Hậu quả nếu thiếu hụt:**
  1. **Thất thoát tài chính:** Không thể tính được doanh thu từ các lịch hẹn bị hủy muộn.
  2. **Tranh chấp với khách hàng:** Lễ tân và kế toán không có căn cứ minh bạch để giải trình số tiền đã cấn trừ và số tiền hoàn lại vào tài khoản bệnh nhân.
  3. **Lệch sổ sách kế toán cuối tháng:** Tổng số dư tài khoản ngân hàng thực tế của phòng khám sẽ không khớp với báo cáo trên phần mềm, vi phạm nguyên tắc kiểm toán và tính toàn vẹn dữ liệu.

---

### Câu hỏi 3: Sự nhất quán (Consistency) giữa UML Activity Diagram và ERD đóng vai trò gì trong việc chuyển giao công việc giữa BA và Dev?
**Trả lời:**
- **Activity Diagram** phản ánh **Hành vi động theo thời gian (Behavioral View / State Machine)** của quy trình kinh doanh.
- **ERD** phản ánh **Cấu trúc dữ liệu tĩnh bền vững (Structural View / Data Persistence)**.
- **Vai trò cốt lõi của tính nhất quán:**
  1. **Bảo toàn dữ liệu vòng đời:** Mọi trạng thái trung gian, điều kiện rẽ nhánh và kết quả đầu ra trong Activity Diagram đều phải có nơi lưu trữ tương ứng trong ERD. Nếu ERD thiếu cột/bảng, mã nguồn Backend của Developer sẽ không có chỗ để lưu (`No Persistence Layer`), dẫn đến lỗi hệ thống liên tục.
  2. **Rút ngắn thời gian bàn giao và giảm thiểu chi phí sửa lỗi:** Phát hiện và đồng bộ hóa ERD với BA từ sớm giúp tránh được các đợt đập đi xây lại (Refactoring) tốn kém khi phần mềm đã vận hành thực tế.
