-- JKDM SMK POC · seed data
-- Deterministic. No randomness anywhere - a flaky comparator demo
-- is worse than no comparator demo.
--
-- Descriptions are deliberately longer than 35 chars so the COBOL
-- PIC X(35) truncation shows up as a MATERIAL difference.

INSERT INTO tariff_rate (hs_code, description, duty_rate, sst_rate, uom) VALUES
('8471.30.10', 'Portable automatic data processing machines weighing not more than 10 kg', 0.0500, 0.1000, 'UNT'),
('8517.12.00', 'Telephones for cellular networks or for other wireless networks', 0.0750, 0.1000, 'UNT'),
('6109.10.00', 'T-shirts, singlets and other vests, knitted or crocheted, of cotton', 0.0250, 0.1000, 'PCE'),
('8703.23.90', 'Motor cars with spark-ignition internal combustion engine, 1500-3000cc', 0.1000, 0.1000, 'UNT'),
('3304.99.90', 'Beauty or make-up preparations and preparations for the care of the skin', 0.0350, 0.1000, 'KGM'),
('9403.60.90', 'Wooden furniture of a kind used in the bedroom, other than seats', 0.0650, 0.1000, 'PCE'),
('4011.10.00', 'New pneumatic tyres of rubber of a kind used on motor cars', 0.0450, 0.1000, 'PCE'),
('1006.30.99', 'Semi-milled or wholly milled rice, whether or not polished or glazed', 0.2000, 0.0000, 'KGM');

INSERT INTO fta_rule (fta_code, hs_code, origin_country, pref_rate, min_local_pct) VALUES
('ATIGA', '8471.30.10', 'TH', 0.0000, 40.00),
('ATIGA', '8517.12.00', 'VN', 0.0000, 40.00),
('ATIGA', '1006.30.99', 'TH', 0.0000, 40.00),
('AKFTA', '8703.23.90', 'KR', 0.0500, 45.00),
('MTFTA', '4011.10.00', 'JP', 0.0200, 40.00);

-- ---------------------------------------------------------------
-- CLEAN CASES · both backends must agree exactly
-- ---------------------------------------------------------------
INSERT INTO declaration (decl_ref, decl_type, declarant_tin, origin_country, fta_claimed, local_pct) VALUES
('K1-2026-000101', 'K1', 'C12345678901', 'CN', NULL, NULL),
('K1-2026-000102', 'K1', 'C12345678902', 'US', NULL, NULL),
('K1-2026-000103', 'K1', 'C12345678903', 'DE', NULL, NULL);

INSERT INTO declaration_line (decl_ref, line_no, hs_code, quantity, customs_value) VALUES
('K1-2026-000101', 1, '8471.30.10', 10.000, 20000.00),
('K1-2026-000101', 2, '8517.12.00',  5.000, 10000.00),
('K1-2026-000102', 1, '6109.10.00', 100.000, 4000.00),
('K1-2026-000102', 2, '9403.60.90',  20.000, 8000.00),
('K1-2026-000103', 1, '4011.10.00',  40.000, 6000.00);

-- ---------------------------------------------------------------
-- FISCAL DIFFERENCE #1 · line-level vs total-level rounding
--
-- COBOL rounds each line to 2dp then accumulates.
-- PHP sums at full float precision then rounds once.
--
-- Expected:  COBOL 1088.47   PHP 1088.46   delta 0.01
--
-- This is the classic customs rounding dispute. It is deterministic
-- and arises from a genuine implementation difference - nothing is
-- hardcoded to force it.
-- ---------------------------------------------------------------
INSERT INTO declaration (decl_ref, decl_type, declarant_tin, origin_country, fta_claimed, local_pct) VALUES
('K1-2026-000104', 'K1', 'C12345678904', 'CN', NULL, NULL);

INSERT INTO declaration_line (decl_ref, line_no, hs_code, quantity, customs_value) VALUES
('K1-2026-000104', 1, '8471.30.10',  1.000, 1234.55),
('K1-2026-000104', 2, '8517.12.00',  1.000, 2345.67),
('K1-2026-000104', 3, '6109.10.00',  1.000,  987.65),
('K1-2026-000104', 4, '8703.23.90',  1.000, 4567.89),
('K1-2026-000104', 5, '3304.99.90',  1.000, 3210.55),
('K1-2026-000104', 6, '9403.60.90',  1.000, 1876.33),
('K1-2026-000104', 7, '4011.10.00',  1.000, 2999.99);

-- ---------------------------------------------------------------
-- FISCAL DIFFERENCE #2 · FTA threshold boundary
--
-- local_pct is EXACTLY the min_local_pct threshold (40.00).
-- COBOL applies preference on >= threshold.
-- PHP applies on > threshold.
--
-- Hand-coded, but realistic: a boundary condition misread during
-- conversion. Worth ~RM 600 on this declaration.
-- ---------------------------------------------------------------
INSERT INTO declaration (decl_ref, decl_type, declarant_tin, origin_country, fta_claimed, local_pct) VALUES
('K1-2026-000105', 'K1', 'C12345678905', 'TH', 'ATIGA', 40.00);

INSERT INTO declaration_line (decl_ref, line_no, hs_code, quantity, customs_value) VALUES
('K1-2026-000105', 1, '1006.30.99', 3000.000, 3000.00);

-- ---------------------------------------------------------------
-- CONTROL · FTA clearly above threshold, both must agree
-- ---------------------------------------------------------------
INSERT INTO declaration (decl_ref, decl_type, declarant_tin, origin_country, fta_claimed, local_pct) VALUES
('K1-2026-000106', 'K1', 'C12345678906', 'TH', 'ATIGA', 55.00);

INSERT INTO declaration_line (decl_ref, line_no, hs_code, quantity, customs_value) VALUES
('K1-2026-000106', 1, '1006.30.99', 2000.000, 2000.00);
