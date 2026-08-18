/// JKDM SMK POC - parse the COBOL fixed-width response into canonical form.
///
/// THIS CLASS IS WHY THE FABRIC EXISTS.
///
/// The COBOL core returns positional, zero-padded, implied-decimal
/// records with PIC X(35) truncated text and YYYYMMDDHHMMSS
/// timestamps. Consumers must never see that. IRIS normalises it to
/// the canonical model (SMK 4.3.5, WCO Data Model alignment) so that
/// the API contract is identical regardless of which backend served
/// the call.
///
/// If the COBOL mock returned clean JSON, this class would not need
/// to exist - and the demo would prove nothing.
Class JKDM.Util.CobolParser Extends %RegisteredObject
{

/// Header layout - see cobol/copybook and DUTYCALC.cbl RESP-HEADER
///   STATUS        X(02)   1
///   DECL-REF      X(20)   3
///   LINE-COUNT    9(03)   23
///   TOT-VALUE     9(11)V99 26
///   TOT-DUTY      9(11)V99 39
///   TOT-SST       9(11)V99 52
///   TOT-PAYABLE   9(11)V99 65
///   PREF-APPLIED  X(01)   78
///   CALC-TS       X(14)   79
ClassMethod ParseHeader(pRaw As %String) As %DynamicObject
{
    Set tObj = {}
    Set tObj.status         = $ZSTRIP($EXTRACT(pRaw, 1, 2), "<>W")
    Set tObj.declarationRef = $ZSTRIP($EXTRACT(pRaw, 3, 22), "<>W")
    Set tObj.lineCount      = +$EXTRACT(pRaw, 23, 25)
    Set tObj.totalCustomsValue = ..Implied($EXTRACT(pRaw, 26, 38), 2)
    Set tObj.totalDutyAmount   = ..Implied($EXTRACT(pRaw, 39, 51), 2)
    Set tObj.totalSstAmount    = ..Implied($EXTRACT(pRaw, 52, 64), 2)
    Set tObj.totalPayable      = ..Implied($EXTRACT(pRaw, 65, 77), 2)
    Set tObj.preferenceApplied = ($EXTRACT(pRaw, 78) = "Y")
    Set tObj.calculatedAt      = ..CobolTS($EXTRACT(pRaw, 79, 92))
    Quit tObj
}

/// Line layout - RESP-LINE
///   MARKER        X(02)   1
///   LINE-NO       9(03)   3
///   HS-CODE       X(10)   6
///   HS-DESC       X(35)   16
///   RATE-APPLIED  9(03)V9999 51
///   CUSTOMS-VALUE 9(11)V99 58
///   LINE-DUTY     9(11)V99 71
///   LINE-SST      9(11)V99 84
ClassMethod ParseLine(pRaw As %String) As %DynamicObject
{
    Set tObj = {}
    Set tObj.lineNo        = +$EXTRACT(pRaw, 3, 5)
    Set tObj.hsCode        = $ZSTRIP($EXTRACT(pRaw, 6, 15), "<>W")
    Set tObj.hsDescription = $ZSTRIP($EXTRACT(pRaw, 16, 50), "<>W")
    Set tObj.rateApplied   = ..Implied($EXTRACT(pRaw, 51, 57), 4)
    Set tObj.customsValue  = ..Implied($EXTRACT(pRaw, 58, 70), 2)
    Set tObj.lineDuty      = ..Implied($EXTRACT(pRaw, 71, 83), 2)
    Set tObj.lineSst       = ..Implied($EXTRACT(pRaw, 84, 96), 2)
    Quit tObj
}

/// Zero-padded implied-decimal string -> numeric.
/// "0000000123455" with 2 decimals -> 1234.55
ClassMethod Implied(pRaw As %String, pDecimals As %Integer) As %Decimal
{
    Set tClean = $ZSTRIP(pRaw, "<>W")
    If tClean = "" Quit 0
    Set tClean = $TRANSLATE(tClean, " ", "0")
    Quit +tClean / (10 ** pDecimals)
}

/// YYYYMMDDHHMMSS -> ISO-8601. Mainframe timestamps carry no zone;
/// assume Asia/Kuala_Lumpur. This assumption is exactly the kind of
/// thing the comparator's IGNORE/MATERIAL judgement has to settle.
ClassMethod CobolTS(pRaw As %String) As %String
{
    Set tClean = $ZSTRIP(pRaw, "<>W")
    If $LENGTH(tClean) < 14 Quit ""
    Quit $EXTRACT(tClean,1,4)_"-"_$EXTRACT(tClean,5,6)_"-"_$EXTRACT(tClean,7,8)_
         "T"_$EXTRACT(tClean,9,10)_":"_$EXTRACT(tClean,11,12)_":"_
         $EXTRACT(tClean,13,14)_"+08:00"
}

/// Full response -> canonical object matching the PHP shape.
ClassMethod ToCanonical(pHeaderRaw As %String, pLinesRaw As %DynamicArray) As %DynamicObject
{
    Set tObj = ..ParseHeader(pHeaderRaw)
    Set tLines = []
    Set tIter = pLinesRaw.%GetIterator()
    While tIter.%GetNext(.tKey, .tVal) {
        Do tLines.%Push(..ParseLine(tVal))
    }
    Set tObj.lines = tLines
    Set tObj.backend = "COBOL"
    Quit tObj
}

}
