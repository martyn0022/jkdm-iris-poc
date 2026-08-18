-- JKDM SMK POC · schema
-- Shared source of truth. Laravel reads this directly via Eloquent.
-- The generator container derives the COBOL fixed-width file from
-- these same tables, so any backend difference is provably LOGIC,
-- not data divergence.

CREATE TABLE tariff_rate (
    hs_code         VARCHAR(10)  PRIMARY KEY,
    description     VARCHAR(120) NOT NULL,
    duty_rate       NUMERIC(7,4) NOT NULL,
    sst_rate        NUMERIC(7,4) NOT NULL DEFAULT 0.1000,
    uom             VARCHAR(6)   NOT NULL DEFAULT 'UNT'
);

CREATE TABLE fta_rule (
    fta_code        VARCHAR(10)  NOT NULL,
    hs_code         VARCHAR(10)  NOT NULL,
    origin_country  CHAR(2)      NOT NULL,
    pref_rate       NUMERIC(7,4) NOT NULL,
    min_local_pct   NUMERIC(5,2) NOT NULL DEFAULT 40.00,
    PRIMARY KEY (fta_code, hs_code, origin_country)
);

CREATE TABLE declaration (
    decl_ref        VARCHAR(20)  PRIMARY KEY,
    decl_type       VARCHAR(4)   NOT NULL,
    declarant_tin   VARCHAR(16)  NOT NULL,
    origin_country  CHAR(2)      NOT NULL,
    fta_claimed     VARCHAR(10),
    local_pct       NUMERIC(5,2),
    currency_code   CHAR(3)      NOT NULL DEFAULT 'MYR',
    lodged_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE declaration_line (
    decl_ref        VARCHAR(20)  NOT NULL REFERENCES declaration(decl_ref),
    line_no         INT          NOT NULL,
    hs_code         VARCHAR(10)  NOT NULL REFERENCES tariff_rate(hs_code),
    quantity        NUMERIC(11,3) NOT NULL,
    customs_value   NUMERIC(13,2) NOT NULL,
    PRIMARY KEY (decl_ref, line_no)
);

CREATE INDEX idx_line_decl ON declaration_line(decl_ref);
