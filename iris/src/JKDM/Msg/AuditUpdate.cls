/// Outcome stamp for an audit row created earlier in the same session.
///
/// Sent to JKDM.BO.AuditOperation after parsing and after lodgement.
/// The row is never replaced - it is updated - so the receipt
/// timestamp and the original hash survive whatever happens later.
Class JKDM.Msg.AuditUpdate Extends Ens.Request
{

Property SessionID As %String(MAXLEN = 60);

Property ParseStatus As %String(MAXLEN = 20);

Property RejectReason As %String(MAXLEN = 500);

Property MessageType As %String(MAXLEN = 20);

Property DeclarationRef As %String(MAXLEN = 40);

Property RecordCount As %Integer;

Property CoreReference As %String(MAXLEN = 60);

Property ServedBy As %String(MAXLEN = 20);

}
