/// Inbound declaration intake, as a graphical BPL.
///
/// Viewable and editable in the Business Process Designer:
///   Interoperability > Build > Business Processes > JKDM.BP.DeclarationIntake
///
/// The shape order on the canvas is the architecture:
///
///   1. audit the receipt          - before parsing
///   2. parse and validate         - may fail; the row already exists
///   3. transform to canonical     - one message model, N partners
///   4. lodge to the core          - through the strangler router
///   5. stamp the outcome
///   6. acknowledge to the partner
///
/// Step 1 precedes step 2 so that a file which fails to parse still has
/// an audit row, a hash and its raw content. Without those there is no
/// evidence of what a partner submitted.
///
/// Step 4 lodges over the same API contract a live consumer calls, so
/// file-origin traffic obeys the same routing table - the question SMK
/// 5.2 leaves open, answered here and visible in the audit trail.
///
/// Parsing stays in ObjectScript, called from one <code> activity. The
/// diagram is worth having because it shows the order of the calls, not
/// because it hides the string handling.
Class JKDM.BP.DeclarationIntake Extends Ens.BusinessProcessBPL
{

/// Structural gate on the interchange envelope.
///
/// IRIS parses EDIFACT leniently: a truncated interchange with no
/// UNT/UNZ trailers still yields a document object with usable
/// segments. That suits a viewer but not an intake gate, where a file
/// cut short in transit would be lodged with whatever lines arrived.
///
/// Without a D96A schema there is no full standards validation, so this
/// checks the envelope only. It catches truncation, not a syntactically
/// valid message carrying the wrong segments.
ClassMethod ValidateEnvelope(pRaw As %String) As %Status
{
    Set tTrimmed = $ZSTRIP(pRaw, "<>WC")
    If tTrimmed = "" {
        Quit $$$ERROR($$$GeneralError, "empty file")
    }
    If '(tTrimmed [ "UNB+") {
        Quit $$$ERROR($$$GeneralError, "no UNB interchange header")
    }
    If '(tTrimmed [ "UNZ+") {
        Quit $$$ERROR($$$GeneralError, "no UNZ interchange trailer - file truncated in transit")
    }
    If '(tTrimmed [ "UNT+") {
        Quit $$$ERROR($$$GeneralError, "no UNT message trailer - message incomplete")
    }
    Quit $$$OK
}

/// Parse the interchange far enough to know WHAT it is - nothing more.
///
/// Split from the transform on purpose. Identifying the message type is
/// a routing decision, and routing decisions belong on the diagram
/// where a reader can see them, not buried inside a parse routine.
///
/// pCode is SYNTAX, or empty when the message was readable.
ClassMethod ParseAndIdentify(
    pRequest As JKDM.Msg.InboundFile,
    Output pMessageType As %String,
    Output pCode As %String,
    Output pReason As %String) As %Status
{
    Set pMessageType = "", pCode = "", pReason = ""
    Set tMsg = ..MessageFor(pRequest, .pCode, .pReason)
    Set:$IsObject(tMsg) pMessageType = tMsg.Name
    Quit $$$OK
}

/// CUSDEC -> canonical declaration. Called from the CUSDEC branch only.
ClassMethod TransformCusdec(
    pRequest As JKDM.Msg.InboundFile,
    Output pCanonical As JKDM.Msg.CanonicalDeclaration,
    Output pCode As %String,
    Output pReason As %String) As %Status
{
    Set pCanonical = "", pCode = "", pReason = ""

    Set tMsg = ..MessageFor(pRequest, .pCode, .pReason)
    Quit:'$IsObject(tMsg) $$$OK

    Set tSC = ##class(JKDM.Xform.CusdecToCanonical).Transform(
        tMsg, pRequest.PartnerID, pRequest.FileName, .pCanonical)
    If $$$ISERR(tSC) {
        Set pCode = "SYNTAX", pReason = "transform failed"
        Quit $$$OK
    }

    If pCanonical.DeclarationRef = "" {
        // Structurally valid, business-invalid. A different failure from
        // a parse error, and worth a different reject code - partners fix
        // these two problems in different places.
        Set pCode = "BUSINESS", pReason = "no declaration reference in BGM"
    }
    Quit $$$OK
}

/// CUSCAR -> canonical manifest. Called from the CUSCAR branch.
///
/// The mapping itself lives in JKDM.Xform.CuscarToCanonical, which is
/// the classroom exercise. This wrapper ships complete so the room
/// never has to touch the process to make their change take effect.
ClassMethod TransformCuscar(
    pRequest As JKDM.Msg.InboundFile,
    Output pCanonical As JKDM.Msg.CanonicalDeclaration,
    Output pCode As %String,
    Output pReason As %String) As %Status
{
    Set pCanonical = "", pCode = "", pReason = ""

    Set tMsg = ..MessageFor(pRequest, .pCode, .pReason)
    Quit:'$IsObject(tMsg) $$$OK

    Set tSC = ##class(JKDM.Xform.CuscarToCanonical).Transform(
        tMsg, pRequest.PartnerID, pRequest.FileName, .pCanonical)
    If $$$ISERR(tSC) {
        Set pCode = "SYNTAX", pReason = "manifest transform failed"
        Quit $$$OK
    }

    If pCanonical.ManifestRef = "" {
        Set pCode = "UNSUPPORTED", pReason = "manifest handler not finished - see docs/EXERCISE.md"
    }
    Quit $$$OK
}

/// Validate the envelope and return the message inside the interchange.
///
/// Both the identify step and the transform step need the parsed
/// message, and re-reading the stream costs about a millisecond, so
/// this re-parses rather than carrying a document through the BPL
/// context. Carrying it would mean serialising an EDI document between
/// activities for no measurable gain.
/// ponytail: re-parse per activity; carry the document id if a message
/// ever gets big enough for it to matter.
ClassMethod MessageFor(
    pRequest As JKDM.Msg.InboundFile,
    Output pCode As %String,
    Output pReason As %String) As EnsLib.EDI.EDIFACT.Document [ Private ]
{
    Set pCode = "", pReason = ""

    Set tRaw = ""
    Do pRequest.RawContent.Rewind()
    While 'pRequest.RawContent.AtEnd {
        Set tRaw = tRaw_pRequest.RawContent.Read(32000)
    }

    Set tSC = ..ValidateEnvelope(tRaw)
    If $$$ISERR(tSC) {
        Set pCode = "SYNTAX", pReason = $SYSTEM.Status.GetErrorText(tSC)
        Quit ""
    }

    Set tDoc = ##class(EnsLib.EDI.EDIFACT.Document).ImportFromString(tRaw, .tParseSC)
    If $$$ISERR(tParseSC) || '$IsObject(tDoc) {
        Set pCode = "SYNTAX", pReason = "EDIFACT parse failed"
        Quit ""
    }

    // An interchange (UNB...UNZ) wraps one or more messages (UNH...UNT).
    Set tMessage = tDoc
    If tDoc.Name = "Interchange" {
        Set tMessage = tDoc.NextChild("")
    }
    If '$IsObject(tMessage) {
        Set pCode = "SYNTAX", pReason = "interchange contains no message"
        Quit ""
    }
    Quit tMessage
}

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='JKDM.Msg.InboundFile' response='Ens.Response' height='2600' width='2200' >
<context>
<property name='RejectCode' type='%String' initialexpression='' />
<property name='RejectReason' type='%String' >
<parameters>
<parameter name='MAXLEN' value='500' />
</parameters>
</property>
<property name='DeclRef' type='%String' />
<property name='LineCount' type='%Integer' initialexpression='0' />
<property name='CoreRef' type='%String' >
<parameters>
<parameter name='MAXLEN' value='60' />
</parameters>
</property>
<property name='ServedBy' type='%String' />
<property name='Outcome' type='%String' />
<property name='MessageType' type='%String' />
<property name='Canonical' type='JKDM.Msg.CanonicalDeclaration' />
</context>
<sequence xend='200' yend='2150' >

<call name='1. Audit receipt' target='JKDM.BO.AuditOperation' async='0' xpos='200' ypos='250' >
<annotation>Written BEFORE anything tries to parse the file. The file you cannot read is the one you will be asked about.</annotation>
<request type='JKDM.Msg.InboundFile' >
<assign property="callrequest" value="request" action="set" />
</request>
<response type='Ens.Response' />
</call>

<code name='2. Identify the message' xpos='200' ypos='375' >
<annotation>Envelope check and parse, far enough to know what arrived. No transform yet - what to do with it is the next decision.</annotation>
<![CDATA[
 Do ##class(JKDM.BP.DeclarationIntake).ParseAndIdentify(request, .tType, .tCode, .tReason)
 Set context.MessageType = tType
 Set context.RejectCode = tCode
 Set context.RejectReason = tReason
]]>
</code>

<if name='3. Readable?' condition='context.RejectCode=""' xpos='200' ypos='500' xend='200' yend='1550' >
<annotation>Everything downstream only runs for a file we could actually read.</annotation>
<true>

<switch name='4. Route on message type' xpos='470' ypos='640' xend='470' yend='950' >
<annotation>Content-based routing. The fabric inspects what arrived and sends it to the handler for that message type. Adding a partner message type is a new branch here, not a change to anything upstream.</annotation>
<case name='CUSDEC · declaration' condition='context.MessageType="CUSDEC"' >
<code name='Transform to canonical' xpos='335' ypos='780' >
<![CDATA[
 Do ##class(JKDM.BP.DeclarationIntake).TransformCusdec(request, .tCanon, .tCode, .tReason)
 Set context.RejectCode = tCode
 Set context.RejectReason = tReason
 If $IsObject(tCanon) {
   Set context.Canonical = tCanon
   Set context.DeclRef = tCanon.DeclarationRef
   Set context.LineCount = tCanon.CommodityLines.Count()
 }
]]>
</code>
</case>
<case name='CUSCAR · manifest' condition='context.MessageType="CUSCAR"' >
<code name='No handler yet' xpos='605' ypos='780' >
<annotation>This branch is the hands-on exercise. The routing decision already exists; what is missing is the transform behind it.</annotation>
<![CDATA[
 Do ##class(JKDM.BP.DeclarationIntake).TransformCuscar(request, .tCanon, .tCode, .tReason)
 Set context.RejectCode = tCode
 Set context.RejectReason = tReason
 If $IsObject(tCanon) {
   Set context.Canonical = tCanon
   Set context.DeclRef = tCanon.ManifestRef
   Set context.LineCount = 1
 }
]]>
</code>
</case>
<default name='unknown type' >
<code name='Reject unknown' xpos='875' ypos='780' >
<![CDATA[
 Set context.RejectCode = "UNSUPPORTED"
 Set context.RejectReason = "unsupported message type: "_context.MessageType
]]>
</code>
</default>
</switch>

<if name='5. Canonical built?' condition='context.RejectCode=""' xpos='470' ypos='1000' xend='470' yend='1450' >
<true>

<call name='6. Audit PARSED' target='JKDM.BO.AuditOperation' async='0' xpos='740' ypos='1100' >
<request type='JKDM.Msg.AuditUpdate' >
<assign property="callrequest.SessionID" value="process.%SessionId" action="set" />
<assign property="callrequest.ParseStatus" value='"PARSED"' action="set" />
<assign property="callrequest.MessageType" value="context.MessageType" action="set" />
<assign property="callrequest.DeclarationRef" value="context.DeclRef" action="set" />
<assign property="callrequest.RecordCount" value="context.LineCount" action="set" />
</request>
<response type='Ens.Response' />
</call>

<call name='7. Lodge via strangler router' target='JKDM.BO.CoreDeclarationOp' async='0' xpos='740' ypos='1220' >
<annotation>Calls the SAME public contract a live consumer calls, so file traffic obeys the same routing table (SMK 5.2).</annotation>
<request type='JKDM.Msg.CanonicalDeclaration' >
<assign property="callrequest" value="context.Canonical" action="set" />
</request>
<response type='JKDM.Msg.CoreLodgement' >
<assign property="context.CoreRef" value="callresponse.CoreReference" action="set" />
<assign property="context.ServedBy" value="callresponse.ServedBy" action="set" />
<assign property="context.Outcome" value="callresponse.Outcome" action="set" />
</response>
</call>

<code name='8. Read the core outcome' xpos='740' ypos='1340' >
<annotation>"We hold no such declaration" is an answer. "The core is down" is an outage. Partners are told different things.</annotation>
<![CDATA[
 If context.Outcome = "UNKNOWN_DECLARATION" {
   Set context.RejectCode = "BUSINESS"
   Set context.RejectReason = "core holds no declaration "_context.DeclRef
 } ElseIf context.Outcome = "CORE_UNAVAILABLE" {
   Set context.RejectCode = "SYSTEM"
   Set context.RejectReason = "core temporarily unavailable"
 }
]]>
</code>

</true>
</if>

</true>
</if>

<if name='9. Lodged?' condition='context.RejectCode=""' xpos='200' ypos='1650' xend='200' yend='1950' >
<true>
<call name='10. Audit LODGED' target='JKDM.BO.AuditOperation' async='0' xpos='470' ypos='1800' >
<request type='JKDM.Msg.AuditUpdate' >
<assign property="callrequest.SessionID" value="process.%SessionId" action="set" />
<assign property="callrequest.ParseStatus" value='"LODGED"' action="set" />
<assign property="callrequest.DeclarationRef" value="context.DeclRef" action="set" />
<assign property="callrequest.CoreReference" value="context.CoreRef" action="set" />
<assign property="callrequest.ServedBy" value="context.ServedBy" action="set" />
</request>
<response type='Ens.Response' />
</call>
</true>
<false>
<call name='10. Audit REJECTED' target='JKDM.BO.AuditOperation' async='0' xpos='830' ypos='1800' >
<request type='JKDM.Msg.AuditUpdate' >
<assign property="callrequest.SessionID" value="process.%SessionId" action="set" />
<assign property="callrequest.ParseStatus" value='"REJECTED"' action="set" />
<assign property="callrequest.RejectReason" value="context.RejectCode_&quot;: &quot;_context.RejectReason" action="set" />
<assign property="callrequest.DeclarationRef" value="context.DeclRef" action="set" />
</request>
<response type='Ens.Response' />
</call>
</false>
</if>

<call name='11. Acknowledge to partner' target='JKDM.BO.AckFileOperation' async='0' xpos='200' ypos='2050' >
<annotation>APERAK when accepted, CONTRL when not. A flow that ingests perfectly and never acks generates phone calls.</annotation>
<request type='JKDM.Msg.AckRequest' >
<assign property="callrequest.FileName" value="request.FileName" action="set" />
<assign property="callrequest.Accepted" value='context.RejectCode=""' action="set" />
<assign property="callrequest.AckType" value='$SELECT(context.RejectCode="":"APERAK",1:"CONTRL")' action="set" />
<assign property="callrequest.Content" value='##class(JKDM.BO.AckFileOperation).BuildAck(request.FileName,context.DeclRef,context.CoreRef,context.RejectCode="",context.RejectCode,context.RejectReason)' action="set" />
</request>
<response type='Ens.Response' />
</call>

</sequence>
</process>
}

}
