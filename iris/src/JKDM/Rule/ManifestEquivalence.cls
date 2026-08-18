/// Field classification for manifest.lookup.
///
/// This class decides nothing. Whether a difference blocks a migration
/// is judged by the people converting the module and approved by JKDM;
/// SMK 5.7 states that the architecture "defines the method; it does
/// not set the thresholds". The approved judgement is recorded here so
/// the comparator applies it consistently to every manifest.
///
/// JKDM.Rule.DutyEquivalence is the worked reference. Its shape
/// transfers; its answers do not, since a duty calculation and a
/// manifest lookup have different fiscal surfaces.
///
///   FISCAL   - any mismatch fails the SMK 5.7 gate. The section names
///              duty, tax, payment, receipt, exemption, refund or
///              claim, guarantee, revenue posting, declaration status
///              and release status.
///   MATERIAL - a genuine defect, but no money moves.
///   IGNORE   - expected to differ.
///
/// Three classifications worth reviewing with JKDM:
///   eta               the same instant, one side UTC and one +08:00.
///                     Formatting, or a defect for a consumer that
///                     parses naively?
///   consignmentCount  COBOL counts records; PHP reads a stored counter
///                     that has drifted. No money moves.
///   statusCode        COBOL 'RL', PHP 'RELEASED'. Release status is
///                     named in the 5.7 fiscal list, so an encoding
///                     difference may or may not fail the gate.
Class JKDM.Rule.ManifestEquivalence Extends %RegisteredObject
{

/// Returns FISCAL | MATERIAL | IGNORE for a given field path.
ClassMethod Classify(pFieldPath As %String) As %String
{
    Set tField = $PIECE(pFieldPath, ".", $LENGTH(pFieldPath, "."))

    // Release status is named in the SMK 5.7 fiscal list, so an
    // encoding difference is treated as fiscal until JKDM decides
    // otherwise. Blocking is the safe default.
    If ..InList(tField, "statusCode") {
        Quit "FISCAL"
    }

    // Expected to differ. "backend" exists precisely to differ.
    If ..InList(tField, "backend,retrievedAt") {
        Quit "IGNORE"
    }

    // Everything unclassified lands here. Leaving a field in this
    // bucket is itself a decision, and the one most likely to fail a
    // module at the gate.
    Quit "MATERIAL"
}

/// Tolerance for numeric FISCAL fields.
///
/// SMK 5.7 defines the method and explicitly does NOT set the
/// thresholds - JKDM approves those before cutover. Zero here means
/// any difference at all registers.
ClassMethod Tolerance(pFieldPath As %String) As %Decimal
{
    Quit 0
}

ClassMethod InList(pValue As %String, pList As %String) As %Boolean
{
    Quit ","_pList_"," [ (","_pValue_",")
}

}
