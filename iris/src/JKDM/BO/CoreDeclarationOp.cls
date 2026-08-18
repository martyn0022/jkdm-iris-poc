/// JKDM SMK POC - lodge a canonical declaration to the core.
///
/// THIS IS THE JOIN BETWEEN THE TWO FLOWS, AND IT IS THE MOST
/// ARCHITECTURALLY LOADED CLASS IN THE POC.
///
/// It does not call COBOL. It does not call PHP. It calls the same
/// public API contract that a live consumer calls, and lets the
/// strangler router decide who serves it.
///
/// The consequence is worth pausing on in the session: flip
/// duty.calculate to SHADOW, drop an EDIFACT file, and the file-origin
/// transaction is shadowed and compared exactly like an interactive
/// one. Flip it to LIVE_NEW and tomorrow's partner file is served by
/// PHP without the partner, the file format, or this class changing.
///
/// SMK 5.2 asks whether batch and file-origin traffic get the same
/// dual routing as live API calls. The document does not answer it.
/// This class answers "yes" - which is a decision JKDM should make
/// explicitly rather than inherit from a POC. Put it to the room.
Class JKDM.BO.CoreDeclarationOp Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The public API contract - identical to what an external consumer
/// would call. Not a back door into a backend.
Property ContractURL As %String(MAXLEN = 200) [ InitialExpression = "/jkdm/duty/calculate" ];

Parameter SETTINGS = "ContractURL:Basic";

Method Lodge(
    pRequest As JKDM.Msg.CanonicalDeclaration,
    Output pResponse As JKDM.Msg.CoreLodgement) As %Status
{
    Set pResponse = ##class(JKDM.Msg.CoreLodgement).%New()

    // A declaration gets priced; a manifest gets verified against the
    // core's own record. Different contracts, because they are
    // different questions - and the manifest one is exactly the
    // operation the afternoon exercise puts into SHADOW.
    If pRequest.SourceMessageType = "CUSCAR" {
        Quit ..Verify(pRequest, .pResponse)
    }

    Set tBody = {}
    Set tBody.declarationRef = pRequest.DeclarationRef

    // Adapter.Post() takes its URL from the adapter's own setting and
    // form-encodes the payload. This contract wants a JSON body at a
    // per-operation path, so build the request explicitly and let
    // SendFormDataArray carry it.
    Set tHttpReq = ##class(%Net.HttpRequest).%New()
    Set tHttpReq.ContentType = "application/json"
    Do tHttpReq.EntityBody.Write(tBody.%ToJSON())

    // Resolve the URL into a local first. The adapter reads this
    // argument with $GET(pURL,..URL), and passing the property
    // expression straight in resolves to empty there - which shows up
    // as a 404 against the instance root, not as an error. Cost an
    // hour once; keeping the local costs nothing.
    Kill tFormData
    Set tURL = ..ContractURL
    $$$TRACE("posting to contract URL ["_tURL_"]")
    Set tSC = ..Adapter.SendFormDataArray(.tHttpResp, "POST", tHttpReq, "", .tFormData, tURL)

    // Do NOT bail on tSC here. The adapter returns an error status for
    // every non-2xx response, which would collapse "no such
    // declaration" and "the backend is down" back into one outcome -
    // the exact distinction this operation exists to preserve. The
    // response object is populated either way; read the status code.
    If '$IsObject(tHttpResp) {
        Set pResponse.Outcome = "CORE_UNAVAILABLE"
        Quit $$$OK
    }

    // 404 is an ANSWER: the core does not hold that declaration
    // reference. That is the broker's problem and they need to be told
    // so. Anything else in the error range is our problem, and nobody
    // outside should hear about it beyond "try again".
    If tHttpResp.StatusCode = 404 {
        Set pResponse.Outcome = "UNKNOWN_DECLARATION"
        Quit $$$OK
    }

    If tHttpResp.StatusCode '= 200 {
        Set pResponse.Outcome = "CORE_UNAVAILABLE"
        Set tWarn = "core contract returned HTTP "_tHttpResp.StatusCode_
                    " for "_pRequest.DeclarationRef
        $$$LOGWARNING(tWarn)
        Quit $$$OK
    }

    Set tJson = ##class(%DynamicObject).%FromJSON(tHttpResp.Data)

    // The teaching headers from the strangler router. In production
    // these are stripped - here they are how the audit trail learns
    // which implementation computed the money.
    Set pResponse.ServedBy  = tHttpResp.GetHeader("X-SMK-Backend")
    Set pResponse.RouteMode = tHttpResp.GetHeader("X-SMK-Route-Mode")

    Set pResponse.TotalDutyAmount = tJson.totalDutyAmount
    Set pResponse.TotalTaxAmount  = tJson.totalSstAmount
    Set pResponse.TotalPayable    = tJson.totalPayable

    // A real core issues the reference. The POC derives one so the
    // audit trail has something to carry - flagged rather than faked
    // silently.
    Set pResponse.CoreReference = "CORE-"_pRequest.DeclarationRef

    Set tLog = "lodged "_pRequest.DeclarationRef_" via "_pResponse.ServedBy
    Set tLog = tLog_" (mode "_pResponse.RouteMode_"), payable "_pResponse.TotalPayable
    $$$LOGINFO(tLog)

    Quit $$$OK
}

/// Manifest path: ask the core whether it holds this manifest, over
/// the same public contract a consumer would use.
Method Verify(
    pRequest As JKDM.Msg.CanonicalDeclaration,
    Output pResponse As JKDM.Msg.CoreLodgement) As %Status
{
    Set tURL = "/jkdm/manifest/"_pRequest.ManifestRef

    Set tHttpReq = ##class(%Net.HttpRequest).%New()
    Kill tFormData
    Set tSC = ..Adapter.SendFormDataArray(.tHttpResp, "GET", tHttpReq, "", .tFormData, tURL)

    If '$IsObject(tHttpResp) {
        Set pResponse.Outcome = "CORE_UNAVAILABLE"
        Quit $$$OK
    }
    If tHttpResp.StatusCode = 404 {
        Set pResponse.Outcome = "UNKNOWN_DECLARATION"
        Quit $$$OK
    }
    If tHttpResp.StatusCode '= 200 {
        Set pResponse.Outcome = "CORE_UNAVAILABLE"
        Quit $$$OK
    }

    Set pResponse.ServedBy      = tHttpResp.GetHeader("X-SMK-Backend")
    Set pResponse.RouteMode     = tHttpResp.GetHeader("X-SMK-Route-Mode")
    Set pResponse.CoreReference = "CORE-"_pRequest.ManifestRef

    Set tLog = "verified manifest "_pRequest.ManifestRef_" via "_pResponse.ServedBy
    $$$LOGINFO(tLog)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="JKDM.Msg.CanonicalDeclaration">
    <Method>Lodge</Method>
  </MapItem>
</MapItems>
}

}
