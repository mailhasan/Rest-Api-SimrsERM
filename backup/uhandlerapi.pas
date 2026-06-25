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
  umod_inacbg;

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
