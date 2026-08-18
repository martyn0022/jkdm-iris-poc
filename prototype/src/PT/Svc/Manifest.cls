/// Manifest lookup, natively.
Class PT.Svc.Manifest Extends %RegisteredObject
{

ClassMethod Lookup(pRef As %String) As %DynamicObject
{
    Set tMan = ##class(PT.Data.Manifest).%OpenId(pRef)
    If '$IsObject(tMan) {
        Quit {"status":"NOT_FOUND","manifestRef":(pRef)}
    }

    Set tCons = []
    Set tTotal = 0
    For i = 1:1:tMan.Consignments.Count() {
        Set tC = tMan.Consignments.GetAt(i)
        Set tTotal = tTotal + tC.GrossKg
        Do tCons.%Push({
            "lineNo": (tC.LineNo),
            "consignmentRef": (tC.ConsignmentRef),
            "containerCount": (tC.ContainerCount),
            "grossKg": (tC.GrossKg),
            "description": (tC.Description)
        })
    }

    Quit {
        "status": "OK",
        "manifestRef": (tMan.ManifestRef),
        "vesselId": (tMan.VesselId),
        "vesselName": (tMan.VesselName),
        "voyageNumber": (tMan.VoyageNo),
        "carrierTin": (tMan.CarrierTin),
        "portOfDischarge": (tMan.PortOfDischarge),
        "eta": (tMan.Eta),
        "statusCode": (##class(PT.Data.Manifest).StatusName(tMan.StatusCode)),
        "consignmentCount": (tCons.%Size()),
        "totalGrossKg": (tTotal),
        "consignments": (tCons),
        "backend": "IRIS"
    }
}

}
