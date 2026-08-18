/// JKDM SMK POC - write the acknowledgement back to the partner drop.
///
/// Outbound inverts the inbound pattern: IRIS is still the client, but
/// now it PUTs to the partner's server instead of GETting from it.
///
/// The ack is not decoration. A partner whose file was rejected needs
/// to know within minutes, in a form their software can read - and a
/// partner whose file was accepted needs the reference to quote when
/// they call. An ingestion flow with no ack generates phone calls.
Class JKDM.BO.AckFileOperation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.FTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.FTP.OutboundAdapter;

Method SendAck(
    pRequest As JKDM.Msg.AckRequest,
    Output pResponse As Ens.Response) As %Status
{
    Set pResponse = ##class(Ens.Response).%New()

    Set tOutName = ##class(%File).GetFilename(pRequest.FileName)
    Set tOutName = $PIECE(tOutName, ".", 1)_"."_$ZCONVERT(pRequest.AckType, "L")

    Set tStream = ##class(%Stream.FileCharacter).%New()
    Do tStream.Write(pRequest.Content)

    Set tSC = ..Adapter.PutStream(tOutName, tStream)

    If $$$ISERR(tSC) {
        // The declaration is already lodged and audited. A failed ack
        // is an operational problem, not a fiscal one - alert, do not
        // unwind the transaction.
        Set tErr = "ack write failed for "_tOutName_": "_$SYSTEM.Status.GetErrorText(tSC)
        $$$LOGERROR(tErr)
        Quit $$$OK
    }

    Set tVerdict = $SELECT(pRequest.Accepted: "accepted", 1: "rejected")
    Set tLog = "ack "_pRequest.AckType_" written: "_tOutName_" ("_tVerdict_")"
    $$$LOGINFO(tLog)
    Quit $$$OK
}

/// Build the acknowledgement message.
///
/// CONTRL carries a syntax verdict, APERAK an application verdict.
/// Real partners are fussy about these; the POC emits a readable
/// minimum rather than pretending to full conformance. Getting them
/// exactly right is a partner-onboarding task, not an architecture
/// task - but it is a task, and it has a cost.
ClassMethod BuildAck(
    pFileName As %String,
    pDeclRef As %String,
    pCoreRef As %String,
    pAccepted As %Boolean,
    pCode As %String,
    pReason As %String) As %String
{
    Set tDate = $ZDATE($HOROLOG, 8)                                  // CCYYMMDD
    Set tTime = $TRANSLATE($ZTIME($PIECE($HOROLOG, ",", 2), 1), ":", "")  // HHMMSS
    Set tCtrl = $EXTRACT($TRANSLATE($SYSTEM.Util.CreateGUID(), "-", ""), 1, 9)

    Set tOut = "UNB+UNOA:2+JKDM:ZZ+DFTZ001:ZZ+"_
               $EXTRACT(tDate, 3, 8)_":"_$EXTRACT(tTime, 1, 4)_"+"_tCtrl_"'"

    If pAccepted {
        Set tOut = tOut_"UNH+1+APERAK:D:96A:UN'"
        Set tOut = tOut_"BGM+312+"_pCoreRef_"+9'"
        Set tOut = tOut_"DTM+137:"_tDate_$EXTRACT(tTime, 1, 4)_":203'"
        Set tOut = tOut_"RFF+ACW:"_pDeclRef_"'"
        Set tOut = tOut_"ERC+0'"
        Set tOut = tOut_"FTX+AAO+++LODGED'"
        Set tOut = tOut_"UNT+6+1'"
    }
    Else {
        // The partner gets a code and a short reason, never our
        // internal error text. Leaking "<Ens>ErrHTTPStatus ..." across
        // an organisational boundary tells an outsider about our
        // topology and tells the broker nothing they can act on.
        Set tOut = tOut_"UNH+1+CONTRL:D:96A:UN'"
        Set tOut = tOut_"UCI+"_tCtrl_"+DFTZ001+JKDM+"_..ActionCode(pCode)_"'"
        Set tOut = tOut_"DTM+137:"_tDate_$EXTRACT(tTime, 1, 4)_":203'"
        Set:pDeclRef'="" tOut = tOut_"RFF+ACW:"_pDeclRef_"'"
        Set tOut = tOut_"FTX+AAO+++"_..PartnerText(pCode, pReason)_"'"
        Set tOut = tOut_"UNT+5+1'"
    }

    Set tOut = tOut_"UNZ+1+"_tCtrl_"'"
    Quit tOut
}

/// UN/EDIFACT 0083 action codes, narrowed to what this flow emits.
///   4 = interchange rejected
///   7 = interchange accepted, message rejected
ClassMethod ActionCode(pCode As %String) As %String
{
    Quit $CASE(pCode, "SYNTAX":4, "UNSUPPORTED":7, "BUSINESS":7, "SYSTEM":4, :4)
}

/// What the partner is actually told. Short, upper case (UNOA), and
/// phrased as something the reader can do something about.
ClassMethod PartnerText(
    pCode As %String,
    pReason As %String) As %String
{
    Set tText = $CASE(pCode,
        "SYNTAX":      "REJECTED - INTERCHANGE FAILED SYNTAX VALIDATION",
        "UNSUPPORTED": "REJECTED - MESSAGE TYPE NOT SUPPORTED",
        "BUSINESS":    "REJECTED - DECLARATION DATA NOT ACCEPTED",
        "SYSTEM":      "NOT PROCESSED - RESEND LATER",
        :              "REJECTED")

    // A short business detail is safe to pass on; a system fault
    // detail is not.
    If (pCode = "BUSINESS") || (pCode = "UNSUPPORTED") {
        Set tDetail = $ZCONVERT($EXTRACT(pReason, 1, 50), "U")
        Set tDetail = $ZSTRIP(tDetail, "*", "+':?")
        Set:tDetail'="" tText = tText_" - "_tDetail
    }

    Quit tText
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="JKDM.Msg.AckRequest">
    <Method>SendAck</Method>
  </MapItem>
</MapItems>
}

}
