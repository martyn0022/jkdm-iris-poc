/// Inbound EDI service for the DFTZ partner drop.
///
/// SMK 2.7 integration catalogue, ECS/EDI DFTZ row:
///   current carrier X.400 - SFTP, treatment "Adapter -> API", Wave 3.
///
/// SFTP is not request/response, so there is no inbound call to route.
/// IRIS is the client: it polls the partner drop on a schedule and
/// pulls files down. The partner's "push" is their upload to their own
/// server.
///
/// Figure 4.3.1's routing model assumes an inbound request. Everything
/// downstream of this pull is internally originated, so file traffic
/// reaches the strangler router by a different route - the subject of
/// SMK open question 5.2.
///
/// Not EnsLib.EDI.EDIFACT.Service.FTPService, because that parses the
/// file before handing it over: a file that fails to parse never
/// becomes a message the application controls, and its audit record is
/// whatever the framework logged. Here the receipt is written before
/// the parse is attempted, so this service takes the raw stream, hashes
/// it and passes it on. Parsing happens one step later, in a process
/// that records its own failure.
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

        // Non-repudiation anchor: this hash and the stored content
        // together evidence what the partner sent.
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
/// has moved between versions. Fall back rather than fail: losing the
/// filename must not lose the file.
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
/// IRIS returns the digest as a 32-byte binary string and has no
/// built-in hex encoder for it, so the conversion is explicit. Verified
/// against the standard "abc" vector:
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
