-- JKDM SMK POC · vessel manifest (CUSCAR domain)
--
-- Substrate for the hands-on exercise. Same discipline as the
-- declaration tables: one source of truth, two representations, and
-- differences that arise from the implementations rather than from
-- the data.
--
-- NOTE ON declared_consignments
-- A denormalised counter, maintained by the application. On
-- MANIFEST-2026-0044 it has drifted from the actual consignment
-- count. COBOL counts the records; PHP trusts the column. That is a
-- real and extremely common failure mode, and it is the exercise's
-- "is a count fiscal?" argument.

CREATE TABLE manifest (
    manifest_ref          VARCHAR(24)  PRIMARY KEY,
    vessel_id             VARCHAR(16)  NOT NULL,
    vessel_name           VARCHAR(60)  NOT NULL,
    voyage_no             VARCHAR(12)  NOT NULL,
    carrier_tin           VARCHAR(16)  NOT NULL,
    port_of_discharge     VARCHAR(8)   NOT NULL,
    eta                   TIMESTAMPTZ  NOT NULL,
    status_code           CHAR(2)      NOT NULL,
    declared_consignments INT          NOT NULL,
    total_gross_kg        NUMERIC(13,2) NOT NULL
);

CREATE TABLE manifest_consignment (
    manifest_ref     VARCHAR(24) NOT NULL REFERENCES manifest(manifest_ref),
    line_no          INT         NOT NULL,
    consignment_ref  VARCHAR(24) NOT NULL,
    container_count  INT         NOT NULL,
    gross_kg         NUMERIC(13,2) NOT NULL,
    description      VARCHAR(120) NOT NULL,
    PRIMARY KEY (manifest_ref, line_no)
);

CREATE INDEX idx_cons_manifest ON manifest_consignment(manifest_ref);

-- Status codes as the core holds them. PHP expands these for its API;
-- COBOL returns the stored code. Release status is named in the
-- SMK 5.7 fiscal list - which is what makes it an argument.
CREATE TABLE manifest_status (
    status_code CHAR(2) PRIMARY KEY,
    status_name VARCHAR(20) NOT NULL
);
INSERT INTO manifest_status VALUES
    ('RL','RELEASED'), ('HD','HELD'), ('CL','CLEARED'), ('AR','ARRIVED');

-- ---------------------------------------------------------------
-- Six clean manifests, one ETA-timezone case, one count drift.
-- ---------------------------------------------------------------
INSERT INTO manifest (manifest_ref, vessel_id, vessel_name, voyage_no, carrier_tin,
                      port_of_discharge, eta, status_code, declared_consignments, total_gross_kg) VALUES
('MANIFEST-2026-0041','9V-8841','MV BINTANG SATU','VOY-8841','C99000000001','MYPKG','2026-08-20 06:00:00+08','RL', 3, 24000.00),
('MANIFEST-2026-0042','9V-8842','MV SELATAN MAJU','VOY-8842','C99000000002','MYPKG','2026-08-21 14:30:00+08','RL', 2, 15500.00),
('MANIFEST-2026-0043','9V-8843','MV TANJUNG BIRU','VOY-8843','C99000000003','MYPGU','2026-08-22 09:15:00+08','CL', 2,  9800.00),
('MANIFEST-2026-0044','9V-8844','MV KOTA MERDEKA','VOY-8844','C99000000004','MYPKG','2026-08-23 18:45:00+08','RL', 4, 31200.00),
('MANIFEST-2026-0045','9V-8845','MV HANG TUAH','VOY-8845','C99000000005','MYPEN','2026-08-24 03:00:00+08','HD', 2, 12750.00),
('MANIFEST-2026-0046','9V-8846','MV SRI MUARA','VOY-8846','C99000000006','MYPKG','2026-08-25 22:10:00+08','RL', 2, 18300.00);

INSERT INTO manifest_consignment (manifest_ref, line_no, consignment_ref, container_count, gross_kg, description) VALUES
('MANIFEST-2026-0041',1,'CN-88410001',120,12000.00,'Consolidated consumer electronics and accessories'),
('MANIFEST-2026-0041',2,'CN-88410002', 60, 8000.00,'Knitted cotton apparel in cartons'),
('MANIFEST-2026-0041',3,'CN-88410003', 20, 4000.00,'Rubber tyres for passenger vehicles'),
('MANIFEST-2026-0042',1,'CN-88420001', 80, 9500.00,'Wooden bedroom furniture, flat packed'),
('MANIFEST-2026-0042',2,'CN-88420002', 40, 6000.00,'Cosmetic preparations for skin care'),
('MANIFEST-2026-0043',1,'CN-88430001', 55, 5800.00,'Milled rice in woven polypropylene sacks'),
('MANIFEST-2026-0043',2,'CN-88430002', 30, 4000.00,'Cellular telephone handsets, retail packed'),
-- 0044 declares 4 consignments; only 3 records exist. The counter drifted.
('MANIFEST-2026-0044',1,'CN-88440001',100,15000.00,'Motor vehicle parts and assemblies'),
('MANIFEST-2026-0044',2,'CN-88440002', 70,10200.00,'Portable data processing machines'),
('MANIFEST-2026-0044',3,'CN-88440003', 45, 6000.00,'Assorted household goods'),
('MANIFEST-2026-0045',1,'CN-88450001', 65, 7750.00,'Chilled foodstuffs in reefer containers'),
('MANIFEST-2026-0045',2,'CN-88450002', 40, 5000.00,'Pharmaceutical products, temperature controlled'),
('MANIFEST-2026-0046',1,'CN-88460001',110,11300.00,'Industrial machinery components'),
('MANIFEST-2026-0046',2,'CN-88460002', 65, 7000.00,'Steel fasteners and fixings in drums');
