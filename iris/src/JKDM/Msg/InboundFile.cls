/// JKDM SMK POC - a partner file, exactly as it arrived.
///
/// This message carries the RAW bytes plus the metadata needed to
/// prove receipt. It is created by the inbound service BEFORE any
/// parsing is attempted, which is the whole point: if a partner sends
/// you a malformed file, you must still be able to prove what they
/// sent and when. That is a fiscal-domain non-repudiation requirement
/// (SMK 2.7 TO-BE fabric capabilities), not IRIS boilerplate.
Class JKDM.Msg.InboundFile Extends Ens.Request
{

Property FileName As %String(MAXLEN = 255);

/// Which partner drop this came from. SMK 2.7 catalogue row:
/// ECS/EDI DFTZ (TIE Kinetix, SFTP).
Property PartnerID As %String(MAXLEN = 40);

Property SizeBytes As %Integer;

/// SHA-256 of the raw content. The non-repudiation anchor.
Property FileHash As %String(MAXLEN = 100);

Property ReceivedDT As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG, 3)} ];

/// The original submission, untouched. SMK's audit posture requires
/// the raw partner content be retrievable, not just the parsed result.
Property RawContent As %Stream.GlobalCharacter;

}
