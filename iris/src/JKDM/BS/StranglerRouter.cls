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

/// Mounted by docker-compose - see the iris service. The console needs
/// to reach the same three directories the shell scripts reach.
Parameter SAMPLES = "/opt/jkdm/edi";

Parameter DROP = "/opt/jkdm/drop/cusdec";

Parameter ACK = "/opt/jkdm/ack";

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
  <Route Url="/report/:which"   Method="GET"  Call="ReportView"/>
  <Route Url="/drop/:what"      Method="POST" Call="Drop"/>
  <Route Url="/failmode/:mode"  Method="PUT"  Call="FailMode"/>
  <Route Url="/reset"           Method="POST" Call="Reset"/>
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

/// A request object pointed at one of the two backends.
///
/// Four copies of this env lookup drifted apart once already. One copy,
/// two callers each.
ClassMethod Backend(pWhich As %String) As %Net.HttpRequest [ Private ]
{
    Set tHost = $SYSTEM.Util.GetEnviron(pWhich_"_HOST")
    Set:tHost="" tHost = $SELECT(pWhich = "PHP": "php-service", 1: "cobol-core")
    Set tPort = $SYSTEM.Util.GetEnviron(pWhich_"_PORT")
    Set:tPort="" tPort = 8080

    Set tReq = ##class(%Net.HttpRequest).%New()
    Set tReq.Server = tHost
    Set tReq.Port   = tPort
    Quit tReq
}

/// Call the COBOL core and normalise its fixed-width response into
/// the canonical shape. See JKDM.Util.CobolParser for why this matters.
ClassMethod CallCobol(pRef As %String, Output pSC As %Status) As %DynamicObject
{
    Set pSC = $$$OK
    Set tReq = ..Backend("COBOL")
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
    Set tReq = ..Backend("PHP")
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
    Set tReq = ..Backend("COBOL")

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
    Set tReq = ..Backend("PHP")
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


/// The console: the whole demo behind buttons, served by IRIS itself.
///
/// The page is a plain file at /opt/jkdm/web/console.html rather than a
/// wall of Write statements. That is not tidiness - escaping JavaScript
/// inside ObjectScript string literals broke this page once already,
/// and a mounted file can be edited between sessions without a rebuild.
///
///   http://localhost:52774/jkdm/console
///
/// Nothing here is privileged. Every button is a call the room can make
/// with curl, and the terminal pane prints that curl before it runs -
/// the console is a face on the API, not a second way in.
ClassMethod Console() As %Status
{
    Set %response.ContentType = "text/html"

    Set tFile = ##class(%Stream.FileCharacter).%New()
    Set tSC = tFile.LinkToFile("/opt/jkdm/web/console.html")
    If $$$ISERR(tSC) {
        Set %response.Status = 500
        Write "console.html is not mounted - check the iris volumes in docker-compose.yml"
        Quit $$$OK
    }

    While 'tFile.AtEnd { Write tFile.Read(16000) }
    Quit $$$OK
}

/// Terminal reports, straight down the wire as text.
///
/// JKDM.Util.Report already formats these for a terminal, and in a CSP
/// method the current device IS the HTTP response - so its Write
/// statements land in the body untouched. No second copy of the
/// reporting logic, and the console shows byte-for-byte what
/// ./scripts/audit.sh shows.
ClassMethod ReportView(pWhich As %String) As %Status
{
    Set %response.ContentType = "text/plain"

    If pWhich = "audit"          { Do ##class(JKDM.Util.Report).Audit() }
    ElseIf pWhich = "equivalence"   { Do ##class(JKDM.Util.Report).Equivalence() }
    ElseIf pWhich = "diffs"         { Do ##class(JKDM.Util.Report).Diffs() }
    ElseIf pWhich = "combined"      { Do ##class(JKDM.Util.Report).Combined() }
    ElseIf pWhich = "m-equivalence" { Do ##class(JKDM.Util.Report).Equivalence("manifest.lookup") }
    ElseIf pWhich = "m-diffs"       { Do ##class(JKDM.Util.Report).Diffs(12, "manifest.lookup") }
    Else {
        Set %response.Status = 404
        Write "no such report: ", pWhich
    }
    Quit $$$OK
}

/// Drop sample EDIFACT files into the partner's directory.
///
/// This is the PARTNER acting, not us - exactly what drop-edi.sh does,
/// and deliberately still a plain file copy into the drop directory
/// rather than anything clever. IRIS then notices on its next poll,
/// with no knowledge that a button was involved.
ClassMethod Drop(pWhat As %String) As %Status
{
    Set %response.ContentType = "text/plain"

    // The name reaches the filesystem, so it does not get to contain a
    // path. Everything the console offers is a keyword; a raw filename
    // is accepted too, and that is the one that needs the guard.
    Set tSet = ""
    If pWhat = "one"      { Set tSet = $LISTBUILD("CUSDEC_K1-2026-000101.edi") }
    ElseIf pWhat = "bad"  { Set tSet = $LISTBUILD("CUSDEC_MALFORMED.edi", "CUSDEC_UNPRICEABLE.edi") }
    ElseIf pWhat = "manifest" { Set tSet = $LISTBUILD("CUSCAR_MANIFEST.edi") }
    ElseIf pWhat = "all" {
        Set tRs = ##class(%ResultSet).%New("%File:FileSet")
        Do tRs.Execute(..#SAMPLES, "CUSDEC_K1-*.edi")
        While tRs.Next() { Set tSet = tSet_$LISTBUILD(##class(%File).GetFilename(tRs.Get("Name"))) }
        Do tRs.Close()
    }
    Else {
        If (pWhat [ "/") || (pWhat [ "..") || ($EXTRACT(pWhat, *-3, *) '= ".edi") {
            Set %response.Status = 400
            Write "rejected: expected one|all|bad|manifest or a plain .edi filename"
            Quit $$$OK
        }
        Set tSet = $LISTBUILD(pWhat)
    }

    Set tDrop = ..#DROP
    If '##class(%File).DirectoryExists(tDrop) {
        Set %response.Status = 500
        Write "the partner drop directory is not mounted - check the iris volumes"
        Quit $$$OK
    }

    Set tDropped = 0
    For i = 1:1:$LISTLENGTH(tSet) {
        Set tName = $LIST(tSet, i)
        Set tSrc  = ##class(%File).NormalizeFilename(tName, ..#SAMPLES)
        If '##class(%File).Exists(tSrc) {
            Write "  no such sample: ", tName, !
            Continue
        }
        If ##class(%File).CopyFile(tSrc, ##class(%File).NormalizeFilename(tName, tDrop)) {
            Set tDropped = tDropped + 1
            Write "  dropped ", tName, !
        }
        Else {
            Write "  FAILED to drop ", tName, !
        }
    }

    If tDropped = 0 {
        Set %response.Status = 404
        Write "nothing dropped", !
        Quit $$$OK
    }

    Write !, tDropped, " file(s) in the partner drop. IRIS polls every 5 seconds.", !
    Write "Open the ingestion trail in a moment to watch them land.", !
    Quit $$$OK
}

/// Break the PHP backend on purpose, or put it back.
///
/// In SHADOW the consumer's answer is already decided by COBOL, so a
/// dead shadow backend must change nothing anyone outside can see.
/// That is a property people assume rather than test - this is the
/// button that tests it in front of them.
///
/// php-service owns the file and IRIS has no shell in that container,
/// so this is an HTTP call to a route that exists for exactly this.
ClassMethod FailMode(pMode As %String) As %Status
{
    Set %response.ContentType = "text/plain"

    If '$LISTFIND($LISTBUILD("on", "hang", "off"), pMode) {
        Set %response.Status = 400
        Write "mode must be one of on, hang, off"
        Quit $$$OK
    }

    Set tReq = ..Backend("PHP")
    Set tReq.Timeout = 10
    Set tSC = tReq.Put("/failmode/"_pMode)

    If $$$ISERR(tSC) || (tReq.HttpResponse.StatusCode '= 200) {
        Set %response.Status = 502
        Write "could not reach php-service to set fail mode"
        Quit $$$OK
    }

    Write "php-service fail mode = ", pMode, !
    If pMode = "off" {
        Write "Backend healthy again.", !
    }
    Else {
        Write !, "Now call the consumer contract. In SHADOW nobody outside should notice.", !
    }
    Quit $$$OK
}

/// Back to a clean start state - the console half of reset.sh.
///
/// Clears the audit trail, the comparison evidence, the partner
/// directories, the manifest route and the fail mode. Touches no seed
/// data and nobody's code.
///
/// duty.calculate is not reset because it cannot move: it is fiscal and
/// locked to LEGACY, so it is already where reset would put it.
ClassMethod Reset() As %Status
{
    Set %response.ContentType = "text/plain"

    Do ##class(JKDM.Msg.FileAuditRecord).%DeleteExtent()
    Do ##class(JKDM.Msg.ComparisonResult).%DeleteExtent()
    Write "cleared the audit trail and the comparison evidence", !

    Set tGone = ..Purge(..#DROP, "*.edi")
              + ..Purge(..#ACK, "*.aperak")
              + ..Purge(..#ACK, "*.contrl")
    Write "cleared ", tGone, " file(s) from the partner directories", !

    Do ##class(JKDM.Config.RouteMode).Set("manifest.lookup", "LEGACY", "reset from the console")
    Write "manifest.lookup is back to LEGACY", !

    Set tReq = ..Backend("PHP")
    Set tReq.Timeout = 10
    If $$$ISOK(tReq.Put("/failmode/off")) {
        Write "php-service fail mode is off", !
    }
    Else {
        Write "could not reach php-service - check its fail mode by hand", !
    }

    Write !, "Clean. No files ingested, no comparisons, both routes LEGACY.", !
    Quit $$$OK
}

/// Delete matching files from a directory, returning how many went.
ClassMethod Purge(
    pDir As %String,
    pPattern As %String) As %Integer [ Private ]
{
    Set tCount = 0
    Quit:'##class(%File).DirectoryExists(pDir) 0

    Set tRs = ##class(%ResultSet).%New("%File:FileSet")
    Do tRs.Execute(pDir, pPattern)
    While tRs.Next() {
        If ##class(%File).Delete(tRs.Get("Name")) { Set tCount = tCount + 1 }
    }
    Do tRs.Close()
    Quit tCount
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
