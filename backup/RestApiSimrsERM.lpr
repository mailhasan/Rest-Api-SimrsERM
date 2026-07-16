program RestApiSimrsERM;

{$MODE DELPHI} // Samakan dengan unit handler agar kompatibel penuh

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, CustApp, IniFiles,
  ZConnection, BrookHTTPServer, BrookURLRouter, BrookHTTPRequest, BrookHTTPResponse,
  uhandlerapi, umod_getObatTanpaAuth, umod_auth, umod_riwayat, umod_master_penyakit;

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
    // PERBAIKAN: Pastikan ARequest tidak ganda
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

  // --- KELAS HELPER UNTUK EVENT HANDLER NON-FORM ---
  { TZeosKeepAliveBridge }
  TZeosKeepAliveBridge = class
  public
    procedure HandleConnectionLost(Sender: TObject);
  end;

var
  gZConnectiondb: TZConnection;
  gIPTracker: TStringList;
  gLogFile: string; // Menyimpan path file log
  gZeosBridge: TZeosKeepAliveBridge; // Bridge objek untuk menangani event ZConnection

// --- PROSEDUR LOGGING YANG SUDAH DIPERBAIKI ---
procedure LogWrite(const AMsg: string);
var
  vLogText: string;
  vFileStream: TFileStream;
begin
  // Format log: [YYYY-MM-DD HH:NN:SS] Pesan Log + Baris Baru (CRLF)
  vLogText := FormatDateTime('[yyyy-mm-dd hh:nn:ss] ', Now) + AMsg + sLineBreak;

  // 1. Tampilkan di layar terminal/konsol
  Write(FormatDateTime('[yyyy-mm-dd hh:nn:ss] ', Now) + AMsg + LineEnding);

  // 2. Simpan atau Append ke dalam file teks
  try
    if not FileExists(gLogFile) then
      vFileStream := TFileStream.Create(gLogFile, fmCreate)
    else
      vFileStream := TFileStream.Create(gLogFile, fmOpenWrite or fmShareDenyNone);

    try
      vFileStream.Seek(0, soEnd); // Pindahkan kursor ke baris paling akhir (Append)

      if Length(vLogText) > 0 then
        vFileStream.WriteBuffer(vLogText[1], Length(vLogText));
    finally
      vFileStream.Free;
    end;
  except
    Writeln('-> [CRITICAL ERROR] Gagal menulis ke file log!');
  end;
end;

{ TZeosKeepAliveBridge }
procedure TZeosKeepAliveBridge.HandleConnectionLost(Sender: TObject);
begin
  LogWrite('-> [WARNING] Koneksi database terputus sepihak! Mencoba menyambung kembali...');
  try
    // Memaksa koneksi pool melakukan reconnect global
    TZConnection(Sender).Reconnect;
    LogWrite('-> [RECOVERY] Reconnect database BERHASIL.');
  except
    on E: Exception do
      LogWrite('-> [CRITICAL] Reconnect GAGAL: ' + E.Message);
  end;
end;

{ TConsoleRouter }
procedure TConsoleRouter.DoNotFound(ASender: TObject; const ARoute: string;
  ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
begin
  LogWrite('-> [404 NOT FOUND] IP: ' + ARequest.IP + ' mencoba akses rute: ' + ARoute);
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
  LogWrite(Format('-> [REQUEST] %s %s dari IP: %s', [ARequest.Method, ARequest.Path, ARequest.IP]));
  FRouter.Route(ASender, ARequest, AResponse);
end;

{ TBrookConsoleApp }
procedure TBrookConsoleApp.DoRun;
var
  vPort: Integer;
  vServer: TConsoleServer;
  vIni: TIniFile;
  vConfigFile: string;
  vLastPingTick: QWord; // Untuk tracking waktu ping tanpa memblokir thread
begin
  vPort := StrToIntDef(GetOptionValue('p', 'port'), 888);

  gLogFile := Concat(ExtractFilePath(ParamStr(0)), 'server.log');

  Writeln('=====================================================');
  Writeln('    REST API SIMRS ERM KHANZA - BROOK REST API CONSOLE SERVER       ');
  Writeln('=====================================================');
  Writeln('Menginisialisasi sistem...');

  gIPTracker := TStringList.Create;
  gIPTracker.Sorted := False;

  // Instansiasi objek bridge penanganan event
  gZeosBridge := TZeosKeepAliveBridge.Create;

  vConfigFile := Concat(ExtractFilePath(ParamStr(0)), 'config.ini');
  if not FileExists(vConfigFile) then
  begin
    LogWrite('-> [ERROR] File config.ini tidak ditemukan!');
    Writeln('-> [ERROR] File config.ini tidak ditemukan!');
    gZeosBridge.Free;
    gIPTracker.Free;
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

    // Konfigurasi internal driver Zeos
    gZConnectiondb.Properties.Values['reconnect'] := 'true';
    gZConnectiondb.Properties.Values['ping_timeout'] := '5';

    // PASANG EVENT HANDLER: Antisipasi jika pool membuang koneksi secara mendadak
    //gZConnectiondb.OnConnectionLost := gZeosBridge.HandleConnectionLost;

  finally
    vIni.Free;
  end;

  try
    gZConnectiondb.Connect;
    LogWrite('-> [SUKSES] Zeos Database Connection Pool Aktif.');
    Writeln('-> [SUKSES] Zeos Database Connection Pool Aktif.');
  except
    on E: Exception do
    begin
      LogWrite('-> [ERROR] Gagal inisialisasi Database Pool: ' + E.Message);
      Writeln('-> [ERROR] Gagal inisialisasi Database Pool: ' + E.Message);
      gZeosBridge.Free;
      gIPTracker.Free;
      Terminate;
      Exit;
    end;
  end;

  vServer := TConsoleServer.Create(nil);
  vServer.Port := vPort;

  try
    vServer.Open;
    Writeln('-> [SUKSES] HTTP Server mendengarkan pada port: ' + IntToStr(vPort));
    Writeln('Tekan [CTRL + C] di terminal untuk menghentikan server.');
    Writeln('-----------------------------------------------------');

    // Inisialisasi waktu awal untuk siklus Ping aktif
    vLastPingTick := GetTickCount64;

    while not Terminated do
    begin
      CheckSynchronize(100);

      // --- MEKANISME AKTIF KEEP-ALIVE PING (Tiap 1 Menit / 60000 ms) ---
      // Karena ini aplikasi konsol, kita gunakan GetTickCount64 (non-blocking) sebagai pengganti TTimer
      if (GetTickCount64 - vLastPingTick) >= 60000 then
      begin
        vLastPingTick := GetTickCount64; // Reset timer tick

        if gZConnectiondb.Connected then
        begin
          try
            // Kirim ping ke server MariaDB. Jika server drop, fungsi ini otomatis memicu OnConnectionLost
            if not gZConnectiondb.Ping then
            begin
              LogWrite('-> [PING] Server tidak merespons, mencoba melakukan reconnect otomatis...');
              gZConnectiondb.Reconnect;
            end;
          except
            on E: Exception do
              LogWrite('-> [PING ERROR] Deteksi gangguan database: ' + E.Message);
          end;
        end;
      end;
    end;

  finally
    LogWrite('Membersihkan alokasi memori sistem...');
    Writeln('Membersihkan alokasi memori sistem...');
    vServer.Close;
    vServer.Free;
    gZConnectiondb.Disconnect;
    gZConnectiondb.Free;
    gZeosBridge.Free; // Bersihkan kelas bridge
    gIPTracker.Free;
    LogWrite('-> [OFFLINE] Server dihentikan dengan aman.');
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
