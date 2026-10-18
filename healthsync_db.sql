-- =====================================================================
-- DỰ ÁN HEALTHSYNC: KHẮC PHỤC KHỦNG HOẢNG THIẾT KẾ CƠ SỞ DỮ LIỆU
-- Tác giả: System Analyst & Database Administrator
-- File: healthsync_db.sql
-- =====================================================================

DROP DATABASE IF EXISTS healthsync_db;
CREATE DATABASE healthsync_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE healthsync_db;

-- ---------------------------------------------------------------------
-- PHẦN 1: CÁC THỰC THỂ CƠ BẢN (Patients, Doctors)
-- ---------------------------------------------------------------------

CREATE TABLE Patients (
    patient_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(15) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE Doctors (
    doctor_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    specialty VARCHAR(50) NOT NULL,
    phone VARCHAR(15)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- PHẦN 2: BẢNG APPOINTMENTS (ĐÃ TÁI CẤU TRÚC ĐẠT CHUẨN HOẠT ĐỘNG)
-- Khắc phục LỖ HỔNG 1: Loại bỏ boolean is_active, thay bằng ENUM trạng thái
-- Khắc phục LỖ HỔNG 2: Bổ sung deposit_amount, penalty_fee, cancel_reason
-- ---------------------------------------------------------------------

CREATE TABLE Appointments (
    appointment_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    appointment_date DATETIME NOT NULL,
    
    -- Vòng đời trạng thái đúng theo UML Activity Diagram:
    -- PENDING -> CONFIRMED -> CHECKED_IN -> COMPLETED hoặc CANCELLED
    status ENUM('PENDING', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED') 
        NOT NULL DEFAULT 'PENDING',
    
    -- Quản lý tài chính: Dùng DECIMAL để tránh lỗi làm tròn số thực
    deposit_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (deposit_amount >= 0),
    penalty_fee DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (penalty_fee >= 0),
    
    -- Ghi nhận lý do hủy nếu bị CANCELLED
    cancel_reason VARCHAR(255) NULL,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Ràng buộc toàn vẹn khóa ngoại
    CONSTRAINT fk_app_patient FOREIGN KEY (patient_id) 
        REFERENCES Patients(patient_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_app_doctor FOREIGN KEY (doctor_id) 
        REFERENCES Doctors(doctor_id) ON UPDATE CASCADE ON DELETE RESTRICT,
        
    -- Ràng buộc logic tài chính: Tiền phạt không thể vượt quá tiền cọc
    CONSTRAINT chk_penalty_limit CHECK (penalty_fee <= deposit_amount)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- PHẦN 3: BẢNG PRESCRIPTIONS (ĐƠN THUỐC) - BỊ BỎ QUÊN Ở PHIÊN BẢN CŨ
-- Mỗi lịch hẹn sau khi hoàn tất (COMPLETED) sẽ có 1 đơn thuốc tương ứng
-- ---------------------------------------------------------------------

CREATE TABLE Prescriptions (
    prescription_id INT AUTO_INCREMENT PRIMARY KEY,
    appointment_id INT NOT NULL UNIQUE, -- Quan hệ 1-1 với Appointment đã khám
    medication_details TEXT NOT NULL,
    doctor_notes TEXT NULL,
    issued_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_pres_appointment FOREIGN KEY (appointment_id) 
        REFERENCES Appointments(appointment_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- PHẦN 4: DATABASE TRIGGER BẢO VỆ TÍNH TOÀN VẸN NGHIỆP VỤ
-- Chặn hành vi cố tình kê đơn thuốc cho lịch hẹn CHƯA KHÁM (chưa COMPLETED)
-- ---------------------------------------------------------------------

DELIMITER //

CREATE TRIGGER trg_check_prescription_eligibility
BEFORE INSERT ON Prescriptions
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    
    SELECT status INTO v_status 
    FROM Appointments 
    WHERE appointment_id = NEW.appointment_id;
    
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Lịch hẹn không tồn tại trong hệ thống!';
    ELSEIF v_status != 'COMPLETED' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Chỉ được kê đơn thuốc cho lịch hẹn có trạng thái COMPLETED!';
    END IF;
END //

DELIMITER ;

-- =====================================================================
-- PHẦN 5: CHẠY CÁC KỊCH BẢN THỰC NGHIỆM (SIMULATION SCENARIOS)
-- =====================================================================

-- Chuẩn bị dữ liệu ban đầu
INSERT INTO Patients (patient_id, full_name, phone) VALUES
(1, 'Trần Minh Tuấn', '0901234567'),
(2, 'Nguyễn Thị Bích', '0912345678'),
(3, 'Lê Hoàng Long', '0987654321');

INSERT INTO Doctors (doctor_id, full_name, specialty, phone) VALUES
(1, 'BS. CKI Nguyễn Quốc Hùng', 'Nội tổng quát', '0933333331'),
(2, 'BS. CKII Lê Thị Mai', 'Tai Mũi Họng', '0933333332');

-- ---------------------------------------------------------------------
-- KỊCH BẢN 1 (Thành công):
-- Bệnh nhân 1 đặt lịch cọc 500.000đ -> Xác nhận -> Check-in -> Khám xong -> Kê đơn
-- ---------------------------------------------------------------------

-- 1.1: Tạo lịch hẹn ban đầu (PENDING), cọc 500,000 VND
INSERT INTO Appointments (appointment_id, patient_id, doctor_id, appointment_date, status, deposit_amount)
VALUES (101, 1, 1, '2026-10-20 08:30:00', 'PENDING', 500000.00);

-- 1.2: Lễ tân/Hệ thống xác nhận tiền cọc đã vào tài khoản (CONFIRMED)
UPDATE Appointments 
SET status = 'CONFIRMED' 
WHERE appointment_id = 101;

-- 1.3: Bệnh nhân đến phòng khám và làm thủ tục (CHECKED_IN)
UPDATE Appointments 
SET status = 'CHECKED_IN' 
WHERE appointment_id = 101;

-- 1.4: Bác sĩ khám bệnh xong (COMPLETED)
UPDATE Appointments 
SET status = 'COMPLETED' 
WHERE appointment_id = 101;

-- 1.5: Bác sĩ lập đơn thuốc cho lịch hẹn 101
INSERT INTO Prescriptions (appointment_id, medication_details, doctor_notes)
VALUES (
    101, 
    '1. Paracetamol 500mg: 20 viên (Uống 1v x 2 lần/ngày sau ăn)\n2. Augmentin 1g: 14 viên (Uống 1v x 2 lần/ngày)',
    'Tái khám sau 7 ngày nếu còn sốt hoặc ho khan kéo dài.'
);


-- ---------------------------------------------------------------------
-- KỊCH BẢN 2 (Hủy và phạt cọc):
-- Bệnh nhân 2 đặt cọc 300.000đ -> Hủy sau khi CONFIRMED -> Phạt 150.000đ
-- ---------------------------------------------------------------------

-- 2.1: Lịch hẹn đã được xác nhận cọc 300,000 VND
INSERT INTO Appointments (appointment_id, patient_id, doctor_id, appointment_date, status, deposit_amount)
VALUES (102, 2, 2, '2026-10-21 14:00:00', 'CONFIRMED', 300000.00);

-- 2.2: Bệnh nhân gọi điện báo hủy vì bận đột xuất -> Cập nhật CANCELLED, lý do và phạt 50% cọc (150,000đ)
UPDATE Appointments 
SET status = 'CANCELLED',
    cancel_reason = 'Bận việc đột xuất không thể sắp xếp',
    penalty_fee = 150000.00
WHERE appointment_id = 102;


-- =====================================================================
-- PHẦN 6: TRUY VẤN ĐỐI SOÁT TÀI CHÍNH VÀ BÁO CÁO NGHIỆP VỤ
-- =====================================================================

-- 1. Báo cáo tổng hợp tình trạng lịch hẹn và doanh thu cọc/phạt
SELECT 
    a.appointment_id AS 'Mã LH',
    p.full_name AS 'Bệnh nhân',
    p.phone AS 'SĐT',
    d.full_name AS 'Bác sĩ phụ trách',
    a.appointment_date AS 'Thời gian hẹn',
    a.status AS 'Trạng thái',
    a.deposit_amount AS 'Tiền cọc (VND)',
    a.penalty_fee AS 'Phí phạt (VND)',
    (a.deposit_amount - a.penalty_fee) AS 'Tiền hoàn trả BN (VND)',
    IFNULL(a.cancel_reason, '-') AS 'Lý do hủy'
FROM Appointments a
JOIN Patients p ON a.patient_id = p.patient_id
JOIN Doctors d ON a.doctor_id = d.doctor_id
ORDER BY a.appointment_id;

-- 2. Báo cáo các bệnh nhân đã hoàn tất khám bệnh kèm chi tiết đơn thuốc
SELECT 
    a.appointment_id AS 'Mã Lịch Hẹn',
    p.full_name AS 'Tên Bệnh Nhân',
    d.full_name AS 'Bác Sĩ Khám',
    a.appointment_date AS 'Ngày Khám',
    pr.prescription_id AS 'Mã Đơn Thuốc',
    pr.medication_details AS 'Chi Tiết Thuốc',
    pr.doctor_notes AS 'Lời Dặn Của Bác Sĩ'
FROM Appointments a
JOIN Patients p ON a.patient_id = p.patient_id
JOIN Doctors d ON a.doctor_id = d.doctor_id
JOIN Prescriptions pr ON a.appointment_id = pr.appointment_id
WHERE a.status = 'COMPLETED';

-- 3. Tổng kết dòng tiền cho bộ phận Kế toán phòng khám
SELECT 
    COUNT(appointment_id) AS 'Tổng số lịch hẹn',
    SUM(deposit_amount) AS 'Tổng tiền cọc tiếp nhận',
    SUM(penalty_fee) AS 'Tổng thu từ phí phạt hủy',
    SUM(CASE WHEN status = 'COMPLETED' THEN deposit_amount ELSE 0 END) AS 'Cọc chuyển thành viện phí',
    SUM(CASE WHEN status = 'CANCELLED' THEN (deposit_amount - penalty_fee) ELSE 0 END) AS 'Tổng tiền hoàn trả khách'
FROM Appointments;
