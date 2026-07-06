program RestApiSimrsERM;

{$MODE DELPHI} // Samakan dengan unit handler agar kompatibel penuh

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, CustApp,IniFiles,
  ZConnection, BrookHTTPServer, BrookURLRouter, BrookHTTPRequest, BrookHTTPResponse,
  uhandlerapi, umod_getObatTanpaAuth, umod_auth, umod_riwayat;

type
  { TConsoleRouter }
  TConsoleRouter = class(TBrookURLRouter)
  protected
    // Mengamankan penanganan rute jika tidak ditemukan (404)
    procedure DoNotFound(ASender: TObject; const ARoute: string;
      ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse); override;
  end;

  { TConsoleServer }
  TConsoleServer = class(TBrookHTTPServer)
  private
    FRouter: TConsoleRouter;
  protected
    procedure DoRequest(ASender: TObject; ARequest: TBrookHTTPRequest;
      AResponse: TBrookHTTPResponse); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

  { TBrookConsoleApp }
  TBrookConsoleApp = class(TCustomApplication)
  protected
    procedure DoRun; override;
  end;

var
  gZConnectiondb: TZConnection;
  gIPTracker: TStringList;

{ TConsoleRouter }
procedure TConsoleRouter.DoNotFound(ASender: TObject; const ARoute: string;
  ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
begin
  AResponse.Send('{"status": "error", "message": "Endpoint not found!"}', 'application/json', 404);
end;

{ TConsoleServer }
constructor TConsoleServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRouter := TConsoleRouter.Create(Self);

  // REGISTRASI OTOT: Panggil shared brain kita ke koleksi FRouter.Routes
  RegistrasiSemuaRute(FRouter.Routes, gZConnectiondb, gIPTracker);

  FRouter.Active := True;
end;

destructor TConsoleServer.Destroy;
begin
  FRouter.Free;
  inherited Destroy;
end;

procedure TConsoleServer.DoRequest(ASender: TObject; ARequest: TBrookHTTPRequest;
  AResponse: TBrookHTTPResponse);
begin
  // Meneruskan request jaringan secara aman ke engine router
  FRouter.Route(ASender, ARequest, AResponse);
end;

{ TBrookConsoleApp }
procedure TBrookConsoleApp.DoRun;
var
  vPort: Integer;
  vServer: TConsoleServer;
  vIni: TIniFile;
  vConfigFile: string;
begin
  vPort := StrToIntDef(GetOptionValue('p', 'port'), 8888);

  Writeln('=====================================================');
  Writeln('   REST API SIMRS ERM KHANZA - BROOK REST API CONSOLE SERVER       ');
  Writeln('=====================================================');
  Writeln('Menginisialisasi sistem...');

  gIPTracker := TStringList.Create;
  gIPTracker.Sorted := False;

  // setting langsung pada coding
  {gZConnectiondb := TZConnection.Create(nil);
  gZConnectiondb.Protocol := 'mysql'; // atau 'mysql' sesuai server Khanza Anda
  gZConnectiondb.HostName := '192.168.200.201'; // IP Server Database SIMRS Khanza
  gZConnectiondb.Port     := 3306;
  gZConnectiondb.User     := 'simrs';      // Sesuaikan user database Khanza
  gZConnectiondb.Password := '5tronG!-V3rY-P4ssW0rd@1113!';  // Sesuaikan password database Khanza
  gZConnectiondb.Database := 'sik';      // Nama database default SIMRS Khanza (sik)

  // Tetap pertahankan connection pool agar performa REST API tinggi
  gZConnectiondb.Properties.Values['controls'] := 'true';
  gZConnectiondb.Properties.Values['pooled'] := 'true';
  gZConnectiondb.Properties.Values['maxconnections'] := '100'; // Bisa dinaikkan ke 100 untuk Khanza
  gZConnectiondb.Properties.Values['idle_timeout'] := '60';}

  // membaca file dari config.ini
  vConfigFile := Concat(ExtractFilePath(ParamStr(0)), 'config.ini');
  if not FileExists(vConfigFile) then
  begin
    Writeln('-> [ERROR] File config.ini tidak ditemukan!');
    Terminate;
    Exit;
  end;

  vIni := TIniFile.Create(vConfigFile);
  try
    gZConnectiondb := TZConnection.Create(nil);
    gZConnectiondb.Protocol := 'mariadb';
    gZConnectiondb.HostName := vIni.ReadString('Database', 'Host', '127.0.0.1');
    gZConnectiondb.Port     := vIni.ReadInteger('Database', 'Port', 3306);
    gZConnectiondb.User     := vIni.ReadString('Database', 'User', 'root');
    gZConnectiondb.Password := vIni.ReadString('Database', 'Password', '');
    gZConnectiondb.Database := vIni.ReadString('Database', 'Database', 'sik');

    gZConnectiondb.Properties.Values['controls'] := 'true';
    gZConnectiondb.Properties.Values['pooled'] := 'true';
    gZConnectiondb.Properties.Values['maxconnections'] := vIni.ReadString('Database', 'MaxConnections', '50');
    gZConnectiondb.Properties.Values['idle_timeout'] := vIni.ReadString('Database', 'IdleTimeout', '60');
    // Tambahkan 3 baris sakti ini untuk mendeteksi dan menyambung ulang otomatis:
    gZConnectiondb.Properties.Values['reconnect'] := 'true';     // Aktifkan auto-reconnect bawaan driver
    gZConnectiondb.Properties.Values['ping_timeout'] := '5';     // Deteksi ping putus dalam 5 detik
    gZConnectiondb.Properties.Values['keepalive'] := '30';       // Kirim sinyal ping internal tiap 30 detik

  finally
    vIni.Free;
  end;

  try
    gZConnectiondb.Connect;
    Writeln('-> [SUKSES] Zeos Database Connection Pool Aktif.');
  except
    on E: Exception do
    begin
      Writeln('-> [ERROR] Gagal inisialisasi Database Pool: ' + E.Message);
      gIPTracker.Free;
      Terminate;
      Exit;
    end;
  end;

  // Instansiasi Server berbasis Class-Wrapper yang baru
  vServer := TConsoleServer.Create(nil);
  vServer.Port := vPort;

  try
    vServer.Open;
    Writeln('-> [SUKSES] HTTP Server mendengarkan pada port: ' + IntToStr(vPort));
    Writeln('Tekan [CTRL + C] di terminal untuk menghentikan server.');
    Writeln('-----------------------------------------------------');

    while not Terminated do
    begin
      CheckSynchronize(100);
    end;

  finally
    Writeln('Membersihkan alokasi memori sistem...');
    vServer.Close;
    vServer.Free;
    gZConnectiondb.Disconnect;
    gZConnectiondb.Free;
    gIPTracker.Free;
  end;

  Terminate;
end;

var
  Application: TBrookConsoleApp;
begin
  Application := TBrookConsoleApp.Create(nil);
  Application.Run;
  Application.Free;
end.
