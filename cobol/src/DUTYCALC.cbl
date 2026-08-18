       IDENTIFICATION DIVISION.
       PROGRAM-ID. DUTYCALC.
      *****************************************************************
      * JKDM SMK POC - duty and tax calculation                       *
      *                                                               *
      * Represents the retained fiscal core: SMK Level-1 functions     *
      * 03 (Tariff, Origin & Valuation) and 04 (Duty, Tax & Revenue).  *
      * Per SMK 5.8 this is the "LEAVE IN COBOL" quadrant.             *
      *                                                               *
      * READ-ONLY. Persists nothing. This is deliberate - it makes     *
      * the operation safe to shadow (see spec 5.1, shadow-on-writes). *
      *                                                               *
      * ARITHMETIC NOTE                                                *
      * Working storage uses COMP-3 packed decimal. Each line's duty   *
      * is ROUNDED to 2dp BEFORE accumulation. The PHP implementation  *
      * sums at full float precision and rounds once at the end.       *
      * On multi-line declarations these diverge. Nothing is           *
      * hardcoded to force this - it is the genuine behaviour.         *
      *                                                               *
      * Usage: DUTYCALC <declaration-reference>                        *
      * Output: fixed-width record to stdout                           *
      *****************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT DECL-FILE ASSIGN TO WS-FILE-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  DECL-FILE.
       COPY "DECLLINE.cpy".

       WORKING-STORAGE SECTION.

       01  WS-FILE-PATH             PIC X(255).
       01  WS-FILE-STATUS           PIC XX.
       01  WS-EOF                   PIC X VALUE 'N'.
       01  WS-ARG-REF               PIC X(20).
       01  WS-DATA-DIR              PIC X(200).

      * ---- packed decimal working fields -------------------------
       01  WS-CALC-FIELDS.
           05  WS-EFFECTIVE-RATE    PIC S9(03)V9999 COMP-3.
           05  WS-LINE-DUTY         PIC S9(11)V99   COMP-3.
           05  WS-LINE-SST          PIC S9(11)V99   COMP-3.
           05  WS-LINE-BASE         PIC S9(11)V99   COMP-3.
           05  WS-TOT-DUTY          PIC S9(11)V99   COMP-3 VALUE ZERO.
           05  WS-TOT-SST           PIC S9(11)V99   COMP-3 VALUE ZERO.
           05  WS-TOT-VALUE         PIC S9(11)V99   COMP-3 VALUE ZERO.
           05  WS-TOT-PAYABLE       PIC S9(11)V99   COMP-3 VALUE ZERO.
           05  WS-LINE-COUNT        PIC 9(03)       VALUE ZERO.
           05  WS-PREF-APPLIED      PIC X           VALUE 'N'.
           05  WS-FOUND             PIC X           VALUE 'N'.

       01  WS-TIMESTAMP.
           05  WS-TS-DATE           PIC X(08).
           05  WS-TS-TIME           PIC X(06).
       01  WS-CURRENT-DATE          PIC X(21).

      * ---- fixed-width response ----------------------------------
      * Positional, zero-padded, no ISO timestamps. This is what
      * forces the IRIS transformation to do real work. A COBOL
      * service returning clean JSON would teach nothing.
       01  RESP-HEADER.
           05  RH-STATUS            PIC X(02).
           05  RH-DECL-REF          PIC X(20).
           05  RH-LINE-COUNT        PIC 9(03).
           05  RH-TOT-VALUE         PIC 9(11)V99.
           05  RH-TOT-DUTY          PIC 9(11)V99.
           05  RH-TOT-SST           PIC 9(11)V99.
           05  RH-TOT-PAYABLE       PIC 9(11)V99.
           05  RH-PREF-APPLIED      PIC X(01).
           05  RH-CALC-TS           PIC X(14).

       01  RESP-LINE.
           05  RL-MARKER            PIC X(02) VALUE 'LN'.
           05  RL-LINE-NO           PIC 9(03).
           05  RL-HS-CODE           PIC X(10).
           05  RL-HS-DESC           PIC X(35).
           05  RL-RATE-APPLIED      PIC 9(03)V9999.
           05  RL-CUSTOMS-VALUE     PIC 9(11)V99.
           05  RL-LINE-DUTY         PIC 9(11)V99.
           05  RL-LINE-SST          PIC 9(11)V99.

       PROCEDURE DIVISION.

       MAIN-PARA.
           ACCEPT WS-ARG-REF FROM COMMAND-LINE
           IF WS-ARG-REF = SPACES
               MOVE 'ER' TO RH-STATUS
               DISPLAY 'ERno declaration reference supplied'
               STOP RUN
           END-IF

           ACCEPT WS-DATA-DIR FROM ENVIRONMENT "COBOL_DATA_DIR"
           IF WS-DATA-DIR = SPACES
               MOVE '/data' TO WS-DATA-DIR
           END-IF
           STRING FUNCTION TRIM(WS-DATA-DIR) '/declline.dat'
               DELIMITED BY SIZE INTO WS-FILE-PATH
           END-STRING

           PERFORM PROCESS-FILE
           PERFORM EMIT-HEADER
           STOP RUN.

       PROCESS-FILE.
           OPEN INPUT DECL-FILE
           IF WS-FILE-STATUS NOT = '00'
               DISPLAY 'ERcannot open ' FUNCTION TRIM(WS-FILE-PATH)
               STOP RUN
           END-IF

           PERFORM UNTIL WS-EOF = 'Y'
               READ DECL-FILE
                   AT END
                       MOVE 'Y' TO WS-EOF
                   NOT AT END
                       IF DL-DECL-REF = WS-ARG-REF
                           MOVE 'Y' TO WS-FOUND
                           PERFORM CALC-LINE
                       END-IF
               END-READ
           END-PERFORM

           CLOSE DECL-FILE.

       CALC-LINE.
      *    ---- preference test -----------------------------------
      *    COBOL applies preference at >= threshold.
      *    The PHP implementation uses > threshold.
      *    On a declaration sitting exactly ON the threshold the two
      *    disagree. Boundary conditions are a classic conversion
      *    defect - this one is deliberate.
           IF DL-HAS-PREF = 'Y'
              AND DL-LOCAL-PCT >= DL-PREF-MIN-PCT
               MOVE DL-PREF-RATE TO WS-EFFECTIVE-RATE
               MOVE 'Y' TO WS-PREF-APPLIED
           ELSE
               MOVE DL-DUTY-RATE TO WS-EFFECTIVE-RATE
           END-IF

      *    ---- duty: ROUNDED per line, then accumulated ----------
           COMPUTE WS-LINE-DUTY ROUNDED =
               DL-CUSTOMS-VALUE * WS-EFFECTIVE-RATE
           END-COMPUTE

      *    ---- SST on duty-inclusive value -----------------------
           COMPUTE WS-LINE-BASE =
               DL-CUSTOMS-VALUE + WS-LINE-DUTY
           END-COMPUTE
           COMPUTE WS-LINE-SST ROUNDED =
               WS-LINE-BASE * DL-SST-RATE
           END-COMPUTE

           ADD WS-LINE-DUTY        TO WS-TOT-DUTY
           ADD WS-LINE-SST         TO WS-TOT-SST
           ADD DL-CUSTOMS-VALUE    TO WS-TOT-VALUE
           ADD 1                   TO WS-LINE-COUNT

           MOVE DL-LINE-NO         TO RL-LINE-NO
           MOVE DL-HS-CODE         TO RL-HS-CODE
           MOVE DL-HS-DESC         TO RL-HS-DESC
           MOVE WS-EFFECTIVE-RATE  TO RL-RATE-APPLIED
           MOVE DL-CUSTOMS-VALUE   TO RL-CUSTOMS-VALUE
           MOVE WS-LINE-DUTY       TO RL-LINE-DUTY
           MOVE WS-LINE-SST        TO RL-LINE-SST
           DISPLAY RESP-LINE.

       EMIT-HEADER.
           MOVE FUNCTION CURRENT-DATE TO WS-CURRENT-DATE
           MOVE WS-CURRENT-DATE(1:8)  TO WS-TS-DATE
           MOVE WS-CURRENT-DATE(9:6)  TO WS-TS-TIME

           COMPUTE WS-TOT-PAYABLE = WS-TOT-DUTY + WS-TOT-SST

           IF WS-FOUND = 'N'
               MOVE 'ER' TO RH-STATUS
           ELSE
               MOVE 'OK' TO RH-STATUS
           END-IF

           MOVE WS-ARG-REF      TO RH-DECL-REF
           MOVE WS-LINE-COUNT   TO RH-LINE-COUNT
           MOVE WS-TOT-VALUE    TO RH-TOT-VALUE
           MOVE WS-TOT-DUTY     TO RH-TOT-DUTY
           MOVE WS-TOT-SST      TO RH-TOT-SST
           MOVE WS-TOT-PAYABLE  TO RH-TOT-PAYABLE
           MOVE WS-PREF-APPLIED TO RH-PREF-APPLIED
           MOVE WS-TIMESTAMP    TO RH-CALC-TS

           DISPLAY RESP-HEADER.
