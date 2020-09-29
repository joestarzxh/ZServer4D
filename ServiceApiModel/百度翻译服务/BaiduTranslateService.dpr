{ * �ⲿapi֧�֣��ٶȷ������                                                  * }
{ * https://github.com/PassByYou888/CoreCipher                                 * }
{ * https://github.com/PassByYou888/ZServer4D                                  * }
{ * https://github.com/PassByYou888/zExpression                                * }
{ ****************************************************************************** }

program BaiduTranslateService;

{$APPTYPE CONSOLE}

{$R *.res}


uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  PascalStrings,
  CommunicationFramework,
  CommunicationFramework_Server_Indy,
  CommunicationFramework_Server_CrossSocket,
  DoStatusIO,
  CoreClasses,
  DataFrameEngine,
  UnicodeMixedLib,
  MemoryStream64,
  ZS_JsonDataObjects,
  ZDBLocalManager,
  ZDBEngine,
  ListEngine,
  BaiduTranslateAPI in 'BaiduTranslateAPI.pas',
  BaiduTranslateClient in 'Client.Lib\BaiduTranslateClient.pas';

(*
  �ٶȷ��������ʹ��delphi xe10.1.2����д
  ���Ҫ��linux��ʹ�ã������delphi xe10.2.2�����ϰ汾�����������ƽ̨��������Ҳ���linux�����½�һ��console���̣������븴�ƹ�ȥ����

  �ٶȷ����http��ѯ�����߳��иɵ�
  һ���ͻ��˼���ͬʱ����1000����ѯ���󣬲��ᷢ��1000���̣߳�����һ����ѯ��ɺ󣬽������Ż��ѯ��һ��
  ���׷������а�ȫ���ƣ��޶�Ϊ100ipͬʱ��ѯ

  ע�⣺���׷�����ģ��ʹ�������ݿ⣬����û��DataStoreService�������ȱ��������(��Ҫ���Ҳ����һ��С��������̫�Ӵ�)
  ����ʹ��Ctrl+F2�رշ�����ʱ���൱�ڶϵ磬ZDB�а�ȫ��д���ƣ����׵������ǣ��Ȱѿͻ���ȫ���ر��꣬2���Ժ�����ctrl+f2

  ����������ݿ��𻵣����ǲ��ɻָ��ģ�ֻ��ֱ��ɾ��History.ox���ؿ����������ɻָ�
*)

var
  MiniDB: TZDBLocalManager;

const
  C_Mini_DB_Name = 'zTranslate';

type
  TMyServer = class(TCommunicationFramework_Server_CrossSocket)
  public
    procedure DoIOConnectAfter(Sender: TPeerIO); override;
    procedure DoIODisconnect(Sender: TPeerIO); override;
  end;

procedure TMyServer.DoIOConnectAfter(Sender: TPeerIO);
begin
  DoStatus('id: %d ip:%s connected', [Sender.ID, Sender.PeerIP]);
  Sender.UserVariants['LastIP'] := Sender.PeerIP;
  inherited DoIOConnectAfter(Sender);
end;

procedure TMyServer.DoIODisconnect(Sender: TPeerIO);
begin
  DoStatus('id: %d ip: %s disconnect', [Sender.ID, VarToStr(Sender.UserVariants['LastIP'])]);
  inherited DoIODisconnect(Sender);
end;

procedure cmd_BaiduTranslate(Sender: TPeerIO; InData, OutData: TDataFrameEngine);
type
  PDelayReponseSource = ^TDelayReponseSource;

  TDelayReponseSource = packed record
    serv: TMyServer;
    ID: Cardinal;
    sourLan, destLan: TTranslateLanguage;
    s: TPascalString;
    UsedCache: Boolean;
    Hash64: THash64;
  end;

var
  sp: PDelayReponseSource;
begin
  // ����ʵ�ֵ�BaiduTranslate����Ҳ��һ�ָ߼�����������ʾ��
  // �����Щ����������о�ͷ��ǣ��̫��������Ϊ��û�й��Ĺ�ZDB�������ݿ�����
  // ���������zdbҲû�£�ֱ������zdb���ڣ�����BaiduTranslateWithHTTP��ʹ�ü���

  // ���ڶԷ������İ�ȫ����
  // �������ip�ٹ�100������ͬʱ������ѯ���ͷ��ش���
  // ��Ϊֻ��ip���߳���100�ˣ�ͬʱ100���ֶ��ڷ�����������Żᴥ������������
  if BaiduTranslateTh > BaiduTranslate_MaxSafeThread then
    begin
      OutData.WriteBool(False);
      Exit;
    end;

  // �����ӳ���Ӧģʽ��ZS�ӳٵļ�����ϵ�����ã��������ڱ�׼��ʾ���˽����Demo
  Sender.PauseResultSend;

  // ���Ǵ���һ���ص������ݽṹ�������ӳٵİ�ȫ�ͷţ�����й©
  new(sp);
  sp^.serv := TMyServer(Sender.OwnerFramework);
  sp^.ID := Sender.ID;
  // ���Կͻ��˵ķ�������
  sp^.sourLan := TTranslateLanguage(InData.Reader.ReadByte); // �����Դ����
  sp^.destLan := TTranslateLanguage(InData.Reader.ReadByte); // �����Ŀ������
  sp^.s := InData.Reader.ReadString;                         // ���ﲻ���ַ������������ַ����������ڿͻ���ȥ��
  sp^.UsedCache := InData.Reader.ReadBool;                   // �Ƿ�ʹ��cache���ݿ�
  sp^.Hash64 := FastHash64PPascalString(@sp^.s);             // ����hash

  // ��cache���ݿ��ѯ���ǵķ��룬Ч�ʸ���
  MiniDB.QueryDBP(
    False,          // ��ѯ���д�뵽���ر�
    True,           // ��ѯ�ķ��ر����ڴ�������False����һ��ʵ����ļ���
    True,           // �����ʼ��ѯ
    C_Mini_DB_Name, // ��ѯ��Ŀ�����ݿ�����
    '',             // ���ر�����ƣ���Ϊ���ǲ�������������
    True,           // ��ѯ���ʱ���ͷŷ��ر�
    0,              // ��ѯ���ʱ���ͷŷ��ر���ӳ�ʱ�䣬��λ����
    0.1,            // ��Ƭ����ʱ�䣬����ѯ�кܶ෴��ʱ��ÿ���۵����ʱ�䣬�ʹ��������¼������������������ڻ���ʱ���У����ݶ��������ڴ�
    0,              // ��ѯִ��ʱ��,0������
    0,              // ���Ĳ�ѯ��Ŀƥ��������0������
    1,              // ���Ĳ�ѯ�������������ֻ��һ�����ǵķ���cache
      procedure(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean)
    var
        p: PDelayReponseSource;
        J: TJsonObject;
        cli: TPeerIO;
    begin
        // ��ѯ�������ص�
        p := dPipe.UserPointer;

        // ����ͻ���UsedCacheΪ�٣�����ֱ�ӽ�����ѯ������������ѯ����¼���ȥ
        if not p^.UsedCache then
        begin
            dPipe.stop;
            Exit;
        end;

        // ��һ����ZDB����Ҫ���ٻ��ƣ�json��ʵ���Ǳ��˻��������ģ������ݿⷱæʱ��json���ᱻ�ͷţ�����Ϊcache���ڴ���
        J := qState.dbEng.GetJson(qState);

        Allowed :=
        (p^.Hash64 = J.u['h']) // ������hash����߱����ٶ�
        and (TTranslateLanguage(J.i['sl']) = p^.sourLan) and (TTranslateLanguage(J.i['dl']) = p^.destLan)
        and (p^.s.Same(TPascalString(J.s['s'])));

        if Allowed then
        begin
            cli := p^.serv.PeerIO[p^.ID];

            // ���ӳټ�����ϵ�У��ͻ��˿��ܷ���������Ͷ�����
            // ������ߣ�cli����nil
            if cli <> nil then
            begin
                cli.OutDataFrame.WriteBool(True);       // ����ɹ�״̬
                cli.OutDataFrame.WriteString(J.s['d']); // ������ɵ�Ŀ������
                cli.OutDataFrame.WriteBool(True);       // �����Ƿ�����cache���ݿ�
                cli.ContinueResultSend;
            end;

            // �����˳��Ժ󣬺�̨��ѯ���Զ���������Ϊ����ֻ��Ҫһ������
        end;
    end,
    procedure(dPipe: TZDBPipeline)
    var
      p: PDelayReponseSource;
    begin
      p := dPipe.UserPointer;
      // ����ҵ���һ��������dPipe.QueryResultCounter�ͻ���1�����������ͷŸղ�������ڴ�
      if dPipe.QueryResultCounter > 0 then
        begin
          Dispose(p);
          Exit;
        end;

      // �����Cache���ݿ���û���ҵ������ǵ��ðٶ�api�����ҽ����������浽cahce���ݿ�
      BaiduTranslateWithHTTP(False, p^.sourLan, p^.destLan, p^.s, p, procedure(UserData: Pointer; Success: Boolean; sour, dest: TPascalString)
        var
          cli: TPeerIO;
          n: TPascalString;
          js: TJsonObject;
          p: PDelayReponseSource;
        begin
          p := UserData;
          cli := TPeerIO(PDelayReponseSource(UserData)^.serv.PeerIO[PDelayReponseSource(UserData)^.ID]);
          // ���ӳټ�����ϵ�У��ͻ��˿��ܷ���������Ͷ�����
          // ������ߣ�cli����nil
          if cli <> nil then
            begin
              cli.OutDataFrame.WriteBool(Success);
              if Success then
                begin
                  cli.OutDataFrame.WriteString(dest);
                  cli.OutDataFrame.WriteBool(False); // �����Ƿ�����cache���ݿ�

                  // ֻ�е��ͻ��˵�UsedCacheΪ�����ǲ�д�뷭����Ϣ�����ݿ�
                  if p^.UsedCache then
                    begin
                      // ����ѯ�����¼�����ݿ�
                      // ��Ϊ����200�������룬�ͱ�����ٶȽ�Ǯ
                      js := TJsonObject.Create;
                      js.i['sl'] := Integer(p^.sourLan);
                      js.i['dl'] := Integer(p^.destLan);
                      js.u['h'] := FastHash64PPascalString(@p^.s);
                      js.F['t'] := Now;
                      js.s['s'] := p^.s.Text;
                      js.s['d'] := dest.Text;
                      js.s['ip'] := cli.PeerIP;

                      MiniDB.PostData(C_Mini_DB_Name, js);

                      // ��ubuntu������ģʽ�£��޷���ʾ����
{$IFNDEF Linux}
                      DoStatus('new cache %s', [js.ToString]);
{$IFEND}
                      DisposeObject(js);
                    end;
                end;

              // ������Ӧ
              cli.ContinueResultSend;
            end;
          Dispose(p);
        end);
    end).UserPointer := sp;
end;

// ����cache���ݿ⣬�����ʵ�ֻ��������޵������ݿ�ĩβ׷��һ�������¼�����ﲢ����ɾ��֮ǰ�Ķ���
// �ٶȷ����cache���ݿ�Ĳ�ѯ�Ǵ�ĩβ��ʼ����������׷��Ҳ��ͬ���޸���
procedure cmd_UpdateTranslate(Sender: TPeerIO; InData: TDataFrameEngine);
var
  sourLan, destLan: TTranslateLanguage;
  s, d: TPascalString;
  Hash64: THash64;
  js: TJsonObject;
begin
  sourLan := TTranslateLanguage(InData.Reader.ReadByte); // �����Դ����
  destLan := TTranslateLanguage(InData.Reader.ReadByte); // �����Ŀ������
  s := InData.Reader.ReadString;                         // Դ��
  d := InData.Reader.ReadString;                         // ����
  Hash64 := FastHash64PPascalString(@s);                 // ����hash

  js := TJsonObject.Create;
  js.i['sl'] := Integer(sourLan);
  js.i['dl'] := Integer(destLan);
  js.u['h'] := Hash64;
  js.F['t'] := Now;
  js.s['s'] := s.Text;
  js.s['d'] := d.Text;
  js.s['ip'] := Sender.PeerIP;
  MiniDB.PostData(C_Mini_DB_Name, js);

  // ��ubuntu������ģʽ�£��޷���ʾ����
{$IFNDEF Linux}
  DoStatus('update cache %s', [js.ToString]);
{$IFEND}
  DisposeObject(js);
end;

procedure Init_BaiduTranslateAccound;
var
  cfg: THashStringList;
begin
  // ʹ�����е�ַ����ٶȷ���
  // http://api.fanyi.baidu.com

  cfg := THashStringList.Create;
  if umlFileExists(umlCombineFileName(umlCurrentPath(), 'zTranslate.conf')) then
    begin
      cfg.LoadFromFile(umlCombineFileName(umlCurrentPath(), 'zTranslate.conf'));
      BaiduTranslate_Appid := cfg.GetDefaultValue('AppID', BaiduTranslate_Appid);
      BaiduTranslate_Key := cfg.GetDefaultValue('Key', BaiduTranslate_Key);
    end
  else
    begin
      cfg.SetDefaultValue('AppID', BaiduTranslate_Appid);
      cfg.SetDefaultValue('Key', BaiduTranslate_Key);
      cfg.SaveToFile(umlCombineFileName(umlCurrentPath(), 'zTranslate.conf'));
    end;
  DisposeObject(cfg);
end;

var
  server_1, server_2: TMyServer;

begin
  // ��ʼ���ٶȷ����˺�
  Init_BaiduTranslateAccound;

  MiniDB := TZDBLocalManager.Create;
  // ��Ϊ�����ļ���ʽ�����ݿ⣬�������־���ctrl+f2��ǿ�ˣ����ݿ��������
  MiniDB.InitDB(C_Mini_DB_Name);

  server_1 := TMyServer.Create;
  // ʹ����ǿ����ϵͳ��3�μ�DES�������ܽ��ECB
  server_1.SwitchMaxSecurity;
  // �����Ubuntu��ʹ��indy���������������ָ���󶨵Ļػ���ַ
  // if server_IPv4.StartService('0.0.0.0', 59813) then

  // �°汾��CrossSocket�Ѿ��޸�����Ubuntu��ipv4+ipv6ͬʱ����һ���˿�����
  // ��ôʹ�ÿ��ַ�ͬʱ����ipv4+ipv6��59813
  if server_1.StartService('', 59813) then
      DoStatus('start service with ipv4:59813 success')
  else
      DoStatus('start service with ipv4:59813 failed!');

  // ���ǣ�������Ȼ����ͬʱ�����������ͬʱ����ipv6,ipv4�͸�����ͬ�˿ڣ�Ȼ���ٽ�ָ�����ָ��ͬһ���ط�
  // �����ɿ��������κ�һ���ⲿ�������ӿڣ�DIOCP,Cross,Indy,ICS�ȵȷ������ӿھ��������ַ�ʽʵ�ֶ������ļ���ʽ����

  // �����linux����ipv6��������Ҫô�Լ�װipv6�����ģ�飬Ҫô��������
  server_2 := TMyServer.Create;
  // ʹ����ǿ����ϵͳ��3�μ�DES�������ܽ��ECB
  server_2.SwitchMaxSecurity;
  if server_2.StartService('::', 59814) then
      DoStatus('start service with ipv6:59814 success')
  else
      DoStatus('start service with ipv6:59814 failed!');

  server_1.RegisterStream('BaiduTranslate').OnExecuteCall := cmd_BaiduTranslate;
  server_2.RegisterStream('BaiduTranslate').OnExecuteCall := cmd_BaiduTranslate;

  server_1.RegisterDirectStream('UpdateTranslate').OnExecuteCall := cmd_UpdateTranslate;
  server_2.RegisterDirectStream('UpdateTranslate').OnExecuteCall := cmd_UpdateTranslate;

  // 15�����ʱ�Ͽ�����
  server_1.IdleTimeout := 15000;
  server_2.IdleTimeout := 15000;

  server_1.QuietMode := True;
  server_2.QuietMode := True;

  while True do
    begin
      MiniDB.Progress;
      server_1.Progress;
      server_2.Progress;

      // ��ɫ������������࿪��
      if server_1.Count + server_2.Count > 0 then
          CoreClasses.CheckThreadSynchronize(1)
      else
          CoreClasses.CheckThreadSynchronize(100);
    end;

end.
