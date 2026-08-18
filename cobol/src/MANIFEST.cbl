       IDENTIFICATION DIVISION.
       PROGRAM-ID. MANIFEST.
      *****************************************************************
      * JKDM SMK POC - vessel manifest lookup                         *
      *                                                               *
      * The read-only counterpart to DUTYCALC. No arithmetic that      *
      * moves money, which is exactly why it makes a good exercise:    *
      * attendees have to decide what "equivalent" means when almost   *
      * nothing on the record is obviously fiscal.                     *
      *                                                               *
      * COUNTING NOTE                                                  *
      * This program COUNTS the consignment records it reads. The PHP  *
      * implementation reads a denormalised counter column instead.    *
      * On a manifest where that counter has drifted, the two          *
      * disagree - which is a genuine and very common defect, not a    *
      * planted one.                                                   *
      *                                                               *
      * Usage: MANIFEST <manifest-reference>                           *
      *****************************************************************
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT MAN-FILE ASSIGN TO WS-FILE-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  MAN-FILE.
       COPY "MANIFEST.cpy".

       WORKING-STORAGE SECTION.

       01  WS-FILE-PATH             PIC X(255).
       01  WS-FILE-STATUS           PIC XX.
       01  WS-EOF                   PIC X VALUE 'N'.
       01  WS-ARG-REF               PIC X(24).
       01  WS-DATA-DIR              PIC X(200).
       01  WS-FOUND                 PIC X VALUE 'N'.

       01  WS-ACC.
           05  WS-CONS-COUNT        PIC 9(03)     VALUE ZERO.
           05  WS-TOT-GROSS         PIC S9(11)V99 COMP-3 VALUE ZERO.

       01  WS-HDR.
           05  WS-H-VESSEL-ID       PIC X(16).
           05  WS-H-VESSEL-NAME     PIC X(30).
           05  WS-H-VOYAGE          PIC X(12).
           05  WS-H-CARRIER         PIC X(16).
           05  WS-H-PORT            PIC X(08).
           05  WS-H-ETA             PIC X(14).
           05  WS-H-STATUS          PIC X(02).

       01  RESP-HEADER.
           05  RH-STATUS            PIC X(02).
           05  RH-REF               PIC X(24).
           05  RH-VESSEL-ID         PIC X(16).
           05  RH-VESSEL-NAME       PIC X(30).
           05  RH-VOYAGE            PIC X(12).
           05  RH-CARRIER-TIN       PIC X(16).
           05  RH-PORT              PIC X(08).
           05  RH-ETA               PIC X(14).
           05  RH-STATUS-CODE       PIC X(02).
           05  RH-CONS-COUNT        PIC 9(03).
           05  RH-GROSS-KG          PIC 9(11)V99.

       01  RESP-LINE.
           05  RL-MARKER            PIC X(02) VALUE 'LN'.
           05  RL-LINE-NO           PIC 9(03).
           05  RL-CONS-REF          PIC X(24).
           05  RL-CONTAINERS        PIC 9(05).
           05  RL-GROSS-KG          PIC 9(11)V99.
           05  RL-DESC              PIC X(40).

       PROCEDURE DIVISION.

       MAIN-PARA.
           ACCEPT WS-ARG-REF FROM COMMAND-LINE
           IF WS-ARG-REF = SPACES
               DISPLAY 'ERno manifest reference supplied'
               STOP RUN
           END-IF

           ACCEPT WS-DATA-DIR FROM ENVIRONMENT "COBOL_DATA_DIR"
           IF WS-DATA-DIR = SPACES
               MOVE '/data' TO WS-DATA-DIR
           END-IF
           STRING FUNCTION TRIM(WS-DATA-DIR) '/manifest.dat'
               DELIMITED BY SIZE INTO WS-FILE-PATH
           END-STRING

           PERFORM PROCESS-FILE
           PERFORM EMIT-HEADER
           STOP RUN.

       PROCESS-FILE.
           OPEN INPUT MAN-FILE
           IF WS-FILE-STATUS NOT = '00'
               DISPLAY 'ERcannot open ' FUNCTION TRIM(WS-FILE-PATH)
               STOP RUN
           END-IF

           PERFORM UNTIL WS-EOF = 'Y'
               READ MAN-FILE
                   AT END
                       MOVE 'Y' TO WS-EOF
                   NOT AT END
                       IF MF-REF = WS-ARG-REF
                           MOVE 'Y' TO WS-FOUND
                           PERFORM TAKE-LINE
                       END-IF
               END-READ
           END-PERFORM

           CLOSE MAN-FILE.

       TAKE-LINE.
           MOVE MF-VESSEL-ID    TO WS-H-VESSEL-ID
           MOVE MF-VESSEL-NAME  TO WS-H-VESSEL-NAME
           MOVE MF-VOYAGE       TO WS-H-VOYAGE
           MOVE MF-CARRIER-TIN  TO WS-H-CARRIER
           MOVE MF-PORT         TO WS-H-PORT
           MOVE MF-ETA          TO WS-H-ETA
           MOVE MF-STATUS       TO WS-H-STATUS

           ADD 1                TO WS-CONS-COUNT
           ADD MF-GROSS-KG      TO WS-TOT-GROSS

           MOVE MF-LINE-NO      TO RL-LINE-NO
           MOVE MF-CONS-REF     TO RL-CONS-REF
           MOVE MF-CONTAINERS   TO RL-CONTAINERS
           MOVE MF-GROSS-KG     TO RL-GROSS-KG
           MOVE MF-DESC         TO RL-DESC
           DISPLAY RESP-LINE.

       EMIT-HEADER.
           IF WS-FOUND = 'N'
               MOVE 'ER' TO RH-STATUS
           ELSE
               MOVE 'OK' TO RH-STATUS
           END-IF

           MOVE WS-ARG-REF       TO RH-REF
           MOVE WS-H-VESSEL-ID   TO RH-VESSEL-ID
           MOVE WS-H-VESSEL-NAME TO RH-VESSEL-NAME
           MOVE WS-H-VOYAGE      TO RH-VOYAGE
           MOVE WS-H-CARRIER     TO RH-CARRIER-TIN
           MOVE WS-H-PORT        TO RH-PORT
           MOVE WS-H-ETA         TO RH-ETA
           MOVE WS-H-STATUS      TO RH-STATUS-CODE
           MOVE WS-CONS-COUNT    TO RH-CONS-COUNT
           MOVE WS-TOT-GROSS     TO RH-GROSS-KG

           DISPLAY RESP-HEADER.
