/// JKDM SMK POC - parse the COBOL manifest response into canonical form.
///
/// Companion to JKDM.Util.CobolParser. Same job, different record.
///
/// ONE DELIBERATE OMISSION - READ BEFORE THE EXERCISE
/// --------------------------------------------------
/// vesselName is NOT trimmed. The COBOL field is PIC X(30) and comes
/// back space padded; this parser passes the padding straight through.
///
/// That is a realistic parser bug, and it is left in on purpose. The
/// comparator will flag it, and the room gets a genuinely useful
/// argument out of it: is the right fix to classify the difference, or
/// to fix the parser? (It is to fix the parser. But notice that the
/// comparator is what told you the parser was wrong.)
Class JKDM.Util.ManifestParser Extends %RegisteredObject
{

/// Header layout - see cobol/src/MANIFEST.cbl RESP-HEADER
///   STATUS       X(02)    1
///   REF          X(24)    3
///   VESSEL-ID    X(16)   27
///   VESSEL-NAME  X(30)   43
///   VOYAGE       X(12)   73
///   CARRIER-TIN  X(16)   85
///   PORT         X(08)  101
///   ETA          X(14)  109
///   STATUS-CODE  X(02)  123
///   CONS-COUNT   9(03)  125
///   GROSS-KG     9(11)V99 128
ClassMethod ParseHeader(pRaw As %String) As %DynamicObject
{
    Set tObj = {}
    Set tObj.status           = $ZSTRIP($EXTRACT(pRaw, 1, 2), "<>W")
    Set tObj.manifestRef      = $ZSTRIP($EXTRACT(pRaw, 3, 26), "<>W")
    Set tObj.vesselId         = $ZSTRIP($EXTRACT(pRaw, 27, 42), "<>W")
    // Deliberately unstripped - see the class comment.
    Set tObj.vesselName       = $EXTRACT(pRaw, 43, 72)
    Set tObj.voyageNumber     = $ZSTRIP($EXTRACT(pRaw, 73, 84), "<>W")
    Set tObj.carrierTin       = $ZSTRIP($EXTRACT(pRaw, 85, 100), "<>W")
    Set tObj.portOfDischarge  = $ZSTRIP($EXTRACT(pRaw, 101, 108), "<>W")
    Set tObj.eta              = ##class(JKDM.Util.CobolParser).CobolTS($EXTRACT(pRaw, 109, 122))
    Set tObj.statusCode       = $ZSTRIP($EXTRACT(pRaw, 123, 124), "<>W")
    Set tObj.consignmentCount = +$EXTRACT(pRaw, 125, 127)
    Set tObj.totalGrossKg     = ##class(JKDM.Util.CobolParser).Implied($EXTRACT(pRaw, 128, 140), 2)
    Quit tObj
}

/// Line layout - RESP-LINE
///   MARKER      X(02)   1
///   LINE-NO     9(03)   3
///   CONS-REF    X(24)   6
///   CONTAINERS  9(05)  30
///   GROSS-KG    9(11)V99 35
///   DESC        X(40)  48
ClassMethod ParseLine(pRaw As %String) As %DynamicObject
{
    Set tObj = {}
    Set tObj.lineNo         = +$EXTRACT(pRaw, 3, 5)
    Set tObj.consignmentRef = $ZSTRIP($EXTRACT(pRaw, 6, 29), "<>W")
    Set tObj.containerCount = +$EXTRACT(pRaw, 30, 34)
    Set tObj.grossKg        = ##class(JKDM.Util.CobolParser).Implied($EXTRACT(pRaw, 35, 47), 2)
    Set tObj.description    = $ZSTRIP($EXTRACT(pRaw, 48, 87), "<>W")
    Quit tObj
}

ClassMethod ToCanonical(pHeaderRaw As %String, pLinesRaw As %DynamicArray) As %DynamicObject
{
    Set tObj = ..ParseHeader(pHeaderRaw)
    Set tLines = []
    Set tIter = pLinesRaw.%GetIterator()
    While tIter.%GetNext(.tKey, .tVal) {
        Do tLines.%Push(..ParseLine(tVal))
    }
    Set tObj.consignments = tLines
    Set tObj.backend = "COBOL"
    Quit tObj
}

}
