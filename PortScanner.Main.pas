unit PortScanner.Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, blcksock,
  Vcl.StdCtrls, Vcl.ExtCtrls, HGM.Button;

resourcestring
  rsScan = '�����������';
  rsStopScan = '����������';
  rsStopping = '���������';

type
  //�������� ����������� � ���� IP �� ����� Port
  TOnConnect = procedure(Sender: TObject; const IP: string; Port: Word) of object;
  //������ ����������� � ���� IP �� ����� Port; ErrorCode - ��� ������; ErrorDesk - �������� ������

  TOnError = procedure(Sender: TObject; const IP: string; Port: Word; ErrorCode: Integer; ErrorDesc: string) of object;

  {����� ��� ������������ ��������� ��������� ������}
  TTCPThread = class(TThread)
  private
    FSocket: TTCPBlockSocket; //������ ������
    FIP: string;
    FStartPort: Word;
    FEndPort: Word;
    FOnConnect: TOnConnect;
    FOnError: TOnError;
    procedure DoConnect(const IP: string; Port: Word);
    procedure DoError(const IP: string; Port: Word);
  protected
    procedure Execute; override;
  public
    constructor Create(ASyspended: Boolean; AIP: string; AStartPort, AEndPort, ATimeout: integer);
    destructor Destroy; override;
    property OnConnect: TOnConnect read FOnConnect write FOnConnect;
    property OnError: TOnError read FOnError write FOnError;
  end;

type
  TFormMain = class(TForm)
    PanelMain: TPanel;
    PanelLog: TPanel;
    MemoLog: TMemo;
    chkWriteError: TCheckBox;
    ButtonStart: TButtonFlat;
    PanelOptions: TPanel;
    edConnectTimeout: TEdit;
    edIPAddress: TEdit;
    edPortEnd: TEdit;
    edPortStart: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    procedure ButtonStartClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
     //������ ������
    TCPThread: TTCPThread;
     //���������� ������� ������ OnConnect
    procedure OnConnect(Sender: TObject; const IP: string; Port: word);
     //���������� ������� ������ OnError
    procedure OnError(Sender: TObject; const IP: string; Port: word; ErrorCode: integer; ErrorDesc: string);
     //��������������� ����� ��� "���������/����������" ��������� ���������� � ������ "���������"
    procedure EnableControls(AEnable: boolean);
     //���������� ������� ���������� ������ ������
    procedure OnTerminate(Sender: TObject);
  public
    { Public declarations }
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

procedure TFormMain.ButtonStartClick(Sender: TObject);
begin
  EnableControls(ButtonStart.Caption <> rsScan);
  if ButtonStart.Caption = rsScan then
  begin
    MemoLog.Lines.Add(Format('[%s] �������� ������������', [TimeToStr(Now)]));
    TCPThread := TTCPThread.Create(True, //"������ �����"
      edIPAddress.Text,                  //�����
      StrToInt(edPortStart.Text),        //������ ��������� ������������ ������
      StrToInt(edPortEnd.Text),          //����� ��������� ������������ ������
      StrToInt(edConnectTimeout.Text));  //����-��� �������� ����������
    //���������� ����������� ������� ������
    TCPThread.OnConnect := OnConnect;
    TCPThread.OnError := OnError;
    TCPThread.OnTerminate := OnTerminate;
    //��������� �����
    TCPThread.Start;
    ButtonStart.Caption := rsStopScan;
  end
  else
  begin
    //������������� ����� � ����������� ������
    ButtonStart.Caption := rsStopping;
    TCPThread.Terminate;
    TCPThread.WaitFor;
    TCPThread.Free;
    MemoLog.Lines.Add(Format('[%s] ������������ �����������', [TimeToStr(Now)]));
  end;
end;

procedure TFormMain.EnableControls(AEnable: boolean);
begin
  PanelOptions.Enabled := AEnable;
end;

procedure TFormMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if Assigned(TCPThread) and (not TCPThread.Finished) then
  begin
    TCPThread.Terminate;
    TCPThread.WaitFor;
    TCPThread.Free;
  end;
end;

procedure TFormMain.OnConnect(Sender: TObject; const IP: string; Port: word);
const
  cSuccessStr = '[%s] [%s] ���� %d ������';
begin
  MemoLog.Lines.Add(Format(cSuccessStr, [TimeToStr(Now), IP, Port]));
end;

procedure TFormMain.OnError(Sender: TObject; const IP: string; Port: word; ErrorCode: integer; ErrorDesc: string);
const
  cErrorStr = '[%s] [%s] ���� %.5d ������. ������ %d (%s)';
begin
  if chkWriteError.Checked then
    MemoLog.Lines.Add(Format(cErrorStr, [TimeToStr(Now), IP, Port, ErrorCode, ErrorDesc]))
end;

procedure TFormMain.OnTerminate(Sender: TObject);
begin
  ButtonStart.Caption := rsScan;
  EnableControls(True);
end;

{ TTCPThread }

constructor TTCPThread.Create(ASyspended: boolean; AIP: string; AStartPort, AEndPort, ATimeout: integer);
begin
  inherited Create(ASyspended);
  FSocket := TTCPBlockSocket.Create;
  FSocket.HTTPTunnelTimeout := ATimeout;
  FSocket.SocksTimeout := ATimeout;
  FIP := AIP;
  FStartPort := AStartPort;
  FEndPort := AEndPort;
end;

destructor TTCPThread.Destroy;
begin
  FSocket.Free; //����������� ������
  inherited;
end;

procedure TTCPThread.DoConnect(const IP: string; Port: word);
begin
  if Assigned(FOnConnect) then
    FOnConnect(Self, IP, Port);
end;

procedure TTCPThread.DoError(const IP: string; Port: word);
begin
  if Assigned(FOnError) then
    FOnError(Self, IP, Port, FSocket.LastError, FSocket.LastErrorDesc);
end;

procedure TTCPThread.Execute;
var
  i: integer;
  IP: string;
begin
  i := FStartPort;
  IP := FSocket.ResolveName(FIP);
  while (i <= FEndPort) and (not Terminated) do
  begin
    FSocket.Connect(FIP, IntToStr(i)); //������� �����������
    FSocket.GetSins;
    if FSocket.LastError = 0 then //������ ��� - ����������� �������
      DoConnect(IP, i)
    else
      DoError(IP, i); //���������� ������
    FSocket.CloseSocket; //�������� �����
    Inc(i);
  end;
  if not Terminated then
    FreeOnTerminate := True;
end;

initialization
  ReportMemoryLeaksOnShutdown := True;

end.

