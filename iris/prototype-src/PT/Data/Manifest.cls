/// A vessel manifest and its consignments.
Class PT.Data.Manifest Extends %Persistent
{

Property ManifestRef As %String(MAXLEN = 24) [ Required ];

Property VesselId As %String(MAXLEN = 16);

Property VesselName As %String(MAXLEN = 60);

Property VoyageNo As %String(MAXLEN = 12);

Property CarrierTin As %String(MAXLEN = 16);

Property PortOfDischarge As %String(MAXLEN = 8);

Property Eta As %TimeStamp;

Property StatusCode As %String(MAXLEN = 2);

Property TotalGrossKg As %Numeric(SCALE = 2);

Relationship Consignments As PT.Data.ManifestConsignment [ Cardinality = children, Inverse = Manifest ];

Index RefIdx On ManifestRef [ IdKey ];

/// Status codes as the core holds them, expanded for the API.
ClassMethod StatusName(pCode As %String) As %String
{
    Quit $CASE(pCode, "RL":"RELEASED", "HD":"HELD", "CL":"CLEARED", "AR":"ARRIVED", :pCode)
}

}
