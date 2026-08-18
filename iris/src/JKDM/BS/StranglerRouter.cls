/// JKDM SMK POC - the strangler router.
///
/// SMK Figure 4.3.1: one API contract; IRIS routes to COBOL today and
/// PHP later, with shadow execution during test. The consumer never
/// changes.
///
/// THE DEMO
///   Do ##class(JKDM.Config.RouteMode).Set("duty.calculate","LEGACY")
///   Do ##class(JKDM.Config.RouteMode).Set("duty.calculate","SHADOW")
///   Do ##class(JKDM.Config.RouteMode).Set("duty.calculate","LIVE_NEW")
/// ...calling the same endpoint throughout. Do it slowly, twice.
///
/// X-SMK-Backend and X-SMK-Route-Mode response headers are a teaching
/// device - they make an invisible routing decision visible in
/// Postman. Strip them for production.
Class JKDM.BS.StranglerRouter Extends %CSP.REST
{

Parameter CHARSET = "utf-8";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/health"          Method="GET"  Call="Health"/>
  <Route Url="/duty/calculate"  Method="POST" Call="DutyCalculate"/>
  <Route Url="/manifest/:ref"   Method="GET"  Call="ManifestLookup"/>
  <Route Url="/routes"          Method="GET"  Call="ListRoutes"/>
  <Route Url="/routes/:op/:mode" Method="PUT" Call="SetRoute"/>
  <Route Url="/comparisons"     Method="GET"  Call="ListComparisons"/>
</Routes>
}

/// Everything this class writes is JSON. Setting it per method invites
/// the one that gets forgotten, which is how an API ends up serving
/// application/json as text/html.
ClassMethod OnPreDispatch(
    pUrl As %String,
    pMethod As %String,
    ByRef pContinue As %Boolean) As %Status
{
    Set %response.ContentType = "application/json"
    Set pContinue = 1
    Quit $$$OK
}

ClassMethod Health() As %Status
{
    Write {"status":"UP","fabric":"IRIS"}.%ToJSON()
    Quit $$$OK
}

/// The single API contract. Consumers call this and never know or
/// care which backend answered.
ClassMethod DutyCalculate() As %Status
{
    #dim tSC As %Status = $$$OK
    Try {
        Set tBody = ##class(%DynamicObject).%FromJSON(%request.Content)
        Set tRef = $ZSTRIP(tBody.declarationRef, "<>W")

        If tRef = "" {
            Set %response.Status = 400
            Write {"error":"declarationRef required"}.%ToJSON()
            Quit
        }

        Set tOperation = "duty.calculate"
        Set tRoute = ##class(JKDM.Config.RouteMode).Resolve(tOperation)
        Set tMode = tRoute.Mode

        Set %response.Headers("X-SMK-Route-Mode") = tMode

        If tMode = "LIVE_NEW" {
            Set tResp = ..CallPhp(tRef, .tSC)
            Set %response.Headers("X-SMK-Backend") = "PHP"
        }
        Else {
            // LEGACY and SHADOW both return the COBOL answer.
            Set tResp = ..CallCobol(tRef, .tSC)
            Set %response.Headers("X-SMK-Backend") = "COBOL"

            If tMode = "SHADOW" {
                // Fire-and-forget. A PHP failure must NOT reach the
                // consumer - toggle FAIL_MODE=on in the php-service
                // container and prove it.
                Do ..ShadowAndCompare(tRef, tResp, tOperation, tRoute)
            }
        }

        If $$$ISERR(tSC) {
            // "We do not hold that declaration" is an answer, not an
            // outage. Collapsing both into 502 tells a caller to retry
            // something that will never succeed, and hides a real
            // outage inside a stream of data errors.
            If $SYSTEM.Status.GetErrorText(tSC) [ "404" {
                Set %response.Status = 404
                Write {"error":"declaration not found"}.%ToJSON()
                Quit
            }
            Set %response.Status = 502
            Write {"error":"backend unavailable"}.%ToJSON()
            Quit
        }

        Write tResp.%ToJSON()
    }
    Catch ex {
        Set %response.Status = 500
        Write {"error":(ex.DisplayString())}.%ToJSON()
    }
    Quit $$$OK
}

/// Call the COBOL core and normalise its fixed-width response into
/// the canonical shape. See JKDM.Util.CobolParser for why this matters.
ClassMethod CallCobol(pRef As %String, Output pSC As %Status) As %DynamicObject
{
    Set pSC = $$$OK
    Set tHost = $SYSTEM.Util.GetEnviron("COBOL_HOST")
    Set:tHost="" tHost = "cobol-core"
    Set tPort = $SYSTEM.Util.GetEnviron("COBOL_PORT")
    Set:tPort="" tPort = 8080

    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Server = tHost
    Set tReq.Port = tPort
    Set tReq.ContentType = "application/json"
    Do tReq.EntityBody.Write({"declarationRef":(pRef)}.%ToJSON())

    Set pSC = tReq.Post("/duty/calculate")
    If $$$ISERR(pSC) Quit {}
    If tReq.HttpResponse.StatusCode '= 200 {
        Set pSC = $$$ERROR($$$GeneralError, "COBOL HTTP "_tReq.HttpResponse.StatusCode)
        Quit {}
    }

    Set tRaw = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
    Quit ##class(JKDM.Util.CobolParser).ToCanonical(tRaw.raw, tRaw.lines)
}

ClassMethod CallPhp(pRef As %String, Output pSC As %Status) As %DynamicObject
{
    Set pSC = $$$OK
    Set tHost = $SYSTEM.Util.GetEnviron("PHP_HOST")
    Set:tHost="" tHost = "php-service"
    Set tPort = $SYSTEM.Util.GetEnviron("PHP_PORT")
    Set:tPort="" tPort = 8080

    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Server = tHost
    Set tReq.Port = tPort
    Set tReq.ContentType = "application/json"
    Set tReq.Timeout = 10
    Do tReq.EntityBody.Write({"declarationRef":(pRef)}.%ToJSON())

    Set pSC = tReq.Post("/duty/calculate")
    If $$$ISERR(pSC) Quit {}
    If tReq.HttpResponse.StatusCode '= 200 {
        Set pSC = $$$ERROR($$$GeneralError, "PHP HTTP "_tReq.HttpResponse.StatusCode)
        Quit {}
    }

    Quit ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
}

/// Shadow the call to PHP and compare. Errors are swallowed on
/// purpose: in SHADOW mode the consumer's answer is already decided.
ClassMethod ShadowAndCompare(
    pRef As %String,
    pCobolResp As %DynamicObject,
    pOperation As %String,
    pRoute As JKDM.Config.RouteMode)
{
    Try {
        Set tPhp = ..CallPhp(pRef, .tSC)
        If $$$ISERR(tSC) {
            // Shadow backend down. Log it; do not surface it.
            Do ##class(JKDM.Msg.ComparisonResult).%New()
            Quit
        }
        Do ##class(JKDM.BP.Comparator).Compare(
            pOperation, pRef, pCobolResp, tPhp,
            pRoute.ComparisonRuleClass, $JOB)
    }
    Catch {
        // Deliberately silent.
    }
}


/// The manifest contract. Same router, same three modes, same
/// comparator - a second operation costs one method and one route
/// row, which is the point of putting the decision in a table.
ClassMethod ManifestLookup(pRef As %String) As %Status
{
    #dim tSC As %Status = $$$OK
    Try {
        Set tRef = $ZSTRIP(pRef, "<>W")
        If tRef = "" {
            Set %response.Status = 400
            Write {"error":"manifest reference required"}.%ToJSON()
            Quit
        }

        Set tOperation = "manifest.lookup"
        Set tRoute = ##class(JKDM.Config.RouteMode).Resolve(tOperation)
        Set tMode = tRoute.Mode

        Set %response.Headers("X-SMK-Route-Mode") = tMode

        If tMode = "LIVE_NEW" {
            Set tResp = ..ManifestPhp(tRef, .tSC)
            Set %response.Headers("X-SMK-Backend") = "PHP"
        }
        Else {
            Set tResp = ..ManifestCobol(tRef, .tSC)
            Set %response.Headers("X-SMK-Backend") = "COBOL"

            If tMode = "SHADOW" {
                Do ..ShadowManifest(tRef, tResp, tOperation, tRoute)
            }
        }

        If $$$ISERR(tSC) {
            If $SYSTEM.Status.GetErrorText(tSC) [ "404" {
                Set %response.Status = 404
                Write {"error":"manifest not found"}.%ToJSON()
                Quit
            }
            Set %response.Status = 502
            Write {"error":"backend unavailable"}.%ToJSON()
            Quit
        }

        Write tResp.%ToJSON()
    }
    Catch ex {
        Set %response.Status = 500
        Write {"error":(ex.DisplayString())}.%ToJSON()
    }
    Quit $$$OK
}

ClassMethod ManifestCobol(pRef As %String, Output pSC As %Status) As %DynamicObject
{
    Set pSC = $$$OK
    Set tHost = $SYSTEM.Util.GetEnviron("COBOL_HOST")
    Set:tHost="" tHost = "cobol-core"
    Set tPort = $SYSTEM.Util.GetEnviron("COBOL_PORT")
    Set:tPort="" tPort = 8080

    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Server = tHost
    Set tReq.Port = tPort

    Set pSC = tReq.Get("/manifest/"_pRef)
    If $$$ISERR(pSC) Quit {}
    If tReq.HttpResponse.StatusCode '= 200 {
        Set pSC = $$$ERROR($$$GeneralError, "COBOL HTTP "_tReq.HttpResponse.StatusCode)
        Quit {}
    }

    Set tRaw = ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
    Quit ##class(JKDM.Util.ManifestParser).ToCanonical(tRaw.raw, tRaw.lines)
}

ClassMethod ManifestPhp(pRef As %String, Output pSC As %Status) As %DynamicObject
{
    Set pSC = $$$OK
    Set tHost = $SYSTEM.Util.GetEnviron("PHP_HOST")
    Set:tHost="" tHost = "php-service"
    Set tPort = $SYSTEM.Util.GetEnviron("PHP_PORT")
    Set:tPort="" tPort = 8080

    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Server = tHost
    Set tReq.Port = tPort
    Set tReq.Timeout = 10

    Set pSC = tReq.Get("/manifest/"_pRef)
    If $$$ISERR(pSC) Quit {}
    If tReq.HttpResponse.StatusCode '= 200 {
        Set pSC = $$$ERROR($$$GeneralError, "PHP HTTP "_tReq.HttpResponse.StatusCode)
        Quit {}
    }

    Quit ##class(%DynamicObject).%FromJSON(tReq.HttpResponse.Data)
}

ClassMethod ShadowManifest(
    pRef As %String,
    pCobolResp As %DynamicObject,
    pOperation As %String,
    pRoute As JKDM.Config.RouteMode)
{
    Try {
        Set tPhp = ..ManifestPhp(pRef, .tSC)
        Quit:$$$ISERR(tSC)
        Do ##class(JKDM.BP.Comparator).Compare(
            pOperation, pRef, pCobolResp, tPhp,
            pRoute.ComparisonRuleClass, $JOB)
    }
    Catch {
        // Deliberately silent - see ShadowAndCompare.
    }
}

ClassMethod ListRoutes() As %Status
{
    Set tArr = []
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT OperationName, Mode, AuthoritativeBackend, ChangeReason, Fiscal "_
        "FROM JKDM_Config.RouteMode ORDER BY OperationName")
    While tRs.%Next() {
        Do tArr.%Push({
            "operation": (tRs.%GetData(1)),
            "mode": (tRs.%GetData(2)),
            "authoritative": (tRs.%GetData(3)),
            "reason": (tRs.%GetData(4)),
            "fiscal": (''+tRs.%GetData(5)),
            "modesAvailable": ($SELECT(tRs.%GetData(5): "LEGACY (locked - fiscal)", 1: "LEGACY, SHADOW, LIVE_NEW"))
        })
    }
    Write tArr.%ToJSON()
    Quit $$$OK
}

/// Change the routing mode for an operation.
///
/// Three outcomes, and they are deliberately different status codes:
///   200  changed
///   400  the mode is not a mode - a malformed request
///   409  understood, and refused on policy - the operation is fiscal
ClassMethod SetRoute(pOp As %String, pMode As %String) As %Status
{
    If '$LISTFIND($LISTBUILD("LEGACY", "SHADOW", "LIVE_NEW"), pMode) {
        Set %response.Status = 400
        Write {"error":"mode must be one of LEGACY, SHADOW, LIVE_NEW","received":(pMode)}.%ToJSON()
        Quit $$$OK
    }

    Set tRoute = ##class(JKDM.Config.RouteMode).Resolve(pOp)
    If tRoute.Fiscal, pMode '= "LEGACY" {
        // Refused on policy, and the caller is told which policy rather
        // than handed our internal error text.
        Set %response.Status = 409
        Set tMsg = pOp_" is a fiscal operation and is locked to LEGACY"
        Write {"error":(tMsg),"policy":"fiscal","reference":"SMK 5.8"}.%ToJSON()
        Quit $$$OK
    }

    Set tSC = ##class(JKDM.Config.RouteMode).Set(pOp, pMode, "changed via API")
    If $$$ISERR(tSC) {
        Set %response.Status = 500
        Write {"error":"could not update the routing table"}.%ToJSON()
        Quit $$$OK
    }

    Write {"operation":(pOp),"mode":(pMode)}.%ToJSON()
    Quit $$$OK
}

/// Equivalence evidence, per operation.
///
/// Reports a rate for every operation that has actually been shadowed
/// rather than a single hardcoded one - a fiscal operation is locked to
/// LEGACY and will never appear here, which is correct and not an
/// error.
ClassMethod ListComparisons() As %Status
{
    Set tRates = {}
    Set tOps = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT DISTINCT %EXACT(OperationName) FROM JKDM_Msg.ComparisonResult")
    While tOps.%Next() {
        Set tOp = tOps.%GetData(1)
        Do tRates.%Set(tOp, ##class(JKDM.Msg.ComparisonResult).EquivalenceRate(tOp))
    }

    Set tArr = []
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TOP 50 ID, OperationName, DeclarationRef, Verdict, ComparedAt "_
        "FROM JKDM_Msg.ComparisonResult ORDER BY ID DESC")
    While tRs.%Next() {
        Do tArr.%Push({
            "id": (tRs.%GetData(1)),
            "operation": (tRs.%GetData(2)),
            "reference": (tRs.%GetData(3)),
            "verdict": (tRs.%GetData(4)),
            "comparedAt": (tRs.%GetData(5))
        })
    }

    Write {"equivalenceRate": (tRates), "recent": (tArr)}.%ToJSON()
    Quit $$$OK

}

}
