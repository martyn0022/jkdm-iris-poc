/// Lodge a canonical declaration to the core.
///
/// Calls neither backend directly. It calls the same public API
/// contract an external consumer calls and lets the strangler router
/// decide who serves it, so file-origin traffic obeys the same routing
/// table as live API calls.
///
/// SMK 5.2 does not state whether batch and file traffic should get the
/// same dual routing. This class assumes they should; JKDM to confirm.
Class JKDM.BO.CoreDeclarationOp Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The public API contract, identical to what an external consumer
/// would call. Not a back door into a backend.
Property ContractURL As %String(MAXLEN = 200) [ InitialExpression = "/jkdm/duty/calculate" ];

Parameter SETTINGS = "ContractURL:Basic";

Method Lodge(
    pRequest As JKDM.Msg.CanonicalDeclaration,
    Output pResponse As JKDM.Msg.CoreLodgement) As %Status
{
    Set pResponse = ##class(JKDM.Msg.CoreLodgement).%New()

    // A declaration is priced; a manifest is verified against the
    // core's own record. Different questions, different contracts.
    If pRequest.SourceMessageType = "CUSCAR" {
        Quit ..Verify(pRequest, .pResponse)
    }

    Set tBody = {}
    Set tBody.declarationRef = pRequest.DeclarationRef

    // Adapter.Post() form-encodes the payload and uses the adapter's
    // own URL setting. This contract needs a JSON body at a
    // per-operation path, so build the request explicitly.
    Set tHttpReq = ##class(%Net.HttpRequest).%New()
    Set tHttpReq.ContentType = "application/json"
    Do tHttpReq.EntityBody.Write(tBody.%ToJSON())

    // The URL must be a local variable. The adapter reads this
    // argument as $GET(pURL,..URL); a property expression passed
    // directly resolves to empty, producing a 404 against the instance
    // root rather than an error.
    Kill tFormData
    Set tURL = ..ContractURL
    $$$TRACE("posting to contract URL ["_tURL_"]")
    Set tSC = ..Adapter.SendFormDataArray(.tHttpResp, "POST", tHttpReq, "", .tFormData, tURL)

    // Do not bail on tSC. The adapter returns an error status for any
    // non-2xx response, which would collapse "no such declaration" and
    // "backend down" into one outcome. The response object is
    // populated either way, so read the status code.
    If '$IsObject(tHttpResp) {
        Set pResponse.Outcome = "CORE_UNAVAILABLE"
        Quit $$$OK
    }

    // 404 is an answer: the core holds no such declaration reference.
    // The caller must fix that. Any other error is internal, and the
    // caller only needs to know to retry.
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

    // Routing headers from the strangler router. Stripped in
    // production; here they let the audit trail record which
    // implementation answered.
    Set pResponse.ServedBy  = tHttpResp.GetHeader("X-SMK-Backend")
    Set pResponse.RouteMode = tHttpResp.GetHeader("X-SMK-Route-Mode")

    Set pResponse.TotalDutyAmount = tJson.totalDutyAmount
    Set pResponse.TotalTaxAmount  = tJson.totalSstAmount
    Set pResponse.TotalPayable    = tJson.totalPayable

    // A real core issues this reference. The POC derives one so the
    // audit trail has a value to carry.
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
