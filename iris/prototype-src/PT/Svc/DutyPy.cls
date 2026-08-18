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
/// process - written in ordinary Python with ordinary SQL, by someone
/// who has never seen ObjectScript. Nothing below is IRIS-specific
/// except the two words `iris.sql.exec`.
///
/// Be equally honest about what it does NOT do: Python is not PHP, and
/// this does not make the §5.8 hiring argument disappear. It narrows
/// it from "a language nobody here knows" to "a language most teams
/// already have".
///
/// It also produces the SAME answer as the ObjectScript version and as
/// the COBOL core - 1088.47 - because both use explicit decimal
/// rounding per line. That is a decision, not a language feature.
Class PT.Svc.DutyPy Extends %RegisteredObject
{

/// Returns the same JSON shape as PT.Svc.Duty.Calculate().
ClassMethod Calculate(pRef As %String) As %DynamicObject
{
    Quit ##class(%DynamicObject).%FromJSON(..CalculateJSON(pRef))
}

/// The calculation itself. Returns a JSON string - the Python stays
/// ordinary Python, and the one place the two worlds meet is a string.
ClassMethod CalculateJSON(pRef As %String) As %String [ Language = python ]
{
    import iris
    import json
    import datetime
    from decimal import Decimal, ROUND_HALF_UP

    def money(x):
        # Explicit decimal rounding, half up - the rule the COBOL core
        # applies. Never a binary float for money.
        return Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    header = None
    for row in iris.sql.exec(
        "SELECT DeclRef, FtaClaimed, OriginCountry, LocalPct "
        "FROM PT_Data.Declaration WHERE DeclRef = ?", pRef):
        header = row

    if header is None:
        return json.dumps({"status": "NOT_FOUND", "declarationRef": pRef})

    decl_ref, fta_claimed, origin, local_pct = header

    total_duty = Decimal("0")
    total_sst = Decimal("0")
    total_value = Decimal("0")
    pref_applied = 0
    lines = []

    for line_no, hs_code, customs_value in iris.sql.exec(
        "SELECT LineNo, HSCode, CustomsValue FROM PT_Data.DeclarationLine "
        "WHERE Declaration = ? ORDER BY LineNo", pRef):

        tariff = None
        for row in iris.sql.exec(
            "SELECT DutyRate, SstRate, Description FROM PT_Data.TariffRate "
            "WHERE HSCode = ?", hs_code):
            tariff = row
        if tariff is None:
            continue

        duty_rate, sst_rate, description = tariff
        rate = Decimal(str(duty_rate))

        # Preference applies AT or above the threshold, matching COBOL.
        if fta_claimed and local_pct is not None:
            for pref_rate, min_pct in iris.sql.exec(
                "SELECT PrefRate, MinLocalPct FROM PT_Data.FtaRule "
                "WHERE FtaCode = ? AND HSCode = ? AND OriginCountry = ?",
                fta_claimed, hs_code, origin):
                if Decimal(str(local_pct)) >= Decimal(str(min_pct)):
                    rate = Decimal(str(pref_rate))
                    pref_applied = 1

        value = Decimal(str(customs_value))
        line_duty = money(value * rate)
        line_sst = money((value + line_duty) * Decimal(str(sst_rate)))

        total_duty += line_duty
        total_sst += line_sst
        total_value += value

        lines.append({
            "lineNo": int(line_no),
            "hsCode": hs_code,
            "hsDescription": description,
            "rateApplied": float(rate),
            "customsValue": float(value),
            "lineDuty": float(line_duty),
            "lineSst": float(line_sst),
        })

    return json.dumps({
        "status": "OK",
        "declarationRef": decl_ref,
        "lineCount": len(lines),
        "totalCustomsValue": float(total_value),
        "totalDutyAmount": float(total_duty),
        "totalSstAmount": float(total_sst),
        "totalPayable": float(total_duty + total_sst),
        "preferenceApplied": pref_applied,
        "calculatedAt": datetime.datetime.now().isoformat(timespec="seconds"),
        "lines": lines,
        "backend": "IRIS-PYTHON",
    })
}

}
