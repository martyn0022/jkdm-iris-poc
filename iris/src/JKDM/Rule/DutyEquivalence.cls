/// JKDM SMK POC - field classification for duty.calculate.
///
/// The FISCAL list below is taken VERBATIM from SMK 5.7's definition
/// of fiscal equivalence: "duty, tax, payment, receipt, exemption,
/// refund or claim, guarantee, revenue posting, declaration status
/// and release status all match within the approved tolerance."
///
/// This is the worked reference attendees copy for the manifest
/// operation in the hands-on exercise. Deciding which fields belong
/// in which bucket is an architecture judgement, not a coding task -
/// and it is the judgement the migration factory makes hundreds of
/// times.
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

/// Tolerance for numeric FISCAL fields. SMK 5.7 is explicit that the
/// architecture "defines the method; it does not set the thresholds"
/// - JKDM approves the final tolerance before cutover.
///
/// Zero here on purpose: for the demo, a one-cent difference must
/// register as a FISCAL_DIFF. Changing this to 0.01 and re-running is
/// a good five-minute discussion about who owns that decision.
ClassMethod Tolerance(pFieldPath As %String) As %Decimal
{
    Quit 0
}

ClassMethod InList(pValue As %String, pList As %String) As %Boolean
{
    Quit ","_pList_"," [ (","_pValue_",")
}

}
