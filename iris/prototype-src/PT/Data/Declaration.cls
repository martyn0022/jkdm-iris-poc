/// A customs declaration, stored natively.
///
/// Note the Lines relationship. In the tender stack that is a foreign
/// key plus a hasMany() in the model plus an N+1 problem waiting to
/// happen. Here the child rows live inside the parent's storage, so
/// walking them costs nothing and there is no join to forget.
Class PT.Data.Declaration Extends %Persistent
{

Property DeclRef As %String(MAXLEN = 24) [ Required ];

Property DeclType As %String(MAXLEN = 4);

Property DeclarantTin As %String(MAXLEN = 20);

Property OriginCountry As %String(MAXLEN = 2);

Property FtaClaimed As %String(MAXLEN = 10);

Property LocalPct As %Numeric(SCALE = 2);

Property Currency As %String(MAXLEN = 3) [ InitialExpression = "MYR" ];

Property LodgedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG, 3)} ];

/// Where the declaration came from - a partner file, or an API call.
Property Source As %String(MAXLEN = 20) [ InitialExpression = "API" ];

Relationship Lines As PT.Data.DeclarationLine [ Cardinality = children, Inverse = Declaration ];

Index RefIdx On DeclRef [ IdKey ];

}
