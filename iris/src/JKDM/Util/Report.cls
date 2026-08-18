/// JKDM SMK POC - terminal reports for the demo.
///
/// These exist so the session can show evidence without anyone
/// squinting at a SQL client. Every one of them is a plain query over
/// a persistent class - open the source if the room wants to see that
/// there is no magic behind the numbers.
///
///   Do ##class(JKDM.Util.Report).Audit()
///   Do ##class(JKDM.Util.Report).Equivalence()
///   Do ##class(JKDM.Util.Report).Diffs()
Class JKDM.Util.Report Extends %RegisteredObject
{

/// Flow A - the ingestion audit trail.
ClassMethod Audit()
{
    Write !, "FILE                          STATUS    DECLARATION       LN  SERVED  CORE REFERENCE"
    Write !, ..Rule()

    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT FileName, ParseStatus, DeclarationRef, RecordCount, "_
        "ServedBy, CoreReference, RejectReason "_
        "FROM JKDM_Msg.FileAuditRecord ORDER BY ID")

    Set tCount = 0
    While tRs.%Next() {
        Set tCount = tCount + 1
        Write !, ..Pad(tRs.%GetData(1), 30)
        Write ..Pad(tRs.%GetData(2), 10)
        Write ..Pad(tRs.%GetData(3), 18)
        Write ..Pad(tRs.%GetData(4), 4)
        Write ..Pad(tRs.%GetData(5), 8)
        Write tRs.%GetData(6)
        If tRs.%GetData(7) '= "" {
            Write !, "    reason: ", $EXTRACT(tRs.%GetData(7), 1, 96)
        }
    }

    If tCount = 0 {
        Write !, "(no files ingested yet - drop one from the console or ./scripts/drop-edi.sh)"
    }
    Write !
}

/// Flow B - the equivalence rate that gates a wave (SMK 5.6, 5.7).
///
/// Read the breakdown, not the headline. "0% equivalent" sounds like
/// total failure and usually is not: it counts declarations where
/// every field matched, and one truncated description is enough to
/// spoil that. The number that gates a wave is the FISCAL count,
/// because SMK 5.7 defines equivalence over the fiscal outcomes -
/// duty, tax, payment, receipt, exemption, refund, guarantee, revenue
/// posting, declaration status, release status - and nothing else.
///
/// Deciding that distinction is the room's job, not the tool's.
ClassMethod Equivalence(pOperation As %String = "duty.calculate")
{
    Write !, "Equivalence rate, ", pOperation, ": ",
             ##class(JKDM.Msg.ComparisonResult).EquivalenceRate(pOperation)

    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Verdict, COUNT(*) FROM JKDM_Msg.ComparisonResult "_
        "WHERE OperationName = ? GROUP BY Verdict", pOperation)
    Write !, "Breakdown: "
    While tRs.%Next() {
        Write tRs.%GetData(1), "=", tRs.%GetData(2), "  "
    }

    Write !!, "REFERENCE           VERDICT          COMPARED"
    Write !, ..Rule()

    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT DeclarationRef, Verdict, ComparedAt "_
        "FROM JKDM_Msg.ComparisonResult WHERE OperationName = ? ORDER BY ID", pOperation)

    While tRs.%Next() {
        Write !, ..Pad(tRs.%GetData(1), 20)
        Write ..Pad(tRs.%GetData(2), 17)
        Write $EXTRACT(tRs.%GetData(3), 1, 19)
    }
    Write !
}

/// Every field difference found, newest comparison first.
///
/// EXPECT NOISE. The IGNORE rows dominate and that is the lesson -
/// a comparator without classification produces a report nobody reads.
ClassMethod Diffs(pLimit As %Integer = 12, pOperation As %String = "")
{
    Write !, "REFERENCE           FIELD                         CLASS     COBOL  /  PHP"
    Write !, ..Rule()

    // FieldDiffs is a list of serial objects, so it lives inside the
    // parent row rather than in a child table - there is nothing to
    // join to. Walk the objects instead.
    If pOperation = "" {
        Set tRs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT TOP ? ID FROM JKDM_Msg.ComparisonResult ORDER BY ID DESC", pLimit)
    } Else {
        Set tRs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT TOP ? ID FROM JKDM_Msg.ComparisonResult "_
            "WHERE OperationName = ? ORDER BY ID DESC", pLimit, pOperation)
    }

    Set tCount = 0
    While tRs.%Next() {
        Set tResult = ##class(JKDM.Msg.ComparisonResult).%OpenId(tRs.%GetData(1))
        Continue:'$IsObject(tResult)

        For i = 1:1:tResult.FieldDiffs.Count() {
            Set tDiff = tResult.FieldDiffs.GetAt(i)
            Set tCount = tCount + 1
            Write !, ..Pad(tResult.DeclarationRef, 20)
            Write ..Pad(tDiff.FieldPath, 30)
            Write ..Pad(tDiff.Classification, 10)
            // Show a length whenever the visible text is identical.
            // Truncated descriptions and space-padded fixed-width
            // fields otherwise print as two identical strings, which
            // reads as a broken comparator rather than a real
            // difference.
            Write ..Value(tDiff.CobolValue), " / ", ..Value(tDiff.PhpValue)
        }
    }

    If tCount = 0 {
        Write !, "(no comparisons yet - put an operation in SHADOW and call the contract)"
    }
    Write !, ..Rule()
    Write !, tCount, " differences. Only the FISCAL rows decide the SMK 5.7 gate."
    Write !
}

/// The two flows in one view: which declarations arrived by file, and
/// what the comparator concluded about them.
ClassMethod Combined()
{
    Write !, "DECLARATION       ARRIVED BY   SERVED  VERDICT"
    Write !, ..Rule()

    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT a.DeclarationRef, a.FileName, a.ServedBy, "_
        "(SELECT TOP 1 c.Verdict FROM JKDM_Msg.ComparisonResult c "_
        " WHERE c.DeclarationRef = a.DeclarationRef ORDER BY c.ID DESC) "_
        "FROM JKDM_Msg.FileAuditRecord a "_
        "WHERE a.ParseStatus = 'LODGED' ORDER BY a.ID")

    While tRs.%Next() {
        Write !, ..Pad(tRs.%GetData(1), 18)
        Write ..Pad("EDIFACT file", 13)
        Write ..Pad(tRs.%GetData(3), 8)
        Write $SELECT(tRs.%GetData(4) = "": "(not shadowed)", 1: tRs.%GetData(4))
    }
    Write !
}

/// Render a value for the diff report, with a length when it has been
/// clipped for display.
ClassMethod Value(pRaw As %String) As %String [ Private ]
{
    Set tLen = $LENGTH(pRaw)
    If tLen <= 24 Quit pRaw
    Quit $EXTRACT(pRaw, 1, 24)_"..("_tLen_")"
}

ClassMethod Pad(
    pValue As %String,
    pWidth As %Integer) As %String [ Private ]
{
    Quit $EXTRACT(pValue_"                                        ", 1, pWidth)
}

ClassMethod Rule() As %String [ Private ]
{
    Quit "--------------------------------------------------------------------------------"
}

}
