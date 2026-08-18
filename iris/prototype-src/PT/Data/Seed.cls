/// Seed the prototype with the SAME values Postgres holds.
///
/// Identical data on purpose: if the prototype and the COBOL core
/// disagree, it has to be the logic, never the data. Same discipline
/// as generator/generate_flatfile.py in the main POC.
Class PT.Data.Seed Extends %RegisteredObject
{

ClassMethod Run() As %Status
{
    Do ##class(PT.Data.DeclarationLine).%DeleteExtent()
    Do ##class(PT.Data.Declaration).%DeleteExtent()
    Do ##class(PT.Data.TariffRate).%DeleteExtent()
    Do ##class(PT.Data.FtaRule).%DeleteExtent()
    Do ##class(PT.Data.ManifestConsignment).%DeleteExtent()
    Do ##class(PT.Data.Manifest).%DeleteExtent()

    Do ..Tariff("8471.30.10", "Portable automatic data processing machines weighing not more than 10 kg", .05, .10, "UNT")
    Do ..Tariff("8517.12.00", "Telephones for cellular networks or for other wireless networks", .075, .10, "UNT")
    Do ..Tariff("6109.10.00", "T-shirts, singlets and other vests, knitted or crocheted, of cotton", .025, .10, "PCE")
    Do ..Tariff("8703.23.90", "Motor cars with spark-ignition internal combustion engine, 1500-3000cc", .10, .10, "UNT")
    Do ..Tariff("3304.99.90", "Beauty or make-up preparations and preparations for the care of the skin", .035, .10, "KGM")
    Do ..Tariff("9403.60.90", "Wooden furniture of a kind used in the bedroom, other than seats", .065, .10, "PCE")
    Do ..Tariff("4011.10.00", "New pneumatic tyres of rubber of a kind used on motor cars", .045, .10, "PCE")
    Do ..Tariff("1006.30.99", "Semi-milled or wholly milled rice, whether or not polished or glazed", .20, 0, "KGM")

    Do ..Fta("ATIGA", "8471.30.10", "TH", 0, 40)
    Do ..Fta("ATIGA", "8517.12.00", "VN", 0, 40)
    Do ..Fta("ATIGA", "1006.30.99", "TH", 0, 40)
    Do ..Fta("AKFTA", "8703.23.90", "KR", .05, 45)
    Do ..Fta("MTFTA", "4011.10.00", "JP", .02, 40)

    Do ..Decl("K1-2026-000101", "C12345678901", "CN", "", "")
    Do ..Line("K1-2026-000101", 1, "8471.30.10", 10, 20000)
    Do ..Line("K1-2026-000101", 2, "8517.12.00", 5, 10000)

    Do ..Decl("K1-2026-000102", "C12345678902", "US", "", "")
    Do ..Line("K1-2026-000102", 1, "6109.10.00", 100, 4000)
    Do ..Line("K1-2026-000102", 2, "9403.60.90", 20, 8000)

    Do ..Decl("K1-2026-000103", "C12345678903", "DE", "", "")
    Do ..Line("K1-2026-000103", 1, "4011.10.00", 40, 6000)

    // The seven-line declaration the whole rounding argument turns on.
    Do ..Decl("K1-2026-000104", "C12345678904", "CN", "", "")
    Do ..Line("K1-2026-000104", 1, "8471.30.10", 1, 1234.55)
    Do ..Line("K1-2026-000104", 2, "8517.12.00", 1, 2345.67)
    Do ..Line("K1-2026-000104", 3, "6109.10.00", 1, 987.65)
    Do ..Line("K1-2026-000104", 4, "8703.23.90", 1, 4567.89)
    Do ..Line("K1-2026-000104", 5, "3304.99.90", 1, 3210.55)
    Do ..Line("K1-2026-000104", 6, "9403.60.90", 1, 1876.33)
    Do ..Line("K1-2026-000104", 7, "4011.10.00", 1, 2999.99)

    // Sits exactly on the FTA threshold.
    Do ..Decl("K1-2026-000105", "C12345678905", "TH", "ATIGA", 40)
    Do ..Line("K1-2026-000105", 1, "1006.30.99", 3000, 3000)

    Do ..Decl("K1-2026-000106", "C12345678906", "TH", "ATIGA", 55)
    Do ..Line("K1-2026-000106", 1, "1006.30.99", 2000, 2000)

    Do ..Manifest("MANIFEST-2026-0041", "9V-8841", "MV BINTANG SATU", "VOY-8841", "C99000000001", "MYPKG", "2026-08-20 06:00:00", "RL", 24000)
    Do ..Cons("MANIFEST-2026-0041", 1, "CN-88410001", 120, 12000, "Consolidated consumer electronics and accessories")
    Do ..Cons("MANIFEST-2026-0041", 2, "CN-88410002", 60, 8000, "Knitted cotton apparel in cartons")
    Do ..Cons("MANIFEST-2026-0041", 3, "CN-88410003", 20, 4000, "Rubber tyres for passenger vehicles")

    Do ..Manifest("MANIFEST-2026-0044", "9V-8844", "MV KOTA MERDEKA", "VOY-8844", "C99000000004", "MYPKG", "2026-08-23 18:45:00", "RL", 31200)
    Do ..Cons("MANIFEST-2026-0044", 1, "CN-88440001", 100, 15000, "Motor vehicle parts and assemblies")
    Do ..Cons("MANIFEST-2026-0044", 2, "CN-88440002", 70, 10200, "Portable data processing machines")
    Do ..Cons("MANIFEST-2026-0044", 3, "CN-88440003", 45, 6000, "Assorted household goods")

    Quit $$$OK
}

ClassMethod Tariff(pHS, pDesc, pDuty, pSst, pUom) [ Private ]
{
    Set t = ##class(PT.Data.TariffRate).%New()
    Set t.HSCode = pHS, t.Description = pDesc
    Set t.DutyRate = pDuty, t.SstRate = pSst, t.Uom = pUom
    Do t.%Save()
}

ClassMethod Fta(pFta, pHS, pOrigin, pRate, pMin) [ Private ]
{
    Set f = ##class(PT.Data.FtaRule).%New()
    Set f.FtaCode = pFta, f.HSCode = pHS, f.OriginCountry = pOrigin
    Set f.PrefRate = pRate, f.MinLocalPct = pMin
    Do f.%Save()
}

ClassMethod Decl(pRef, pTin, pOrigin, pFta, pPct) [ Private ]
{
    Set d = ##class(PT.Data.Declaration).%New()
    Set d.DeclRef = pRef, d.DeclType = "K1", d.DeclarantTin = pTin
    Set d.OriginCountry = pOrigin, d.FtaClaimed = pFta
    Set:pPct'="" d.LocalPct = pPct
    Set d.Source = "SEED"
    Do d.%Save()
}

ClassMethod Line(pRef, pNo, pHS, pQty, pValue) [ Private ]
{
    Set d = ##class(PT.Data.Declaration).%OpenId(pRef)
    Quit:'$IsObject(d)
    Set l = ##class(PT.Data.DeclarationLine).%New()
    Set l.Declaration = d
    Set l.LineNo = pNo, l.HSCode = pHS
    Set l.Quantity = pQty, l.CustomsValue = pValue
    Do l.%Save()
}

ClassMethod Manifest(pRef, pVessel, pName, pVoyage, pTin, pPort, pEta, pStatus, pGross) [ Private ]
{
    Set m = ##class(PT.Data.Manifest).%New()
    Set m.ManifestRef = pRef, m.VesselId = pVessel, m.VesselName = pName
    Set m.VoyageNo = pVoyage, m.CarrierTin = pTin, m.PortOfDischarge = pPort
    Set m.Eta = pEta, m.StatusCode = pStatus, m.TotalGrossKg = pGross
    Do m.%Save()
}

ClassMethod Cons(pRef, pNo, pCons, pContainers, pGross, pDesc) [ Private ]
{
    Set m = ##class(PT.Data.Manifest).%OpenId(pRef)
    Quit:'$IsObject(m)
    Set c = ##class(PT.Data.ManifestConsignment).%New()
    Set c.Manifest = m
    Set c.LineNo = pNo, c.ConsignmentRef = pCons
    Set c.ContainerCount = pContainers, c.GrossKg = pGross, c.Description = pDesc
    Do c.%Save()
}

}
