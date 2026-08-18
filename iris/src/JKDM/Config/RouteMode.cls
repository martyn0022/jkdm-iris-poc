/// The strangler routing table: one row per operation, deciding which
/// implementation answers it.
///
/// Maps to SMK Figure 5.9.1 steps 6-8:
///   SHADOW   = step 6-7, parallel run and compare
///   LIVE_NEW = step 8, redirect and retire
Class JKDM.Config.RouteMode Extends (%Persistent, %JSON.Adaptor)
{

/// e.g. "duty.calculate"
Property OperationName As %String(MAXLEN = 100) [ Required ];

/// LEGACY | SHADOW | LIVE_NEW
Property Mode As %String(VALUELIST = ",LEGACY,SHADOW,LIVE_NEW") [ InitialExpression = "LEGACY", Required ];

/// Which backend's answer is returned to the consumer.
Property AuthoritativeBackend As %String(VALUELIST = ",COBOL,PHP") [ InitialExpression = "COBOL" ];

/// Class implementing the field classification for this operation.
Property ComparisonRuleClass As %String(MAXLEN = 200) [ InitialExpression = "JKDM.Rule.DutyEquivalence" ];

/// Does this operation compute money?
///
/// A policy, not a description. A fiscal operation is locked to LEGACY:
/// the router refuses to shadow or redirect it. This encodes SMK 5.8 -
/// "leave the revenue core in COBOL... converting the core buys little
/// and risks the numbers" - as configuration rather than convention.
///
/// It also covers most of the shadow-on-writes problem, since the
/// operations that move money are generally the ones that write.
Property Fiscal As %Boolean [ InitialExpression = 0 ];

/// 0-100. Lets you shadow a sample of live traffic rather than all.
Property ShadowSampleRate As %Integer(MAXVAL = 100, MINVAL = 0) [ InitialExpression = 100 ];

Property EffectiveFrom As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG, 3)} ];

Property ChangedBy As %String(MAXLEN = 100) [ InitialExpression = "system" ];

Property ChangeReason As %String(MAXLEN = 500);

Index OperationIdx On OperationName [ Unique ];

/// Resolve the active mode for an operation. Defaults to LEGACY when
/// no row exists - fail safe, never route to an unproven backend by
/// accident.
ClassMethod Resolve(pOperation As %String) As JKDM.Config.RouteMode
{
    Set tRow = ..OperationIdxOpen(pOperation, 0)
    If '$IsObject(tRow) {
        Set tRow = ..%New()
        Set tRow.OperationName = pOperation
        Set tRow.Mode = "LEGACY"
        Set tRow.AuthoritativeBackend = "COBOL"
    }
    Quit tRow
}

/// Register an operation and its policy. Called once, at build time.
/// Mode always starts at LEGACY - a strangler begins with everything
/// on the legacy path.
ClassMethod Declare(
    pOperation As %String,
    pFiscal As %Boolean,
    pRuleClass As %String = "") As %Status
{
    Set tRow = ..OperationIdxOpen(pOperation, 4)
    If '$IsObject(tRow) {
        Set tRow = ..%New()
        Set tRow.OperationName = pOperation
    }
    Set tRow.Fiscal = pFiscal
    Set tRow.Mode = "LEGACY"
    Set tRow.AuthoritativeBackend = "COBOL"
    // Each operation gets its own classification: a manifest lookup and
    // a duty calculation do not have the same fiscal surface.
    Set:pRuleClass'="" tRow.ComparisonRuleClass = pRuleClass
    Set tRow.ChangeReason = "declared"
    Quit tRow.%Save()
}

/// Flip a route. Refuses to move a fiscal operation.
///   Do ##class(JKDM.Config.RouteMode).Set("manifest.lookup","SHADOW")
ClassMethod Set(pOperation As %String, pMode As %String, pReason As %String = "", pRuleClass As %String = "") As %Status
{
    Set tRow = ..OperationIdxOpen(pOperation, 4)
    If '$IsObject(tRow) {
        Set tRow = ..%New()
        Set tRow.OperationName = pOperation
    }

    // An operation that computes money stays where the numbers are
    // known to be correct. No configuration moves it.
    If tRow.Fiscal, pMode '= "LEGACY" {
        Set tMsg = pOperation_" is a fiscal operation and is locked to LEGACY (SMK 5.8)"
        Quit $$$ERROR($$$GeneralError, tMsg)
    }

    Set:pRuleClass'="" tRow.ComparisonRuleClass = pRuleClass
    Set tRow.Mode = pMode
    Set tRow.AuthoritativeBackend = $Case(pMode, "LIVE_NEW":"PHP", :"COBOL")
    Set tRow.EffectiveFrom = $ZDATETIME($HOROLOG, 3)
    Set tRow.ChangeReason = pReason
    Quit tRow.%Save()
}
}
