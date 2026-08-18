/// One commodity line of the canonical declaration.
///
/// WCO Data Model aligned subset (SMK 4.3.5, 6.12).
Class JKDM.Msg.CanonicalLine Extends (%SerialObject, %JSON.Adaptor)
{

Property LineNo As %Integer;

Property HSCode As %String(MAXLEN = 12);

Property Description As %String(MAXLEN = 250);

Property Qty As %Decimal(SCALE = 3);

Property UOM As %String(MAXLEN = 6);

Property LineValue As %Decimal(SCALE = 2);

}
