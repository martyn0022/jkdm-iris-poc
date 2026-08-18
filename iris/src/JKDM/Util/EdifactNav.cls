/// EDIFACT segment navigation.
///
/// IRIS parses EDIFACT structurally out of the box, splitting the
/// interchange into messages, segments, composites and elements. It
/// does not ship the UN/EDIFACT D96A message dictionary: schemas load
/// from .SEF files, licensed separately.
///
/// With a schema loaded, fields are addressed by name:
///     doc.GetValueAt("BGM:DocumentMessageNumber")
/// Without one, by position:
///     doc.GetValueAt("3:2")
///
/// Only the named form is self-documenting, and only it validates the
/// message against the standard. This class makes the positional form
/// readable by looking segments up by EDIFACT tag rather than counting
/// them.
///
/// Procuring the D96A SEF schema set is a project line item, needed
/// before the first partner conformance test.
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
