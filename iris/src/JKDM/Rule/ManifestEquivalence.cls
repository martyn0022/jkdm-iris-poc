/// JKDM SMK POC - field classification for manifest.lookup.
///
/// WHERE A DECISION MADE ELSEWHERE ARRIVES AS CONFIGURATION.
///
/// Nothing in this class decides anything. Whether a difference blocks
/// a migration is judged by the people converting the module and
/// approved by JKDM - SMK 5.7 is explicit that the architecture
/// "defines the method; it does not set the thresholds".
///
/// This class is where that approved judgement is written down so the
/// comparator applies it consistently, to every manifest, forever -
/// instead of a person re-reading a spreadsheet.
///
/// The worked reference is JKDM.Rule.DutyEquivalence. Copy its shape,
/// not its answers: a duty calculation and a manifest lookup do not
/// have the same fiscal surface.
///
/// THE DEFINITIONS
///   FISCAL   - any mismatch fails the SMK 5.7 gate. The section lists
///              the outcomes that count: duty, tax, payment, receipt,
///              exemption, refund or claim, guarantee, revenue
///              posting, declaration status and RELEASE STATUS.
///   MATERIAL - a genuine defect, but no money moves.
///   IGNORE   - expected to differ.
///
/// THREE THAT SHOULD COST YOU AN ARGUMENT
///   eta               same instant, one side UTC and one +08:00.
///                     Formatting - or a defect waiting for a
///                     downstream consumer that parses naively?
///   consignmentCount  COBOL counts records, PHP reads a stored
///                     counter that has drifted. No money moves. So?
///   statusCode        COBOL 'RL', PHP 'RELEASED'. Release status is
///                     NAMED in the 5.7 fiscal list. Does an encoding
///                     difference in a fiscal field fail the gate?
///
/// There is no answer key. If your pair agrees instantly on all
/// three, one of you has not thought about it hard enough.
Class JKDM.Rule.ManifestEquivalence Extends %RegisteredObject
{

/// Returns FISCAL | MATERIAL | IGNORE for a given field path.
ClassMethod Classify(pFieldPath As %String) As %String
{
    Set tField = $PIECE(pFieldPath, ".", $LENGTH(pFieldPath, "."))

    // Release status is named in the SMK 5.7 fiscal list, so an
    // encoding difference in it is treated as fiscal until JKDM says
    // otherwise. Erring towards blocking is the safe direction.
    If ..InList(tField, "statusCode") {
        Quit "FISCAL"
    }

    // Expected to differ. "backend" exists precisely to differ.
    If ..InList(tField, "backend,retrievedAt") {
        Quit "IGNORE"
    }

    // Everything unclassified lands here. Leaving a field in this
    // bucket is a decision too, and it is the one that quietly fails
    // your module at the gate.
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
