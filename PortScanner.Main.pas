unit PortScanner.Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, blcksock,
  Vcl.StdCtrls, Vcl.ExtCtrls, HGM.Button;

resourcestring
  rsScan = 'Сканировать';
  rsStopScan = 'Остановить';
  rsStopping = 'Остановка';

type
  //успешное подключение к узлу IP по порту Port
  TOnConnect = procedure(Sender: TObject; const IP: string; Port: Word) of object;
  //ошибка подключения к узлу IP по порту Port; ErrorCode - код ошибки; ErrorDesk - описание ошибки

  TOnError = procedure(Sender: TObject; const IP: string; Port: Word; ErrorCode: Integer; ErrorDesc: string) of object;

  {поток для сканирования заданного диапазона портов}
  TTCPThread = class(TThread)
  private
    FSocket: TTCPBlockSocket; //объект сокета
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
     //объект потока
    TCPThread: TTCPThread;
     //обработчик события потока OnConnect
    procedure OnConnect(Sender: TObject; const IP: string; Port: word);
     //Обработчик события потока OnError
    procedure OnError(Sender: TObject; const IP: string; Port: word; ErrorCode: integer; ErrorDesc: string);
     //Вспомогательный метод для "включения/отключения" элементов управления в группе "Настройки"
    procedure EnableControls(AEnable: boolean);
     //Обработчик события завершения работы потока
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
    MemoLog.Lines.Add(Format('[%s] Началось сканирование', [TimeToStr(Now)]));
    TCPThread := TTCPThread.Create(True, //"спящий поток"
      edIPAddress.Text,                  //адрес
      StrToInt(edPortStart.Text),        //начало диапазона сканирования портов
      StrToInt(edPortEnd.Text),          //конец диапазона сканирования портов
      StrToInt(edConnectTimeout.Text));  //тайм-аут ожидания соединения
    //определяем обработчики событий потока
    TCPThread.OnConnect := OnConnect;
    TCPThread.OnError := OnError;
    TCPThread.OnTerminate := OnTerminate;
    //запускаем поток
    TCPThread.Start;
    ButtonStart.Caption := rsStopScan;
  end
  else
  begin
    //останавливаем поток и освобождаем память
    ButtonStart.Caption := rsStopping;
    TCPThread.Terminate;
    TCPThread.WaitFor;
    TCPThread.Free;
    MemoLog.Lines.Add(Format('[%s] Сканирование остановлено', [TimeToStr(Now)]));
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
  cSuccessStr = '[%s] [%s] Порт %d открыт';
begin
  MemoLog.Lines.Add(Format(cSuccessStr, [TimeToStr(Now), IP, Port]));
end;

procedure TFormMain.OnError(Sender: TObject; const IP: string; Port: word; ErrorCode: integer; ErrorDesc: string);
const
  cErrorStr = '[%s] [%s] Порт %.5d закрыт. Ошибка %d (%s)';
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
  FSocket.Free; //освобождаем память
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
    FSocket.Connect(FIP, IntToStr(i)); //пробуем соединиться
    FSocket.GetSins;
    if FSocket.LastError = 0 then //ошибок нет - соединились успешно
      DoConnect(IP, i)
    else
      DoError(IP, i); //возвращаем ошибку
    FSocket.CloseSocket; //закрывем сокет
    Inc(i);
  end;
  if not Terminated then
    FreeOnTerminate := True;
end;

initialization
  ReportMemoryLeaksOnShutdown := True;

end.

