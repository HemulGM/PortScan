program PortScanner;

uses
  Vcl.Forms,
  PortScanner.Main in 'PortScanner.Main.pas' {FormMain};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
