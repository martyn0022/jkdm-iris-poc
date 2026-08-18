/// JKDM SMK POC - inbound EDI service for the DFTZ partner drop.
///
/// SMK 2.7 integration catalogue, ECS/EDI DFTZ row:
///   current carrier X.400 - SFTP, treatment "Adapter -> API", Wave 3.
///
/// THE PATTERN - STATE THIS BEFORE ANYTHING ELSE IN THE WALKTHROUGH
/// ----------------------------------------------------------------
/// SFTP is NOT request/response. There is no inbound call for IRIS to
/// route. IRIS is the CLIENT: it polls the partner drop on a schedule
/// and pulls files down when they appear. The partner's "push" is
/// their upload to their own server.
///
/// This matters architecturally: Figure 4.3.1's routing model assumes
/// an inbound request to route. Everything downstream of this pull is
/// an internally-originated transaction, so file traffic reaches the
/// strangler router by a different door - see SMK open question 5.2,
/// which this POC turns from a debate into an observation.
///
/// WHY A CUSTOM SERVICE RATHER THAN EnsLib.EDI.EDIFACT.Service.FTPService
/// ----------------------------------------------------------------------
/// The stock EDIFACT FTP service parses the file before handing it
/// over. That is usually what you want - but it means a file that
/// fails to parse never becomes a message you control, and the audit
/// record for it is whatever the framework chose to log.
///
/// In a fiscal domain the receipt must exist before the parse is
/// attempted, because the file you cannot read is exactly the one you
/// will be asked to produce. So this service takes the raw stream,
/// hashes it, and hands it on. Parsing happens one step later, inside
/// a process that can record its own failure.
Class JKDM.BS.EdiInboundService Extends Ens.BusinessService
{

Parameter ADAPTER = "EnsLib.FTP.InboundAdapter";

/// SMK 2.7 catalogue partner identifier.
Property PartnerID As %String(MAXLEN = 40) [ InitialExpression = "DFTZ" ];

Property TargetConfigName As %String(MAXLEN = 200) [ InitialExpression = "JKDM.BP.DeclarationIntake" ];

Parameter SETTINGS = "PartnerID:Basic,TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

Method OnProcessInput(
    pInput As %Stream.Object,
    Output pOutput As %RegisteredObject) As %Status
{
    Set tSC = $$$OK
    Try {
        Set tFileName = ..ResolveFileName(pInput)

        // ---- read the raw content ONCE ---------------------------
        Do pInput.Rewind()
        Set tRaw = ""
        While 'pInput.AtEnd {
            Set tRaw = tRaw_pInput.Read(32000)
        }

        Set tMsg = ##class(JKDM.Msg.InboundFile).%New()
        Set tMsg.FileName   = tFileName
        Set tMsg.PartnerID  = ..PartnerID
        Set tMsg.SizeBytes  = $LENGTH(tRaw)

        // Non-repudiation anchor. If a partner disputes what they
        // sent, this hash plus the stored content settles it.
        Set tMsg.FileHash = ..Sha256(tRaw)

        Do tMsg.RawContent.Write(tRaw)

        $$$TRACE("pulled "_tFileName_" ("_tMsg.SizeBytes_" bytes) sha256="_$EXTRACT(tMsg.FileHash, 1, 16)_"...")

        Set tSC = ..SendRequestSync(..TargetConfigName, tMsg, .pOutput)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// The FTP adapter names the stream it hands over, but the attribute
/// it uses has moved between versions. Fall back rather than fail -
/// losing the filename must not lose the file.
ClassMethod ResolveFileName(pInput As %Stream.Object) As %String
{
    Set tName = ""
    Try {
        Set tName = pInput.Attributes("Filename")
    }
    Catch {
        Set tName = ""
    }
    If tName = "" {
        Try {
            Set tName = pInput.Filename
        }
        Catch {
            Set tName = ""
        }
    }
    Set:tName="" tName = "unnamed-"_$ZDATETIME($HOROLOG, 8)_".edi"
    Quit ##class(%File).GetFilename(tName)
}

/// SHA-256, lower-case hex.
///
/// IRIS returns the digest as a 32-byte binary string. There is no
/// built-in hex encoder for it, so the conversion is explicit -
/// verified against the standard "abc" test vector:
///   ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
ClassMethod Sha256(pContent As %String) As %String
{
    Set tDigest = $SYSTEM.Encryption.SHAHash(256, pContent)
    Set tHex = ""
    For i = 1:1:$LENGTH(tDigest) {
        Set tHex = tHex_$EXTRACT("0"_$ZHEX($ASCII(tDigest, i)), *-1, *)
    }
    Quit $ZCONVERT(tHex, "L")
}

}
