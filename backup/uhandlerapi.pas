unit uhandlerapi;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, zstream,

  // =================================================================
  // [DAFTAR MODUL]: TAMBAHKAN UNIT MODUL BARU ANDA DI BAWAH INI
  // =================================================================
  umod_auth,
  //umod_pasien; // <-- Jika membuat umod_dokter, umod_ranap, dst, tambahkan di sini separated by comma
  umod_getObatTanpaAuth,
  umod_inacbg,
  umod_riwayat;

procedure RegistrasiSemuaRute(ARoutesCollection: TCollection; AZConn: TZConnection; AIPTracker: TStringList);

// Ekspos fungsi middleware global agar bisa dipanggil oleh semua umod_*.pas
function IsAuthenticatedtoken(ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse): Boolean;
function CheckRateLimit(AIP: string): Boolean;
function KompresStringKeGZip(const AInput: string): string;

var
  gZConn: TZConnection;
  gIPTracker: TStringList;

implementation

procedure RegistrasiSemuaRute(ARoutesCollection: TCollection; AZConn: TZConnection; AIPTracker: TStringList);
begin
  gZConn := AZConn;
  gIPTracker := AIPTracker;

  // =================================================================
  // [REGISTRASI RUTE]: TAMBAHKAN INSTANCE CLASS BARU DI SINI
  // Bagian ini akan TERUS BERTAMBAH seiring bertambahnya modul Khanza
  // =================================================================

  // 1. Modul Autentikasi / Login
  TRouteGetToken.Create(ARoutesCollection);


  // 2. Modul Pasien (CRUD, Pencarian)
  //TRoutePasien.Create(ARoutesCollection);

  // 3. Modul Dokter (Contoh masa depan)
  // TRouteDokter.Create(ARoutesCollection);

  // 4. Modul Registrasi & Booking (Contoh masa depan)
  // TRouteRegistrasi.Create(ARoutesCollection);

  // Registrasi endpoint obat tanpa auth
   // <-- Tambahkan di sini
  TRouteObatTanpaAuth.Create(ARoutesCollection);
  // Registrasi kelas modul INACBG
  TRouteInacbgPasien.Create(ARoutesCollection);
  TRouteInacbgDetailPasien.Create(ARoutesCollection);

  ///riwayat
  TRouteRiwayatPasien.Create(ARoutesCollection)
end;

// =================================================================
// CORE MIDDLEWARES (Sistem Keamanan & Utility Global)
// =================================================================
function IsAuthenticatedtoken(ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse): Boolean;
var
  vToken: string;
  vQueryUser: TZQuery;
begin
  Result := False;

  // =================================================================
  // KODINGAN SATPAM DISIPLIN TINGGI (ANTI GARBAGE BUFFER / SERVER GONE AWAY)
  // =================================================================
  {try
    // Cek fisik koneksi dengan Ping
    if (not gZConn.Connected) or (not gZConn.Ping) then
    begin
      Writeln('-> [WARNING] Koneksi mati/stale terdeteksi. Melakukan Hard Reset Pool...');

      gZConn.Disconnect;
      // Memaksa driver Zeos mengosongkan semua buffer koneksi lama di memori
      gZConn.Properties.Values['pooled'] := 'false';
      gZConn.Properties.Values['pooled'] := 'true';

      gZConn.Connect;
      Writeln('-> [SUKSES] Pool database disegarkan total.');
    end;
  except
    on E: Exception do
    begin
      Writeln('-> [CRITICAL] Database lumpuh total: ' + E.Message);
      AResponse.Send('{"status": "error", "message": "Database server tidak merespon"}//', 'application/json', 500);
      {Exit;
    end;
  end;}

  vRetryCount := 0;
  while (vRetryCount < 3) do
  begin
    try
      // Jika terdeteksi tidak konek, atau gagal tes Ping fisik ke MariaDB
      if (not gZConn.Connected) or (not gZConn.Ping) then
      begin
        Writeln('-> [WARNING] Jalur database tidak aktif. Membuka ulang paksa...');

        // Putus total dan bersihkan cache pool internal Zeos di memori
        gZConn.Disconnect;
        gZConn.Properties.Values['pooled'] := 'false';
        gZConn.Properties.Values['pooled'] := 'true';

        // Paksa buka kembali
        gZConn.Connect;

        if gZConn.Connected then
        begin
          Writeln('-> [SUKSES] Koneksi pulih kembali dari kondisi mati.');
          Break; // Keluar dari loop re-try karena sudah sukses terbuka
        end;
      end
      else
      begin
        // Jika koneksi sehat dan lolos Ping, langsung amankan jalur keluar loop
        Break;
      end;
    except
      on E: Exception do
      begin
        Inc(vRetryCount);
        Writeln('-> [RETRY ' + IntToStr(vRetryCount) + '] Gagal memulihkan database: ' + E.Message);
        Sleep(500); // Beri jeda setengah detik sebelum mencoba mengetuk pintu MySQL lagi
      end;
    end;
  end;

  // Proteksi Final jika setelah 3x percobaan database masih emoh terbuka
  if (not gZConn.Connected) then
  begin
    Writeln('-> [CRITICAL] Koneksi database lumpuh total setelah 3x re-try.');
    AResponse.Send('{"status": "error", "message": "Database server menolak koneksi (Not Opened Yet)"}', 'application/json', 500);
    Exit;
  end;

  // =================================================================

  vToken := ARequest.Headers.Values['Authorization'];

  if vToken = '' then
  begin
    AResponse.Send('{"status": "error", "message": "Token missing"}', 'application/json', 401);
    Exit;
  end;

  // Mengatasi prefix "Bearer " jika klien mengirimkan dengan format "Bearer <token>"
  if Pos('Bearer ', vToken) = 1 then
    vToken := Copy(vToken, 7, Length(vToken));

  vQueryUser := TZQuery.Create(nil);
  try
    vQueryUser.Connection := gZConn;
    // Membaca dari tabel custom pendamping
    vQueryUser.SQL.Text := 'SELECT id_user FROM user_api_token WHERE token = :token LIMIT 1';
    vQueryUser.ParamByName('token').AsString := vToken;
    vQueryUser.Open;

    if not vQueryUser.IsEmpty then
      Result := True
    else
      AResponse.Send('{"status": "error", "message": "Token tidak valid atau kedaluwarsa"}', 'application/json', 401);
  finally
    vQueryUser.Free;
  end;
end;

function CheckRateLimit(AIP: string): Boolean;
var
  vIndex, vHitCount: Integer;
  vCurrentTime, vLastResetTime: TDateTime;
  vDataStr, vHitStr, vTimeStr: string;
  vPosPemisah: Integer;
begin
  // PENGAMAN RAM: Jika daftar tracker IP sudah terlalu banyak, reset demi mengosongkan RAM
  if gIPTracker.Count > 2000 then
    gIPTracker.Clear;

  Result := True;
  vCurrentTime := Now;
  vIndex := gIPTracker.IndexOfName(AIP);

  if vIndex = -1 then
    gIPTracker.Add(AIP + '=1|' + DateTimeToStr(vCurrentTime + (1 / 1440))) // Reset tiap 1 menit
  else begin
    vDataStr := gIPTracker.ValueFromIndex[vIndex];
    vPosPemisah := Pos('|', vDataStr);
    vHitStr := Copy(vDataStr, 1, vPosPemisah - 1);
    vTimeStr := Copy(vDataStr, vPosPemisah + 1, Length(vDataStr));
    vHitCount := StrToIntDef(vHitStr, 0);
    vLastResetTime := StrToDateTimeDef(vTimeStr, vCurrentTime);

    if vCurrentTime > vLastResetTime then
      gIPTracker.Strings[vIndex] := AIP + '=1|' + DateTimeToStr(vCurrentTime + (1 / 1440))
    else begin
      Inc(vHitCount);
      if vHitCount > 30 then Result := False; // Limit 30 request per menit per IP
      gIPTracker.Strings[vIndex] := AIP + '=' + IntToStr(vHitCount) + '|' + DateTimeToStr(vLastResetTime);
    end;
  end;
end;

function KompresStringKeGZip(const AInput: string): string;
var
  vStreamInput, vStreamOutput: TStringStream;
  vKompresor: TCompressionStream;
begin
  Result := '';
  if AInput = '' then Exit;

  vStreamInput := TStringStream.Create(AInput);
  vStreamOutput := TStringStream.Create('');
  vKompresor := TCompressionStream.Create(cldefault, vStreamOutput);
  try
    vKompresor.CopyFrom(vStreamInput, vStreamInput.Size);
    vKompresor.Free;
    Result := vStreamOutput.DataString;
  finally
    vStreamInput.Free;
    vStreamOutput.Free;
  end;
end;

end.
