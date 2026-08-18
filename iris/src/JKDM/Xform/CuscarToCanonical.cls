/// UN/EDIFACT CUSCAR (vessel manifest) -> canonical customs message.
///
/// ############################################################
/// ##  CLASSROOM LAB - ONE BLOCK TO PASTE, MARKED BELOW      ##
/// ############################################################
///
/// Everything else is written. Find the marked block and paste the
/// four lines from the lab sheet into it. Nothing else changes.
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

        // ---- constants, already done ---------------------------
        Set pCanonical.DeclarationType   = "K8"
        Set pCanonical.PartnerID         = pPartnerID
        Set pCanonical.SourceMessageType = "CUSCAR"
        Set pCanonical.SourceFileRef     = pSourceFile
        Set pCanonical.CurrencyCode      = "MYR"
        Set pCanonical.ConsignorTIN      = ##class(JKDM.Util.EdifactNav).Party(pDoc, "CA")


        // ========================================================
        //   PASTE THE FOUR LINES FROM THE LAB SHEET HERE
        // ========================================================
        Set pCanonical.ManifestRef  = ##class(JKDM.Util.EdifactNav).Get(pDoc, "BGM", 2)
        Set pCanonical.VesselID     = ##class(JKDM.Util.EdifactNav).Get(pDoc, "TDT", 9, 1)
        Set pCanonical.PortOfEntry  = ##class(JKDM.Util.EdifactNav).Get(pDoc, "LOC", 2, 1)
        Set pCanonical.ETA          = ##class(JKDM.Util.EdifactNav).DateTime(##class(JKDM.Util.EdifactNav).Get(pDoc, "DTM", 1, 2, 2))

        // ========================================================


        // ---- already done -------------------------------------
        // The audit trail keys on DeclarationRef, so it takes the
        // manifest reference the pasted block found.
        Set pCanonical.DeclarationRef = pCanonical.ManifestRef
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

}
