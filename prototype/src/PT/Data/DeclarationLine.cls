/// One commodity line. Child of a declaration.
Class PT.Data.DeclarationLine Extends %Persistent
{

Relationship Declaration As PT.Data.Declaration [ Cardinality = parent, Inverse = Lines ];

Property LineNo As %Integer;

Property HSCode As %String(MAXLEN = 12);

Property Quantity As %Numeric(SCALE = 3);

Property CustomsValue As %Numeric(SCALE = 2);

Index LineIdx On LineNo;

}
