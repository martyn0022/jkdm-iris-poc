/// JKDM SMK POC - the audit/non-repudiation operation.
///
/// SMK 2.7 lists "audit - non-repudiation" as a TO-BE fabric
/// capability. This operation is that capability, and it is
/// deliberately boring: create the row on receipt, update it on
/// outcome, never delete.
///
/// It is a separate business operation rather than inline code in the
/// process because in production it will not be a local table. It
/// will be a WORM store, an archive service, or a records-management
/// system with its own retention policy - and when that happens, only
/// this class changes.
Class JKDM.BO.AuditOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// Create the receipt row - called BEFORE the file is parsed.
Method RecordReceipt(
    pRequest As JKDM.Msg.InboundFile,
    Output pResponse As Ens.Response) As %Status
{
    Set pResponse = ##class(Ens.Response).%New()

    Set tRow = ##class(JKDM.Msg.FileAuditRecord).%New()
    Set tRow.FileName    = pRequest.FileName
    Set tRow.FileHash    = pRequest.FileHash
    Set tRow.SizeBytes   = pRequest.SizeBytes
    Set tRow.PartnerID   = pRequest.PartnerID
    Set tRow.ReceivedDT  = pRequest.ReceivedDT
    Set tRow.ParseStatus = "RECEIVED"
    Set tRow.SessionID   = ..%SessionId

    Do pRequest.RawContent.Rewind()
    Do tRow.RawContent.CopyFrom(pRequest.RawContent)

    Set tSC = tRow.%Save()
    $$$LOGINFO("audit receipt #"_tRow.%Id()_" for "_pRequest.FileName)
    Quit tSC
}

/// Stamp the outcome onto the row created on receipt.
Method RecordOutcome(
    pRequest As JKDM.Msg.AuditUpdate,
    Output pResponse As Ens.Response) As %Status
{
    Set pResponse = ##class(Ens.Response).%New()

    Set tRow = ##class(JKDM.Msg.FileAuditRecord).FindBySession(pRequest.SessionID)
    If '$IsObject(tRow) {
        // Should not happen: the receipt is written first, always.
        // If it does, that is a defect worth an alert rather than a
        // silent skip.
        $$$LOGERROR("no audit row for session "_pRequest.SessionID)
        Quit $$$OK
    }

    Set tRow.ParseStatus = pRequest.ParseStatus
    Set tRow.ProcessedDT = $ZDATETIME($HOROLOG, 3)
    Set:pRequest.RejectReason'="" tRow.RejectReason = pRequest.RejectReason
    Set:pRequest.MessageType'="" tRow.MessageType = pRequest.MessageType
    Set:pRequest.DeclarationRef'="" tRow.DeclarationRef = pRequest.DeclarationRef
    Set:pRequest.RecordCount'="" tRow.RecordCount = pRequest.RecordCount
    Set:pRequest.CoreReference'="" tRow.CoreReference = pRequest.CoreReference
    Set:pRequest.ServedBy'="" tRow.ServedBy = pRequest.ServedBy

    Quit tRow.%Save()
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="JKDM.Msg.InboundFile">
    <Method>RecordReceipt</Method>
  </MapItem>
  <MapItem MessageType="JKDM.Msg.AuditUpdate">
    <Method>RecordOutcome</Method>
  </MapItem>
</MapItems>
}

}
