/// The canonical customs message.
///
/// SMK 2.7 names this directly: the TO-BE fabric carries a "canonical
/// customs message, WCO Data Model aligned", replacing the legacy
/// EDIFACT translators and point-to-point links.
///
/// Partners each send a different dialect - DFTZ sends EDIFACT CUSDEC,
/// others send XML or flat files. Mapping each source directly to each
/// consumer produces the N x M point-to-point estate the architecture
/// retires; one canonical form in the middle makes it N + M.
///
/// The manifest-side properties (ManifestRef, VesselID, ETA) are
/// present but unpopulated by Flow A, and are the target of the
/// hands-on exercise.
Class JKDM.Msg.CanonicalDeclaration Extends Ens.Request
{

Property DeclarationRef As %String(MAXLEN = 40);

/// K1 import, K2 export, K3 transit ... (JKDM declaration types)
Property DeclarationType As %String(MAXLEN = 8);

Property PartnerID As %String(MAXLEN = 40);

Property LodgementDT As %String(MAXLEN = 40);

Property ConsignorTIN As %String(MAXLEN = 20);

Property ConsigneeTIN As %String(MAXLEN = 20);

Property DeclarantTIN As %String(MAXLEN = 20);

Property OriginCountry As %String(MAXLEN = 2);

/// FTA/preference claimed by the declarant, e.g. ATIGA, AKFTA.
Property FTAClaimed As %String(MAXLEN = 10);

/// Regional value content percentage supporting the preference claim.
Property LocalContentPct As %Decimal(SCALE = 2);

Property TotalCustomsValue As %Decimal(SCALE = 2);

Property CurrencyCode As %String(MAXLEN = 3);

Property TotalDutyAmount As %Decimal(SCALE = 2);

Property TotalTaxAmount As %Decimal(SCALE = 2);

Property CommodityLines As list Of JKDM.Msg.CanonicalLine;

Property TransportMode As %String(MAXLEN = 4);

Property PortOfEntry As %String(MAXLEN = 10);

/// --- manifest side: unpopulated by Flow A, target for the exercise
Property ManifestRef As %String(MAXLEN = 40);

Property VesselID As %String(MAXLEN = 40);

Property ETA As %String(MAXLEN = 40);

/// --- provenance: which partner message produced this canonical form
Property SourceMessageType As %String(MAXLEN = 20);

Property SourceFileRef As %String(MAXLEN = 255);

Property CanonicalVersion As %String(MAXLEN = 10) [ InitialExpression = "1.0" ];

}
