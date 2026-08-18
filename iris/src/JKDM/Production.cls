/// The interoperability production.
///
/// Flow A (EDI/SFTP ingestion) runs here, so the message viewer, visual
/// trace and queues are live artefacts.
///
/// Flow B (the strangler router) is a REST dispatch class outside the
/// production. The split is deliberate: the router sits on the
/// synchronous request path, where a queue would add latency for no
/// benefit, while ingestion is asynchronous, retryable and needs the
/// audit and replay machinery a production provides.
///
/// Portal:
///   Interoperability > Configure > Production
///   Interoperability > View > Messages   (visual trace per session)
Class JKDM.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="JKDM.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>JKDM SMK POC - inbound EDI/SFTP declaration ingestion (SMK 2.7, 4.3.5)</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="JKDM.BS.EdiInboundService" Category="FlowA-Ingestion" ClassName="JKDM.BS.EdiInboundService" PoolSize="1" Enabled="true" Foreground="false" Comment="Polls the DFTZ partner drop. IRIS is the CLIENT - this is a pull." LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Protocol">SFTP</Setting>
    <Setting Target="Adapter" Name="FTPServer">sftp</Setting>
    <Setting Target="Adapter" Name="FTPPort">22</Setting>
    <Setting Target="Adapter" Name="Credentials">DFTZ</Setting>
    <Setting Target="Adapter" Name="FilePath">/inbound/cusdec</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.edi</Setting>
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
    <Setting Target="Adapter" Name="DeleteFromServer">1</Setting>
    <Setting Target="Adapter" Name="StayConnected">-1</Setting>
    <Setting Target="Host" Name="PartnerID">DFTZ</Setting>
    <Setting Target="Host" Name="TargetConfigName">JKDM.BP.DeclarationIntake</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="JKDM.BP.DeclarationIntake" Category="FlowA-Ingestion" ClassName="JKDM.BP.DeclarationIntake" PoolSize="1" Enabled="true" Foreground="false" Comment="Audit BEFORE parse. Then canonical, then lodge via the router." LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="JKDM.BO.AuditOperation" Category="FlowA-Ingestion" ClassName="JKDM.BO.AuditOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Non-repudiation ledger (SMK 2.7 fabric capability)" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="JKDM.BO.CoreDeclarationOp" Category="FlowA-Ingestion" ClassName="JKDM.BO.CoreDeclarationOp" PoolSize="1" Enabled="true" Foreground="false" Comment="Lodges over the SAME public contract the strangler router serves" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="HTTPServer">localhost</Setting>
    <Setting Target="Adapter" Name="HTTPPort">52773</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">30</Setting>
    <Setting Target="Host" Name="ContractURL">/jkdm/duty/calculate</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

  <Item Name="JKDM.BO.AckFileOperation" Category="FlowA-Ingestion" ClassName="JKDM.BO.AckFileOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="PUTs CONTRL/APERAK back to the partner - outbound inverts the pull" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Protocol">SFTP</Setting>
    <Setting Target="Adapter" Name="FTPServer">sftp</Setting>
    <Setting Target="Adapter" Name="FTPPort">22</Setting>
    <Setting Target="Adapter" Name="Credentials">DFTZ</Setting>
    <Setting Target="Adapter" Name="FilePath">/outbound</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>

</Production>
}

}
