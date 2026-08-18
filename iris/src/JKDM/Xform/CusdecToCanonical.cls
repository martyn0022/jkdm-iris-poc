/// JKDM SMK POC - UN/EDIFACT CUSDEC -> canonical customs declaration.
///
/// This is the "legacy EDIFACT translator" the SMK architecture
/// retires (2.7: the TO-BE fabric replaces external translators,
/// the ESB and point-to-point links). The translation does not
/// disappear - it moves inside the fabric, where it is versioned,
/// traced and testable.
///
/// WHY THIS IS OBJECTSCRIPT AND NOT A GRAPHICAL DTL
/// ------------------------------------------------
/// A graphical DTL maps NAMED source fields. Names come from the
/// message schema, and the D96A schema is not in the product - see
/// JKDM.Util.EdifactNav. Load the SEF schema and this becomes a DTL
/// that a business analyst can read and edit, which is the form you
/// want for sixty partner message variants.
///
/// Say this plainly in the walkthrough. "We would use a DTL here, and
/// here is exactly what it costs to get there" is a stronger position
/// than showing a DTL that only works because the demo data is tame.
Class JKDM.Xform.CusdecToCanonical Extends %RegisteredObject
{

/// Map one CUSDEC message document onto the canonical model.
ClassMethod Transform(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pPartnerID As %String,
    pSourceFile As %String,
    Output pCanonical As JKDM.Msg.CanonicalDeclaration) As %Status
{
    Set tSC = $$$OK
    Try {
        Set pCanonical = ##class(JKDM.Msg.CanonicalDeclaration).%New()

        // --- header ------------------------------------------------
        // BGM: 1 = document type code, 2 = document reference
        Set pCanonical.DeclarationRef  = ##class(JKDM.Util.EdifactNav).Get(pDoc, "BGM", 2)
        Set pCanonical.DeclarationType = ..DeclTypeFromCode(##class(JKDM.Util.EdifactNav).Get(pDoc, "BGM", 1))

        // DTM+137 = document/message date-time
        Set pCanonical.LodgementDT = ##class(JKDM.Util.EdifactNav).DateTime(
            ##class(JKDM.Util.EdifactNav).Get(pDoc, "DTM", 1, 2))

        // NAD parties by role qualifier
        Set pCanonical.DeclarantTIN = ##class(JKDM.Util.EdifactNav).Party(pDoc, "DT")
        Set pCanonical.ConsignorTIN = ##class(JKDM.Util.EdifactNav).Party(pDoc, "CZ")
        Set pCanonical.ConsigneeTIN = ##class(JKDM.Util.EdifactNav).Party(pDoc, "CN")

        // LOC+16 = place of clearance
        Set pCanonical.PortOfEntry = ##class(JKDM.Util.EdifactNav).Get(pDoc, "LOC", 2, 1)

        // TDT = transport details, element 3 = mode of transport
        Set pCanonical.TransportMode = ##class(JKDM.Util.EdifactNav).Get(pDoc, "TDT", 3)

        // CUX+2 = reference currency
        Set pCanonical.CurrencyCode = ##class(JKDM.Util.EdifactNav).Get(pDoc, "CUX", 1, 2)
        Set:pCanonical.CurrencyCode="" pCanonical.CurrencyCode = "MYR"

        // ALI = preference / origin claim. Element 1 is the country of
        // origin, element 4 the special-condition (FTA) code.
        Set pCanonical.OriginCountry = ##class(JKDM.Util.EdifactNav).Get(pDoc, "ALI", 1)
        Set pCanonical.FTAClaimed    = ##class(JKDM.Util.EdifactNav).Get(pDoc, "ALI", 4)

        // PCD+12 = percentage, used here for regional value content.
        Set tPct = ##class(JKDM.Util.EdifactNav).Get(pDoc, "PCD", 1, 2)
        Set:tPct'="" pCanonical.LocalContentPct = +tPct

        Set pCanonical.PartnerID         = pPartnerID
        Set pCanonical.SourceMessageType = "CUSDEC"
        Set pCanonical.SourceFileRef     = pSourceFile

        // --- commodity lines ---------------------------------------
        Do ..MapLines(pDoc, pCanonical)

        Set tTotal = 0
        For i = 1:1:pCanonical.CommodityLines.Count() {
            Set tTotal = tTotal + pCanonical.CommodityLines.GetAt(i).LineValue
        }
        Set pCanonical.TotalCustomsValue = tTotal
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Walk the LIN groups. A CUSDEC line group is a LIN segment followed
/// by its qualifying segments (IMD description, QTY quantity, MOA
/// amount) up to the next LIN or the end of the message. There is no
/// nesting to rely on without a schema, so the walk is positional.
ClassMethod MapLines(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pCanonical As JKDM.Msg.CanonicalDeclaration)
{
    Set tLine = ""

    For i = 1:1:pDoc.SegCount {
        Set tTag = ##class(JKDM.Util.EdifactNav).TagAt(pDoc, i)

        If tTag = "LIN" {
            // Close the previous group before starting a new one.
            If $IsObject(tLine) {
                Do pCanonical.CommodityLines.Insert(tLine)
            }
            Set tLine = ##class(JKDM.Msg.CanonicalLine).%New()
            Set tLine.LineNo = +##class(JKDM.Util.EdifactNav).GetAt(pDoc, i, 1)
            Set tLine.HSCode = ##class(JKDM.Util.EdifactNav).GetAt(pDoc, i, 3, 1)
            Continue
        }

        Continue:'$IsObject(tLine)

        If tTag = "IMD" {
            Set tLine.Description = ##class(JKDM.Util.EdifactNav).GetAt(pDoc, i, 3, 4)
        }
        ElseIf tTag = "QTY" {
            Set tLine.Qty = +##class(JKDM.Util.EdifactNav).GetAt(pDoc, i, 1, 2)
            Set tLine.UOM = ##class(JKDM.Util.EdifactNav).GetAt(pDoc, i, 1, 3)
        }
        ElseIf tTag = "MOA" {
            // MOA+38 = invoice/customs value for the line
            Set tLine.LineValue = +##class(JKDM.Util.EdifactNav).GetAt(pDoc, i, 1, 2)
        }
    }

    If $IsObject(tLine) {
        Do pCanonical.CommodityLines.Insert(tLine)
    }
}

/// UN/EDIFACT 1001 document name codes -> JKDM declaration types.
/// The real mapping is longer; this covers the POC message set.
ClassMethod DeclTypeFromCode(pCode As %String) As %String
{
    Quit $CASE(pCode, 929:"K1", 830:"K2", 933:"K1", 935:"K3", :"K1")
}

}
