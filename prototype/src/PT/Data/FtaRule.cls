/// Preferential rate rules under an FTA.
Class PT.Data.FtaRule Extends %Persistent
{

Property FtaCode As %String(MAXLEN = 10);

Property HSCode As %String(MAXLEN = 12);

Property OriginCountry As %String(MAXLEN = 2);

Property PrefRate As %Numeric(SCALE = 4);

Property MinLocalPct As %Numeric(SCALE = 2);

Index LookupIdx On (FtaCode, HSCode, OriginCountry);

/// The rule that applies to a line, or nothing.
ClassMethod Find(
    pFta As %String,
    pHS As %String,
    pOrigin As %String) As PT.Data.FtaRule
{
    Quit:pFta="" ""
    Set tId = ""
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TOP 1 ID FROM PT_Data.FtaRule "_
        "WHERE FtaCode = ? AND HSCode = ? AND OriginCountry = ?",
        pFta, pHS, pOrigin)
    If tRs.%Next() {
        Set tId = tRs.%GetData(1)
    }
    Quit:tId="" ""
    Quit ..%OpenId(tId)
}

}
