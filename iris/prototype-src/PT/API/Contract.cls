/// The prototype's public contract.
///
/// Same shapes as /jkdm, on purpose. A consumer cannot tell the
/// difference between this and the tender stack from the outside,
/// which is the only honest way to compare them.
Class PT.API.Contract Extends %CSP.REST
{

Parameter CHARSET = "utf-8";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/health"          Method="GET"  Call="Health"/>
  <Route Url="/duty/calculate"  Method="POST" Call="Duty"/>
  <Route Url="/duty/python"     Method="POST" Call="DutyPython"/>
  <Route Url="/manifest/:ref"   Method="GET"  Call="Manifest"/>
  <Route Url="/ingest"          Method="POST" Call="Ingest"/>
  <Route Url="/explain"         Method="GET"  Call="Explain"/>
  <Route Url="/sql"             Method="GET"  Call="Sql"/>
</Routes>
}

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
    Write {"status":"UP","namespace":($NAMESPACE),"role":"application + data + interop"}.%ToJSON()
    Quit $$$OK
}

ClassMethod Duty() As %Status
{
    Set tBody = ##class(%DynamicObject).%FromJSON(%request.Content)
    Set tRef = $ZSTRIP(tBody.declarationRef, "<>W")
    Set tOut = ##class(PT.Svc.Duty).Calculate(tRef)
    If tOut.status = "NOT_FOUND" {
        Set %response.Status = 404
    }
    Write tOut.%ToJSON()
    Quit $$$OK
}

/// The identical calculation, in Python. Same data, same storage.
ClassMethod DutyPython() As %Status
{
    Set tBody = ##class(%DynamicObject).%FromJSON(%request.Content)
    Set tRef = $ZSTRIP(tBody.declarationRef, "<>W")
    Set tOut = ##class(PT.Svc.DutyPy).Calculate(tRef)
    If tOut.status = "NOT_FOUND" {
        Set %response.Status = 404
    }
    Write tOut.%ToJSON()
    Quit $$$OK
}

ClassMethod Manifest(pRef As %String) As %Status
{
    Set tOut = ##class(PT.Svc.Manifest).Lookup($ZSTRIP(pRef, "<>W"))
    If tOut.status = "NOT_FOUND" {
        Set %response.Status = 404
    }
    Write tOut.%ToJSON()
    Quit $$$OK
}

/// Post a raw EDIFACT interchange. It is parsed, PERSISTED and priced
/// in one call - the thing the main POC deliberately cannot do.
ClassMethod Ingest() As %Status
{
    Set tRaw = ""
    If $IsObject(%request.Content) {
        Do %request.Content.Rewind()
        While '%request.Content.AtEnd {
            Set tRaw = tRaw_%request.Content.Read(32000)
        }
    }

    // Without a content type CSP form-decodes the body and Content is
    // never populated. Say that plainly rather than fail on an OREF.
    If tRaw = "" {
        Set %response.Status = 400
        Write {"error":"send the interchange as the request body with Content-Type: text/plain"}.%ToJSON()
        Quit $$$OK
    }

    Set tOut = ##class(PT.Svc.Intake).FromEdifact(tRaw)
    If tOut.status = "REJECTED" {
        Set %response.Status = 422
    }
    Write tOut.%ToJSON()
    Quit $$$OK
}

/// What one class definition is doing here, counted rather than claimed.
ClassMethod Explain() As %Status
{
    Set tArr = []
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES "_
        "WHERE TABLE_SCHEMA = 'PT_Data' ORDER BY TABLE_NAME")
    While tRs.%Next() {
        Do tArr.%Push(tRs.%GetData(1))
    }

    Write {
        "artefactsPerEntity": {
            "tenderStack": ["Eloquent model", "Laravel migration", "Postgres table"],
            "prototype": ["one class definition"]
        },
        "sqlTablesProjected": (tArr),
        "note": "Every table above is a class. Nothing generated them, nothing keeps them in sync.",
        "tiers": {
            "tenderStack": ["NGINX", "PHP-FPM", "Laravel", "EDB Postgres", "IRIS"],
            "prototype": ["IRIS"]
        },
        "honest": "Fewer moving parts to operate. Not a claim about throughput, and not a proposal to change the tender."
    }.%ToJSON()
    Quit $$$OK
}

/// Prove the objects and the SQL are the same data, not a copy.
ClassMethod Sql() As %Status
{
    Set tArr = []
    Set tRs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT d.DeclRef, COUNT(l.LineNo) AS Lines, SUM(l.CustomsValue) AS Value "_
        "FROM PT_Data.Declaration d "_
        "LEFT JOIN PT_Data.DeclarationLine l ON l.Declaration = d.DeclRef "_
        "GROUP BY d.DeclRef ORDER BY d.DeclRef")
    While tRs.%Next() {
        Do tArr.%Push({
            "declarationRef": (tRs.%GetData(1)),
            "lines": (tRs.%GetData(2)),
            "customsValue": (tRs.%GetData(3))
        })
    }
    Write {
        "query": "SELECT ... FROM PT_Data.Declaration JOIN PT_Data.DeclarationLine",
        "rows": (tArr),
        "note": "Same objects the calculation walked. No ORM, no mapping, no second copy."
    }.%ToJSON()
    Quit $$$OK
}

}
