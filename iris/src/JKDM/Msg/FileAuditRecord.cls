/// JKDM SMK POC - the receipt ledger for partner files.
///
/// One row per file pulled from a partner drop, written BEFORE the
/// file is parsed and updated afterwards with the outcome. A file
/// that fails to parse still has a row - that is the requirement.
///
/// Ask the room during the demo: "if a broker claims they lodged a
/// declaration at 09:14 and we have no record, how do you disprove
/// it?" This table, plus the raw content it points at, is the answer.
Class JKDM.Msg.FileAuditRecord Extends (%Persistent, %JSON.Adaptor)
{

Property FileName As %String(MAXLEN = 255);

Property FileHash As %String(MAXLEN = 100);

Property SizeBytes As %Integer;

Property PartnerID As %String(MAXLEN = 40);

Property ReceivedDT As %TimeStamp;

Property MessageType As %String(MAXLEN = 20);

/// RECEIVED - pulled, not yet parsed
/// PARSED   - structurally valid
/// REJECTED - failed parse or business validation
/// LODGED   - accepted by the core
Property ParseStatus As %String(VALUELIST = ",RECEIVED,PARSED,REJECTED,LODGED") [ InitialExpression = "RECEIVED" ];

Property RejectReason As %String(MAXLEN = 500);

Property RecordCount As %Integer [ InitialExpression = 0 ];

Property DeclarationRef As %String(MAXLEN = 40);

/// Reference returned by the core once the declaration is lodged.
Property CoreReference As %String(MAXLEN = 60);

Property ProcessedDT As %TimeStamp;

/// Which backend actually served the lodgement - COBOL or PHP.
/// File-origin traffic goes through the SAME strangler router as live
/// API calls, so this column answers SMK open question 5.2 with data
/// rather than opinion.
Property ServedBy As %String(MAXLEN = 20);

Property SessionID As %String(MAXLEN = 60);

/// The raw partner submission, retrievable for the life of the record.
Property RawContent As %Stream.GlobalCharacter;

Index FileNameIdx On FileName;

Index StatusIdx On ParseStatus;

/// Find the open audit row for a file so the outcome can be stamped
/// onto the same record the receipt created.
ClassMethod FindBySession(pSessionID As %String) As JKDM.Msg.FileAuditRecord
{
    Set tRow = ""
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TOP 1 ID FROM JKDM_Msg.FileAuditRecord "_
        "WHERE SessionID = ? ORDER BY ID DESC", pSessionID)
    If tRs.%Next() {
        Set tRow = ..%OpenId(tRs.%GetData(1))
    }
    Quit tRow
}

}
