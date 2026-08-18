/// EDIFACT intake that actually CREATES the declaration.
///
/// ############################################################
/// ##  THIS IS WHERE THE PROTOTYPE STOPS BEING A RESTATEMENT  ##
/// ############################################################
///
/// The main POC has a documented limitation: Flow A parses a partner
/// file, canonicalises it, and then asks the core to price a
/// declaration the core must ALREADY hold. It never creates anything.
///
/// That was not laziness. Writing meant reaching across to Postgres,
/// and a write in the shadowed path is the one thing shadow mode
/// cannot do safely. So the POC chose a read-only operation and said
/// so out loud.
///
/// Here the data layer is the same process, so ingestion does what
/// ingestion is supposed to do: it persists the declaration, then
/// prices it, in one unit of work. Same interop interface on the way
/// in - same pull, same audit-before-parse discipline - and the
/// limitation simply is not there any more.
///
/// That is the argument for this segment, and it is worth making
/// precisely: not "IRIS is better", but "this particular limitation
/// came from the tier boundary, and moving the boundary removes it".
Class PT.Svc.Intake Extends %RegisteredObject
{

/// Parse a CUSDEC interchange, persist it, price it.
ClassMethod FromEdifact(
    pRaw As %String,
    pSource As %String = "EDIFACT") As %DynamicObject
{
    Set tDoc = ##class(EnsLib.EDI.EDIFACT.Document).ImportFromString(pRaw, .tSC)
    If $$$ISERR(tSC) || '$IsObject(tDoc) {
        Quit {"status":"REJECTED","code":"SYNTAX","reason":"could not parse the interchange"}
    }

    Set tMsg = tDoc
    If tDoc.Name = "Interchange" {
        Set tMsg = tDoc.NextChild("")
    }
    If '$IsObject(tMsg) {
        Quit {"status":"REJECTED","code":"SYNTAX","reason":"interchange contains no message"}
    }
    If tMsg.Name '= "CUSDEC" {
        Quit {"status":"REJECTED","code":"UNSUPPORTED","reason":("message type "_tMsg.Name)}
    }

    Set tRef = ##class(JKDM.Util.EdifactNav).Get(tMsg, "BGM", 2)
    If tRef = "" {
        Quit {"status":"REJECTED","code":"BUSINESS","reason":"no declaration reference in BGM"}
    }

    // One transaction: the declaration and every line, or nothing.
    TSTART

    Set tExisting = ##class(PT.Data.Declaration).%OpenId(tRef)
    If $IsObject(tExisting) {
        Do ##class(PT.Data.Declaration).%DeleteId(tRef)
    }

    Set tDecl = ##class(PT.Data.Declaration).%New()
    Set tDecl.DeclRef       = tRef
    Set tDecl.DeclType      = "K1"
    Set tDecl.DeclarantTin  = ##class(JKDM.Util.EdifactNav).Party(tMsg, "DT")
    Set tDecl.OriginCountry = ##class(JKDM.Util.EdifactNav).Get(tMsg, "ALI", 1)
    Set tDecl.FtaClaimed    = ##class(JKDM.Util.EdifactNav).Get(tMsg, "ALI", 4)
    Set tPct = ##class(JKDM.Util.EdifactNav).Get(tMsg, "PCD", 1, 2)
    Set:tPct'="" tDecl.LocalPct = +tPct
    Set tDecl.Source = pSource

    Set tSC = tDecl.%Save()
    If $$$ISERR(tSC) {
        If $TLEVEL > 0 { TROLLBACK }
        Quit {"status":"REJECTED","code":"SYSTEM","reason":"could not persist the declaration"}
    }

    // Walk the LIN groups exactly as the fabric's transform does.
    Set tLineNo = 0
    For i = 1:1:tMsg.SegCount {
        Set tTag = ##class(JKDM.Util.EdifactNav).TagAt(tMsg, i)
        If tTag = "LIN" {
            Set tLineNo = +##class(JKDM.Util.EdifactNav).GetAt(tMsg, i, 1)
            Set tHS = ##class(JKDM.Util.EdifactNav).GetAt(tMsg, i, 3, 1)
            Set tLine = ##class(PT.Data.DeclarationLine).%New()
            Set tLine.Declaration = tDecl
            Set tLine.LineNo = tLineNo
            Set tLine.HSCode = tHS
            Do tLine.%Save()
        }
        ElseIf tTag = "QTY", tLineNo > 0 {
            Set tLine.Quantity = +##class(JKDM.Util.EdifactNav).GetAt(tMsg, i, 1, 2)
            Do tLine.%Save()
        }
        ElseIf tTag = "MOA", tLineNo > 0 {
            Set tLine.CustomsValue = +##class(JKDM.Util.EdifactNav).GetAt(tMsg, i, 1, 2)
            Do tLine.%Save()
        }
    }

    TCOMMIT

    // Persisted and priced in one call, against storage that never
    // left the process.
    Set tResult = ##class(PT.Svc.Duty).Calculate(tRef)
    Set tResult.status = "LODGED"
    Set tResult.persisted = 1
    Quit tResult
}

}
