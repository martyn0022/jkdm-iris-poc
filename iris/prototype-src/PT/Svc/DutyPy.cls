/// The same calculation, written in Python.
///
/// ############################################################
/// ##  THIS IS THE POINT OF THE SEGMENT FOR A PHP TEAM        ##
/// ############################################################
///
/// The unspoken objection to putting application logic in the database
/// is "we do not have ObjectScript people, and the tender chose PHP
/// partly for the local hiring pool". That objection is correct, and
/// pretending otherwise wastes everyone's time.
///
/// This class is the honest answer. Same data, same storage, same
/// process - written in Python by someone who has never seen
/// ObjectScript. The persistent classes are reached through the iris
/// module; everything else is ordinary Python.
///
/// Be equally honest about what it does NOT do: Python is not PHP, and
/// this does not make the hiring argument disappear. It narrows it.
Class PT.Svc.DutyPy Extends %RegisteredObject
{

/// Returns the same JSON shape as PT.Svc.Duty.Calculate().
ClassMethod Calculate(pRef As %String) As %DynamicObject [ Language = python ]
{
    import iris
    import json
    from decimal import Decimal, ROUND_HALF_UP

    def money(x):
        # Explicit decimal rounding, half up - the same rule the COBOL
        # core applies. Never a binary float for money.
        return Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    decl = iris.cls("PT.Data.Declaration")._OpenId(pRef)
    if not decl:
        return iris.cls("%Library.DynamicObject")._FromJSON(
            json.dumps({"status": "NOT_FOUND", "declarationRef": pRef}))

    total_duty = Decimal("0")
    total_sst = Decimal("0")
    total_value = Decimal("0")
    pref_applied = 0
    lines = []

    for i in range(1, decl.Lines.Count() + 1):
        line = decl.Lines.GetAt(i)
        tariff = iris.cls("PT.Data.TariffRate")._OpenId(line.HSCode)
        if not tariff:
            continue

        rate = Decimal(str(tariff.DutyRate))

        fta = iris.cls("PT.Data.FtaRule").Find(
            decl.FtaClaimed, line.HSCode, decl.OriginCountry)
        if fta and decl.LocalPct is not None and \
           Decimal(str(decl.LocalPct)) >= Decimal(str(fta.MinLocalPct)):
            rate = Decimal(str(fta.PrefRate))
            pref_applied = 1

        value = Decimal(str(line.CustomsValue))
        line_duty = money(value * rate)
        line_sst = money((value + line_duty) * Decimal(str(tariff.SstRate)))

        total_duty += line_duty
        total_sst += line_sst
        total_value += value

        lines.append({
            "lineNo": int(line.LineNo),
            "hsCode": line.HSCode,
            "hsDescription": tariff.Description,
            "rateApplied": float(rate),
            "customsValue": float(value),
            "lineDuty": float(line_duty),
            "lineSst": float(line_sst),
        })

    payload = {
        "status": "OK",
        "declarationRef": decl.DeclRef,
        "lineCount": len(lines),
        "totalCustomsValue": float(total_value),
        "totalDutyAmount": float(total_duty),
        "totalSstAmount": float(total_sst),
        "totalPayable": float(total_duty + total_sst),
        "preferenceApplied": pref_applied,
        "calculatedAt": str(iris.system.Util.TimeStamp()),
        "lines": lines,
        "backend": "IRIS-PYTHON",
    }
    return iris.cls("%Library.DynamicObject")._FromJSON(json.dumps(payload))
}

}
