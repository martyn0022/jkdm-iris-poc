/// An acknowledgement to be written back to the partner's drop.
///
/// CONTRL = syntax-level acknowledgement (did the message parse).
/// APERAK = application-level acknowledgement (did the business
///          accept it, and with what reference).
///
/// Partners chase acknowledgements. An ingestion flow that parses
/// perfectly but never acks is an operational problem, not a
/// technical success - so the ack is part of the flow, not an
/// afterthought.
Class JKDM.Msg.AckRequest Extends Ens.Request
{

Property FileName As %String(MAXLEN = 255);

/// CONTRL | APERAK
Property AckType As %String(MAXLEN = 10);

Property Accepted As %Boolean;

Property Content As %String(MAXLEN = 10000);

}
