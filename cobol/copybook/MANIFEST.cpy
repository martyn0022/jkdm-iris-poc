      *****************************************************************
      * MANIFEST - denormalised vessel manifest consignment record    *
      *                                                               *
      * Same discipline as DECLLINE.cpy: the generator derives this    *
      * file from the Postgres manifest tables, so the flat file and   *
      * the relational schema are two representations of one dataset.  *
      *                                                               *
      * NOTE: MF-VESSEL-NAME is PIC X(30) and MF-DESC is PIC X(40).    *
      * Both are space padded on the way out. The Postgres columns     *
      * are VARCHAR(60) and VARCHAR(120). That padding and truncation  *
      * is real, and it is what the workshop exercise has to classify. *
      *****************************************************************
       01  MANIFEST-REC.
           05  MF-REF               PIC X(24).
           05  MF-VESSEL-ID         PIC X(16).
           05  MF-VESSEL-NAME       PIC X(30).
           05  MF-VOYAGE            PIC X(12).
           05  MF-CARRIER-TIN       PIC X(16).
           05  MF-PORT              PIC X(08).
           05  MF-ETA               PIC X(14).
           05  MF-STATUS            PIC X(02).
           05  MF-LINE-NO           PIC 9(03).
           05  MF-CONS-REF          PIC X(24).
           05  MF-CONTAINERS        PIC 9(05).
           05  MF-GROSS-KG          PIC 9(11)V99.
           05  MF-DESC              PIC X(40).
