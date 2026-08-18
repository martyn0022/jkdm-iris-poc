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
  <Route Url="/console"         Method="GET"  Call="Console"/>
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


/// A clickable routing console, served by IRIS itself.
///
/// The routing table is the control surface for the whole transition,
/// and driving it from curl makes it look like a developer toy. This
/// is the same three modes behind a page anyone can operate.
///
///   http://localhost:52774/jkdm/console
///
/// It changes nothing the API does not already expose - every button
/// is a PUT to /routes/{op}/{mode}, including the refusal on a fiscal
/// operation.
ClassMethod Console() As %Status
{
    Set %response.ContentType = "text/html"

    Write "<!doctype html><html><head><meta charset='utf-8'>", !
    Write "<meta name='viewport' content='width=device-width,initial-scale=1'>", !
    Write "<title>SMK routing console</title><style>", !
    Write ":root{--bg:#FBFBFC;--fg:#10151C;--mut:#5C6875;--line:#DBE0E6;", !
    Write "--card:#FFF;--acc:#0E6B6B;--accbg:#E0EFED;--warn:#A8271A;--warnbg:#F7E9E7}", !
    Write "@media(prefers-color-scheme:dark){:root{--bg:#0C1117;--fg:#E9EDF2;--mut:#8B95A1;", !
    Write "--line:#23303E;--card:#141C25;--acc:#4ECDC4;--accbg:#10322F;--warn:#FF9184;--warnbg:#2A1613}}", !
    Write "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);", !
    Write "font:15px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;padding:2rem 1.5rem 4rem}", !
    Write "main{max-width:56rem;margin:0 auto}", !
    Write "h1{font-size:1.6rem;letter-spacing:-.02em;margin:0 0 .3rem}", !
    Write "p.sub{color:var(--mut);margin:0 0 2rem}", !
    Write ".op{background:var(--card);border:1px solid var(--line);border-radius:4px;", !
    Write "padding:1.1rem 1.3rem;margin-bottom:1rem}", !
    Write ".op h2{font-size:1.05rem;margin:0 0 .2rem;font-family:ui-monospace,monospace}", !
    Write ".op .meta{color:var(--mut);font-size:.82rem;margin-bottom:.9rem}", !
    Write ".modes{display:flex;gap:.5rem;flex-wrap:wrap}", !
    Write "button{font:inherit;font-size:.85rem;padding:.45rem 1rem;border-radius:3px;", !
    Write "border:1px solid var(--line);background:transparent;color:var(--fg);cursor:pointer}", !
    Write "button:hover:not(:disabled){border-color:var(--acc)}", !
    Write "button.now{background:var(--accbg);border-color:var(--acc);color:var(--acc);font-weight:600}", !
    Write "button:disabled{opacity:.4;cursor:not-allowed}", !
    Write ".lock{display:inline-block;font-size:.7rem;letter-spacing:.08em;text-transform:uppercase;", !
    Write "background:var(--warnbg);color:var(--warn);padding:.15rem .5rem;border-radius:2px;margin-left:.5rem}", !
    Write "#msg{margin:1rem 0;padding:.8rem 1rem;border-radius:3px;font-size:.88rem;display:none}", !
    Write "#msg.err{display:block;background:var(--warnbg);color:var(--warn)}", !
    Write "#msg.ok{display:block;background:var(--accbg);color:var(--acc)}", !
    Write "h3{font-size:.72rem;letter-spacing:.12em;text-transform:uppercase;color:var(--mut);", !
    Write "margin:2.5rem 0 .6rem;font-family:ui-monospace,monospace}", !
    Write "table{width:100%;border-collapse:collapse;font-size:.85rem}", !
    Write "th,td{text-align:left;padding:.45rem .6rem .45rem 0;border-bottom:1px solid var(--line)}", !
    Write "th{font-size:.68rem;letter-spacing:.1em;text-transform:uppercase;color:var(--mut)}", !
    Write "td{color:var(--mut);font-family:ui-monospace,monospace;font-size:.8rem}", !
    Write ".v{font-weight:600}.v.FISCAL_DIFF{color:var(--warn)}.v.EQUIVALENT{color:var(--acc)}", !
    Write "</style></head><body><main>", !
    Write "<h1>SMK routing console</h1>", !
    Write "<p class='sub'>One row per operation. Changing a mode changes which implementation answers &mdash; ", !
    Write "no deployment, no consumer change. What counts as equivalent is decided elsewhere and arrives here as configuration.</p>", !
    Write "<div id='msg'></div><div id='ops'></div>", !
    Write "<h3>Comparison evidence</h3><div id='ev'></div>", !
    Write "</main><script>", !
    Write "const M=['LEGACY','SHADOW','LIVE_NEW'];", !
    Write "function say(t,k){const m=document.getElementById('msg');m.textContent=t;m.className=k;}", !
    Write "async function load(){", !
    Write " const r=await fetch('routes'); const rows=await r.json();", !
    Write " document.getElementById('ops').innerHTML=rows.map(o=>{", !
    Write "  const lock=o.fiscal==1?""<span class='lock'>fiscal &middot; locked</span>"":'';", !
    Write "  const btns=M.map(m=>{", !
    Write "   const cur=m==o.mode?' now':'';", !
    Write "   const dis=(o.fiscal==1&&m!='LEGACY')?' disabled':'';", !
    Write "   return ""<button class='mode""+cur+""'""+dis+"" onclick=\""setMode('""+o.operation+""','""+m+""')\"">""+m+'</button>';", !
    Write "  }).join('');", !
    Write "  return ""<div class='op'><h2>""+o.operation+lock+""</h2>""", !
    Write "   +""<div class='meta'>answered by ""+o.authoritative+"" &middot; ""+o.modesAvailable+""</div>""", !
    Write "   +""<div class='modes'>""+btns+'</div></div>';", !
    Write " }).join('');", !
    Write " const e=await (await fetch('comparisons')).json();", !
    Write " const rec=e.recent||[];", !
    Write " if(!rec.length){document.getElementById('ev').innerHTML=""<p style='color:var(--mut);font-size:.85rem'>Nothing compared yet. Put an operation into SHADOW and call it.</p>"";return;}", !
    Write " let h=""<table><tr><th>operation</th><th>reference</th><th>verdict</th><th>when</th></tr>"";", !
    Write " for(const c of rec){h+=""<tr><td>""+c.operation+""</td><td>""+c.reference+""</td><td class='v ""+c.verdict+""'>""+c.verdict+""</td><td>""+c.comparedAt+""</td></tr>"";}", !
    Write " document.getElementById('ev').innerHTML=h+""</table>"";", !
    Write "}", !
    Write "async function setMode(op,m){", !
    Write " const r=await fetch('routes/'+op+'/'+m,{method:'PUT'});", !
    Write " const b=await r.json();", !
    Write " if(r.ok){say(op+' is now '+m,'ok');}else{say(b.error||'refused','err');}", !
    Write " load();", !
    Write "}", !
    Write "load();setInterval(load,5000);", !
    Write "</script></body></html>", !
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
