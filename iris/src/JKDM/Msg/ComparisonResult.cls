/// JKDM SMK POC - equivalence evidence.
///
/// This class is the artefact that takes a module through the SMK 5.7
/// fiscal-equivalence gate and populates its Migration Passport (5.6).
/// The dashboard over it is the governance story made concrete.
Class JKDM.Msg.ComparisonResult Extends (%Persistent, %JSON.Adaptor)
{

Property OperationName As %String(MAXLEN = 100);

Property DeclarationRef As %String(MAXLEN = 40);

Property RequestID As %String(MAXLEN = 60);

Property ComparedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG, 3)} ];

Property CobolResponse As %String(MAXLEN = 30000);

Property PhpResponse As %String(MAXLEN = 30000);

Property FieldDiffs As list Of JKDM.Msg.FieldDiff;

/// EQUIVALENT | MATERIAL_DIFF | FISCAL_DIFF
Property Verdict As %String(VALUELIST = ",EQUIVALENT,MATERIAL_DIFF,FISCAL_DIFF");

Property SessionID As %String(MAXLEN = 60);

Index OperationIdx On OperationName;

Index VerdictIdx On Verdict;

/// Equivalence rate per operation - the number that gates a wave.
ClassMethod EquivalenceRate(pOperation As %String) As %String
{
    Set tTotal = 0, tEquiv = 0
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Verdict, COUNT(*) FROM JKDM_Msg.ComparisonResult "_
        "WHERE OperationName = ? GROUP BY Verdict", pOperation)
    While tRs.%Next() {
        Set tN = tRs.%GetData(2)
        Set tTotal = tTotal + tN
        If tRs.%GetData(1) = "EQUIVALENT" Set tEquiv = tEquiv + tN
    }
    If tTotal = 0 Quit "no data"
    Quit $FNUMBER(tEquiv / tTotal * 100, "", 2)_"% ("_tEquiv_"/"_tTotal_")"
}
}
