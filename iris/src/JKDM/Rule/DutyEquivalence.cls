/// Field classification for duty.calculate.
///
/// The FISCAL list below is taken verbatim from SMK 5.7's definition of
/// fiscal equivalence: "duty, tax, payment, receipt, exemption, refund
/// or claim, guarantee, revenue posting, declaration status and release
/// status all match within the approved tolerance."
///
/// Which fields belong in which bucket is an architecture judgement
/// rather than a coding task. This class is the worked reference for
/// the manifest classification.
Class JKDM.Rule.DutyEquivalence Extends %RegisteredObject
{

/// Returns FISCAL | MATERIAL | IGNORE for a given field path.
ClassMethod Classify(pFieldPath As %String) As %String
{
    Set tField = $PIECE(pFieldPath, ".", $LENGTH(pFieldPath, "."))

    // --- FISCAL: any mismatch fails the SMK 5.7 gate ---------------
    If ..InList(tField,
        "totalDutyAmount,totalSstAmount,totalPayable,totalCustomsValue,"_
        "lineDuty,lineSst,rateApplied,preferenceApplied,status") {
        Quit "FISCAL"
    }

    // --- IGNORE: expected to differ --------------------------------
    // Format, precision presentation, timestamps, correlation IDs.
    If ..InList(tField,
        "calculatedAt,backend,requestId,traceId,sessionId") {
        Quit "IGNORE"
    }

    // --- MATERIAL: a defect, but not a monetary one ----------------
    // hsDescription lands here: COBOL truncates at PIC X(35),
    // Postgres holds VARCHAR(120). Real difference, no fiscal impact,
    // but downstream consumers may be relying on the full text.
    Quit "MATERIAL"
}

/// Tolerance for numeric FISCAL fields. SMK 5.7 states that the
/// architecture "defines the method; it does not set the thresholds" -
/// JKDM approves the final tolerance before cutover.
///
/// Zero here, so a one-cent difference registers as a FISCAL_DIFF.
ClassMethod Tolerance(pFieldPath As %String) As %Decimal
{
    Quit 0
}

ClassMethod InList(pValue As %String, pList As %String) As %Boolean
{
    Quit ","_pList_"," [ (","_pValue_",")
}

}
