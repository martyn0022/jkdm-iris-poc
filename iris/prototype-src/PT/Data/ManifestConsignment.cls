/// One consignment on a manifest.
Class PT.Data.ManifestConsignment Extends %Persistent
{

Relationship Manifest As PT.Data.Manifest [ Cardinality = parent, Inverse = Consignments ];

Property LineNo As %Integer;

Property ConsignmentRef As %String(MAXLEN = 24);

Property ContainerCount As %Integer;

Property GrossKg As %Numeric(SCALE = 2);

Property Description As %String(MAXLEN = 200);

Index LineIdx On LineNo;

}
