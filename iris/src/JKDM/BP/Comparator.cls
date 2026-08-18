/// Equivalence comparator.
///
/// Runs asynchronously in SHADOW mode. Compares the canonical form of
/// both backend responses field by field, classifies each difference
/// through the operation's rule class, and persists the evidence.
///
/// Most differences classify as IGNORE - timestamps, formatting,
/// backend identifiers. The three-way classification exists so that
/// the FISCAL differences remain visible among them.
Class JKDM.BP.Comparator Extends %RegisteredObject
{

ClassMethod Compare(
    pOperation As %String,
    pDeclRef As %String,
    pCobol As %DynamicObject,
    pPhp As %DynamicObject,
    pRuleClass As %String = "JKDM.Rule.DutyEquivalence",
    pRequestID As %String = "") As %Status
{
    Set tSC = $$$OK
    Try {
        Set tResult = ##class(JKDM.Msg.ComparisonResult).%New()
        Set tResult.OperationName  = pOperation
        Set tResult.DeclarationRef = pDeclRef
        Set tResult.RequestID      = pRequestID
        Set tResult.CobolResponse  = pCobol.%ToJSON()
        Set tResult.PhpResponse    = pPhp.%ToJSON()

        Set tWorst = "EQUIVALENT"

        Do ..Walk(pCobol, pPhp, "", pRuleClass, tResult, .tWorst)

        Set tResult.Verdict = tWorst
        Set tSC = tResult.%Save()
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// Recursive field walk over the two canonical objects.
ClassMethod Walk(
    pA As %DynamicObject,
    pB As %DynamicObject,
    pPrefix As %String,
    pRuleClass As %String,
    pResult As JKDM.Msg.ComparisonResult,
    ByRef pWorst As %String)
{
    Set tIter = pA.%GetIterator()
    While tIter.%GetNext(.tKey, .tValA) {
        Set tPath = $SELECT(pPrefix = "": tKey, 1: pPrefix_"."_tKey)
        Set tValB = pB.%Get(tKey)

        // Nested arrays (line detail) - compare element by element.
        If $ISOBJECT(tValA), tValA.%IsA("%Library.DynamicArray") {
            If '$ISOBJECT(tValB) Continue
            Set tAi = tValA.%GetIterator()
            While tAi.%GetNext(.tIdx, .tElemA) {
                Set tElemB = tValB.%Get(tIdx)
                If $ISOBJECT(tElemA), $ISOBJECT(tElemB) {
                    Do ..Walk(tElemA, tElemB, tPath_"["_tIdx_"]",
                              pRuleClass, pResult, .pWorst)
                }
            }
            Continue
        }

        If $ISOBJECT(tValA) {
            If $ISOBJECT(tValB) {
                Do ..Walk(tValA, tValB, tPath, pRuleClass, pResult, .pWorst)
            }
            Continue
        }

        // Scalar comparison
        If ..Equal(tValA, tValB, tPath, pRuleClass) Continue

        Set tClass = $CLASSMETHOD(pRuleClass, "Classify", tPath)

        Set tDiff = ##class(JKDM.Msg.FieldDiff).%New()
        Set tDiff.FieldPath      = tPath
        Set tDiff.CobolValue     = $SELECT(tValA = "": "<empty>", 1: tValA)
        Set tDiff.PhpValue       = $SELECT(tValB = "": "<absent>", 1: tValB)
        Set tDiff.Classification = tClass
        Do pResult.FieldDiffs.Insert(tDiff)

        If tClass = "FISCAL" {
            Set pWorst = "FISCAL_DIFF"
        } ElseIf (tClass = "MATERIAL") && (pWorst '= "FISCAL_DIFF") {
            Set pWorst = "MATERIAL_DIFF"
        }
    }
}

ClassMethod Equal(pA, pB, pPath As %String, pRuleClass As %String) As %Boolean
{
    If pA = pB Quit 1

    // Numeric comparison within the operation's approved tolerance.
    If ..IsNumeric(pA), ..IsNumeric(pB) {
        Set tTol = $CLASSMETHOD(pRuleClass, "Tolerance", pPath)
        Quit ($ZABS(pA - pB) <= tTol)
    }

    Quit 0
}

ClassMethod IsNumeric(pVal) As %Boolean
{
    If pVal = "" Quit 0
    Quit (pVal = +pVal)
}

}
