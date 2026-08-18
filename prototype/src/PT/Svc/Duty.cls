/// Duty and tax calculation, running inside the database.
///
/// WHAT TO NOTICE, AND WHAT NOT TO CLAIM
/// -------------------------------------
/// Notice: there is no connection string, no query builder, no result
/// set to marshal, and no network hop. The code walks objects that are
/// already in the same process as their storage.
///
/// Do NOT claim this is "faster than Laravel" from a demo of six
/// declarations. The honest claim is narrower and stronger: there is
/// one less tier to operate, and no mapping layer that can drift.
///
/// ROUNDING - THE PART THAT MATTERS
/// --------------------------------
/// This rounds each line to two decimals before accumulating, which is
/// what the COBOL core does. That is a deliberate decision to match the
/// fiscal system of record, not an accident of the language.
///
/// The tender's PHP sums at full precision and rounds once, which
/// differs by a cent on a seven-line declaration. Neither is "wrong" in
/// isolation - but only one of them agrees with the system that has
/// been posting revenue for twenty years, and agreeing with that is the
/// whole job.
Class PT.Svc.Duty Extends %RegisteredObject
{

ClassMethod Calculate(pRef As %String) As %DynamicObject
{
    Set tDecl = ##class(PT.Data.Declaration).%OpenId(pRef)
    If '$IsObject(tDecl) {
        Quit {"status":"NOT_FOUND","declarationRef":(pRef)}
    }

    Set tTotalDuty = 0, tTotalSst = 0, tTotalValue = 0
    Set tPrefApplied = 0
    Set tLines = []

    For i = 1:1:tDecl.Lines.Count() {
        Set tLine = tDecl.Lines.GetAt(i)
        Set tTariff = ##class(PT.Data.TariffRate).%OpenId(tLine.HSCode)
        Continue:'$IsObject(tTariff)

        Set tRate = tTariff.DutyRate

        // Preference applies at or above the threshold - the same
        // boundary the COBOL uses.
        Set tFta = ##class(PT.Data.FtaRule).Find(tDecl.FtaClaimed, tLine.HSCode, tDecl.OriginCountry)
        If $IsObject(tFta), tDecl.LocalPct '= "", tDecl.LocalPct >= tFta.MinLocalPct {
            Set tRate = tFta.PrefRate
            Set tPrefApplied = 1
        }

        // Round per line, then accumulate. Matches the fiscal core.
        Set tLineDuty = $NUMBER(tLine.CustomsValue * tRate, 2)
        Set tLineSst  = $NUMBER((tLine.CustomsValue + tLineDuty) * tTariff.SstRate, 2)

        Set tTotalDuty  = tTotalDuty + tLineDuty
        Set tTotalSst   = tTotalSst + tLineSst
        Set tTotalValue = tTotalValue + tLine.CustomsValue

        Do tLines.%Push({
            "lineNo": (tLine.LineNo),
            "hsCode": (tLine.HSCode),
            "hsDescription": (tTariff.Description),
            "rateApplied": (tRate),
            "customsValue": (tLine.CustomsValue),
            "lineDuty": (tLineDuty),
            "lineSst": (tLineSst)
        })
    }

    Quit {
        "status": "OK",
        "declarationRef": (tDecl.DeclRef),
        "lineCount": (tLines.%Size()),
        "totalCustomsValue": (tTotalValue),
        "totalDutyAmount": (tTotalDuty),
        "totalSstAmount": (tTotalSst),
        "totalPayable": (tTotalDuty + tTotalSst),
        "preferenceApplied": (tPrefApplied),
        "calculatedAt": ($ZDATETIME($HOROLOG, 3)),
        "lines": (tLines),
        "backend": "IRIS"
    }
}

}
