/// One field-level difference between the two backends.
///
/// Classification is the whole point. A naive comparator that reports
/// every difference produces unusable noise - attendees discover this
/// within about 30 seconds of first running it, which is exactly the
/// lesson.
Class JKDM.Msg.FieldDiff Extends (%SerialObject, %JSON.Adaptor)
{

Property FieldPath As %String(MAXLEN = 200);

Property CobolValue As %String(MAXLEN = 500);

Property PhpValue As %String(MAXLEN = 500);

/// FISCAL   - any mismatch is a failure. SMK 5.7 list.
/// MATERIAL - a defect, but not a monetary one.
/// IGNORE   - expected to differ (format, timestamps, trace IDs).
Property Classification As %String(VALUELIST = ",FISCAL,MATERIAL,IGNORE");
}
