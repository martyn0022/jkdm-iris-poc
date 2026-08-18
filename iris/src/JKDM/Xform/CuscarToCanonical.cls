/// UN/EDIFACT CUSCAR (vessel manifest) -> canonical customs message.
///
/// ############################################################
/// ##   CLASSROOM EXERCISE - FOUR LINES TO FILL IN           ##
/// ############################################################
///
/// Most of this is written. Find the four blocks marked TODO and fill
/// in the one line each needs. Six lines above them are already done -
/// those are your examples, and every answer looks like one of them.
///
/// HOW TO READ AN EDIFACT SEGMENT
/// ------------------------------
/// A segment is a tag, then ELEMENTS separated by + , and an element
/// may hold COMPONENTS separated by : - so in
///
///     BGM+85+MANIFEST-2026-0041+9
///      ^   ^          ^
///     tag  e1        e2
///
/// the manifest reference is element 2 of BGM, and you ask like this:
///
///     ##class(JKDM.Util.EdifactNav).Get(pDoc, "BGM", 2)
///
/// When the element has components, add a third number:
///
///     TDT+20+VOY-8841+1++CARRIER:172:20++++9V-8841:103:11:MV BINTANG SATU
///                                              ^                 ^
///                                            e9 c1             e9 c4
///
///     ##class(JKDM.Util.EdifactNav).Get(pDoc, "TDT", 9, 4)
///         -> MV BINTANG SATU
///
/// And when the same tag appears more than once, add a fourth number
/// saying which one you want:
///
///     ##class(JKDM.Util.EdifactNav).Get(pDoc, "DTM", 1, 2, 2)
///                                                       ^
///                                           the SECOND DTM segment
Class JKDM.Xform.CuscarToCanonical Extends %RegisteredObject
{

ClassMethod Transform(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pPartnerID As %String,
    pSourceFile As %String,
    Output pCanonical As JKDM.Msg.CanonicalDeclaration) As %Status
{
    Set tSC = $$$OK
    Try {
        Set pCanonical = ##class(JKDM.Msg.CanonicalDeclaration).%New()

        // ---- already done for you - your examples --------------
        Set pCanonical.DeclarationType   = "K8"
        Set pCanonical.PartnerID         = pPartnerID
        Set pCanonical.SourceMessageType = "CUSCAR"
        Set pCanonical.SourceFileRef     = pSourceFile
        Set pCanonical.CurrencyCode      = "MYR"

        // The carrier is the NAD party carrying the CA qualifier.
        Set pCanonical.ConsignorTIN = ##class(JKDM.Util.EdifactNav).Party(pDoc, "CA")


        // ---- TODO 1 --------------------------------------------
        // The manifest reference: element 2 of the BGM segment.
        // The class comment above shows exactly this one.
        //
        // Set pCanonical.ManifestRef = ...


        // ---- TODO 2 --------------------------------------------
        // The vessel identifier: element 9, COMPONENT 1, of TDT.
        // The comment above reaches component 4 of that same element;
        // you want component 1.
        //
        // Set pCanonical.VesselID = ...


        // ---- TODO 3 --------------------------------------------
        // The port of discharge: element 2, component 1, of LOC.
        //
        // Set pCanonical.PortOfEntry = ...


        // ---- TODO 4 --------------------------------------------
        // The estimated arrival: element 1, component 2, of the SECOND
        // DTM segment - the first DTM is the message date.
        //
        // This one is wrapped in DateTime() to turn 202608200600 into a
        // real timestamp. Copy it as written; it is the only awkward one:
        //
        // Set pCanonical.ETA = ##class(JKDM.Util.EdifactNav).DateTime(##class(JKDM.Util.EdifactNav).Get(pDoc, "DTM", 1, 2, 2))


        // ---- nothing below here needs changing -----------------
        // The audit trail keys on DeclarationRef, so it gets the
        // manifest reference you found in TODO 1.
        Set pCanonical.DeclarationRef = pCanonical.ManifestRef
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
