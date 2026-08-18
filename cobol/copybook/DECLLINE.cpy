      *****************************************************************
      * DECLLINE - denormalised declaration line record               *
      *                                                               *
      * This copybook is the record-structure reference for the        *
      * COBOL side. The generator container derives the flat file      *
      * from the Postgres schema - so this file and the relational     *
      * schema are two representations of the same data.               *
      *                                                               *
      * That is exactly the CardDemo TS2-04 / TS3-04 decision:         *
      * "the database schema becomes the record-structure reference".  *
      *                                                               *
      * NOTE: HS-DESC is PIC X(35). The Postgres column is             *
      * VARCHAR(120). The truncation is real and shows up in the       *
      * comparator as a MATERIAL difference.                           *
      *****************************************************************
       01  DECL-LINE-REC.
           05  DL-DECL-REF          PIC X(20).
           05  DL-DECL-TYPE         PIC X(04).
           05  DL-DECLARANT-TIN     PIC X(16).
           05  DL-ORIGIN-COUNTRY    PIC X(02).
           05  DL-FTA-CLAIMED       PIC X(10).
           05  DL-LOCAL-PCT         PIC 9(03)V99.
           05  DL-CURRENCY          PIC X(03).
           05  DL-LINE-NO           PIC 9(03).
           05  DL-HS-CODE           PIC X(10).
           05  DL-HS-DESC           PIC X(35).
           05  DL-QUANTITY          PIC 9(08)V999.
           05  DL-CUSTOMS-VALUE     PIC 9(11)V99.
           05  DL-DUTY-RATE         PIC 9(03)V9999.
           05  DL-SST-RATE          PIC 9(03)V9999.
           05  DL-PREF-RATE         PIC 9(03)V9999.
           05  DL-PREF-MIN-PCT      PIC 9(03)V99.
           05  DL-HAS-PREF          PIC X(01).
