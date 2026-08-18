/// What the core returned when the declaration was lodged.
///
/// ServedBy and RouteMode are carried deliberately: they let the
/// audit trail answer "which implementation computed the duty on this
/// declaration, on this day" - which is the question an auditor asks
/// after cutover, and the one a migration project usually cannot
/// answer retrospectively.
Class JKDM.Msg.CoreLodgement Extends Ens.Response
{

/// LODGED               - priced and accepted
/// UNKNOWN_DECLARATION  - the core has no such declaration reference
/// CORE_UNAVAILABLE     - the backend failed or timed out
///
/// The first two are answers. The third is an outage. Partners must be
/// told different things, and operations must be paged for only one of
/// them - so the flow has to be able to tell them apart.
Property Outcome As %String(VALUELIST = ",LODGED,UNKNOWN_DECLARATION,CORE_UNAVAILABLE") [ InitialExpression = "LODGED" ];

Property CoreReference As %String(MAXLEN = 60);

Property ServedBy As %String(MAXLEN = 20);

Property RouteMode As %String(MAXLEN = 20);

Property TotalDutyAmount As %Decimal(SCALE = 2);

Property TotalTaxAmount As %Decimal(SCALE = 2);

Property TotalPayable As %Decimal(SCALE = 2);

}
