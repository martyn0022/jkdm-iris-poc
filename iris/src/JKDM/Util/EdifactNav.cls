/// JKDM SMK POC - EDIFACT segment navigation.
///
/// READ THIS BEFORE THE FLOW A WALKTHROUGH - it is an honest
/// constraint worth stating out loud in the session.
///
/// IRIS parses EDIFACT structurally out of the box: it splits the
/// interchange into messages, messages into segments, segments into
/// composites and elements. What it does NOT ship is the UN/EDIFACT
/// D96A message DICTIONARY. Schemas are loaded from .SEF files, which
/// are licensed separately and are not in the product.
///
/// With a schema loaded you address fields by name:
///     doc.GetValueAt("BGM:DocumentMessageNumber")
/// Without one you address them by position:
///     doc.GetValueAt("3:2")
///
/// Both are real IRIS; only the first is self-documenting, and only
/// the first validates the message against the standard. This class
/// exists to make the positional form readable by looking segments up
/// by their EDIFACT tag rather than counting them by hand.
///
/// ACTION FOR THE PROJECT: procuring the D96A SEF schema set is a
/// real line item. It is cheap, but it is not zero, and it needs to
/// happen before the first partner conformance test - not after.
Class JKDM.Util.EdifactNav Extends %RegisteredObject
{

/// Ordinal position of the Nth segment carrying the given tag.
/// Returns 0 when not present.
ClassMethod FindSegment(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pTag As %String,
    pOccurrence As %Integer = 1) As %Integer
{
    Set tSeen = 0
    For i = 1:1:pDoc.SegCount {
        Set tSeg = pDoc.GetSegmentAt(i)
        Continue:'$IsObject(tSeg)
        If tSeg.GetValueAt(0) = pTag {
            Set tSeen = tSeen + 1
            If tSeen = pOccurrence Return i
        }
    }
    Quit 0
}

/// Value of an element within the Nth segment carrying a tag.
///   Get(doc,"BGM",2)      -> BGM element 2
///   Get(doc,"LIN",3,1)    -> LIN element 3, component 1
ClassMethod Get(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pTag As %String,
    pElement As %Integer,
    pComponent As %Integer = 0,
    pOccurrence As %Integer = 1) As %String
{
    Set tPos = ..FindSegment(pDoc, pTag, pOccurrence)
    Quit:tPos=0 ""
    Set tPath = tPos_":"_pElement
    If pComponent > 0 {
        Set tPath = tPath_"."_pComponent
    }
    Quit pDoc.GetValueAt(tPath)
}

/// Value from a segment identified by its absolute ordinal position.
/// Used when walking line groups, where the same tag repeats.
ClassMethod GetAt(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pPosition As %Integer,
    pElement As %Integer,
    pComponent As %Integer = 0) As %String
{
    Set tPath = pPosition_":"_pElement
    If pComponent > 0 {
        Set tPath = tPath_"."_pComponent
    }
    Quit pDoc.GetValueAt(tPath)
}

/// The EDIFACT tag of the segment at a position - "LIN", "MOA", etc.
ClassMethod TagAt(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pPosition As %Integer) As %String
{
    Set tSeg = pDoc.GetSegmentAt(pPosition)
    Quit:'$IsObject(tSeg) ""
    Quit tSeg.GetValueAt(0)
}

/// A NAD (name and address) party qualified by role - DT declarant,
/// CN consignee, CZ consignor. Returns the party identifier.
ClassMethod Party(
    pDoc As EnsLib.EDI.EDIFACT.Document,
    pQualifier As %String) As %String
{
    For i = 1:1:pDoc.SegCount {
        Set tSeg = pDoc.GetSegmentAt(i)
        Continue:'$IsObject(tSeg)
        Continue:tSeg.GetValueAt(0)'="NAD"
        If pDoc.GetValueAt(i_":1") = pQualifier {
            Return pDoc.GetValueAt(i_":2.1")
        }
    }
    Quit ""
}

/// EDIFACT CCYYMMDDHHMM (format qualifier 203) -> ISO-8601.
/// Malformed or absent values return empty rather than guessing -
/// a wrong lodgement timestamp is worse than a missing one.
ClassMethod DateTime(pRaw As %String) As %String
{
    Set tClean = $ZSTRIP(pRaw, "<>W")
    Quit:$LENGTH(tClean)<8 ""
    Set tOut = $EXTRACT(tClean, 1, 4)_"-"_$EXTRACT(tClean, 5, 6)_"-"_$EXTRACT(tClean, 7, 8)
    If $LENGTH(tClean) >= 12 {
        Set tOut = tOut_"T"_$EXTRACT(tClean, 9, 10)_":"_$EXTRACT(tClean, 11, 12)_":00+08:00"
    }
    Quit tOut
}

}
