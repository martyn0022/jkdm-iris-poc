/// Tariff reference data.
///
/// THE POINT OF THIS FILE IS HOW SHORT IT IS.
///
/// In the tender stack the same thing is three artefacts kept in step
/// by hand: a Laravel migration that creates the table, an Eloquent
/// model that describes it again in PHP, and the physical Postgres
/// table itself. Here the class definition IS the object, IS the SQL
/// table, and IS the storage. There is nothing to keep in sync,
/// because there is only one of it.
///
///   SELECT * FROM PT_Data.TariffRate          <- works, no mapping
///   Set t = ##class(PT.Data.TariffRate).%OpenId("8471.30.10")
///
/// Same data, both ways in, no ORM in between.
Class PT.Data.TariffRate Extends %Persistent
{

Property HSCode As %String(MAXLEN = 12) [ Required ];

Property Description As %String(MAXLEN = 200);

Property DutyRate As %Numeric(SCALE = 4);

Property SstRate As %Numeric(SCALE = 4);

Property Uom As %String(MAXLEN = 6);

Index HSIdx On HSCode [ IdKey ];

}
