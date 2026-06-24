unit umod_auth;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, BrookURLRouter, BrookHTTPRequest, BrookHTTPResponse,
  BrookUtility, fpjson, jsonparser;

type
  { TRouteGetToken }
  TRouteGetToken = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

// Merujuk ke core handler untuk menggunakan database pool global (gZConn)
uses uhandlerapi;

procedure TRouteGetToken.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmPOST];
  Pattern := '/api/v1/login';
end;

procedure TRouteGetToken.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  JSONData: TJSONData;
  JSONObject, JSONRes, JSONPegawai: TJSONObject;
  vUserInput, vPassInput, vToken: string;
  vQueryUser, vQueryPegawai: TZQuery;
  vIDUserSah: string;
begin
  // 1. Ambil Payload JSON dari Request Body (Klien mengirimkan username & password)
  try
    JSONData := GetJSON(ARequest.Payload.ToString);
    JSONObject := TJSONObject(JSONData);
    vUserInput := JSONObject.Get('username', '');
    vPassInput := JSONObject.Get('password', '');
  except
    AResponse.Send('{"status": "error", "message": "Format JSON tidak valid"}', 'application/json', 400);
    Exit;
  end;

  if (vUserInput = '') or (vPassInput = '') then
  begin
    AResponse.Send('{"status": "error", "message": "Username dan password wajib diisi"}', 'application/json', 400);
    if Assigned(JSONData) then JSONData.Free;
    Exit;
  end;

  // 2. Inisialisasi Query untuk Validasi Login menggunakan AES_DECRYPT (Casting ke CHAR agar aman)
  vQueryUser := TZQuery.Create(nil);
  vQueryUser.Connection := uhandlerapi.gZConn;

  vQueryPegawai := TZQuery.Create(nil);
  vQueryPegawai.Connection := uhandlerapi.gZConn;

  try
    vQueryUser.SQL.Clear;
    vQueryUser.SQL.Add('SELECT ');
    vQueryUser.SQL.Add('  CAST(AES_DECRYPT(id_user, "nur") AS CHAR(30)) AS id_user_dekrpsi, ');
    vQueryUser.SQL.Add('  CAST(AES_DECRYPT(password, "windi") AS CHAR(50)) AS pass_dekrpsi ');
    vQueryUser.SQL.Add('FROM user ');
    vQueryUser.SQL.Add('WHERE AES_DECRYPT(id_user, "nur") = :user ');
    vQueryUser.SQL.Add('  AND AES_DECRYPT(password, "windi") = :pass ');
    vQueryUser.SQL.Add('LIMIT 1');

    vQueryUser.ParamByName('user').AsString := vUserInput;
    vQueryUser.ParamByName('pass').AsString := vPassInput;
    vQueryUser.Open;

    // Jika user ditemukan dan password cocok
    if not vQueryUser.IsEmpty then
    begin
      vIDUserSah := vQueryUser.FieldByName('id_user_dekrpsi').AsString;
      vQueryUser.Close;

      // 3. Ambil data pegawai berdasarkan id_user yang sah (id_user di tabel user Khanza berelasi dengan NIK di tabel pegawai)
      vQueryPegawai.SQL.Clear;
      vQueryPegawai.SQL.Add('SELECT nik, nama, jk, jbtn, tmp_lahir, tgl_lahir, stts_aktif, no_ktp ');
      vQueryPegawai.SQL.Add('FROM pegawai ');
      vQueryPegawai.SQL.Add('WHERE nik = :nik ');
      vQueryPegawai.SQL.Add('LIMIT 1');

      vQueryPegawai.ParamByName('nik').AsString := vIDUserSah;
      vQueryPegawai.Open;

      // 4. Generate SHA1 Token untuk Sesi API ini
      vToken := Brook.SHA1(TGUID.NewGuid.ToString + vIDUserSah + DateTimeToStr(Now));

      // 5. Update token ke tabel user agar middleware mengenali request berikutnya
      vQueryUser.SQL.Clear;
      vQueryUser.SQL.Text :=
                            'INSERT INTO user_api_token (id_user, token, last_activity) VALUES (:id, :token, NOW()) ' +
                            'ON DUPLICATE KEY UPDATE token = :token, last_activity = NOW()';
      vQueryUser.ParamByName('token').AsString := vToken;
      vQueryUser.ParamByName('user').AsString := vIDUserSah;
      vQueryUser.ExecSQL;

      // 6. Susun Response JSON Sukses
      JSONRes := TJSONObject.Create;
      JSONRes.Add('status', 'success');
      JSONRes.Add('token', vToken);

      // Masukkan objek data pegawai jika data pegawainya ditemukan
      if not vQueryPegawai.IsEmpty then
      begin
        JSONPegawai := TJSONObject.Create;
        JSONPegawai.Add('nik', vQueryPegawai.FieldByName('nik').AsString);
        JSONPegawai.Add('nama', vQueryPegawai.FieldByName('nama').AsString);
        JSONPegawai.Add('jk', vQueryPegawai.FieldByName('jk').AsString);
        JSONPegawai.Add('jabatan', vQueryPegawai.FieldByName('jbtn').AsString);
        JSONPegawai.Add('tempat_lahir', vQueryPegawai.FieldByName('tmp_lahir').AsString);
        JSONPegawai.Add('tanggal_lahir', vQueryPegawai.FieldByName('tgl_lahir').AsString);
        JSONPegawai.Add('status_aktif', vQueryPegawai.FieldByName('stts_aktif').AsString);
        JSONPegawai.Add('no_ktp', vQueryPegawai.FieldByName('no_ktp').AsString);

        JSONRes.Add('pegawai', JSONPegawai);
      end else begin
        JSONRes.Add('pegawai', TJSONNull.Create); // Jika user ada tapi data di tabel pegawai kosong
      end;

      AResponse.Send(JSONRes.AsJSON, 'application/json', 200);
      JSONRes.Free;
    end
    else
    begin
      // Jika kombinasi username & password salah
      AResponse.Send('{"status": "error", "message": "Kombinasi Username atau Password salah!"}', 'application/json', 401);
    end;

  except
    on E: Exception do
    begin
      AResponse.SendFmt('{"status": "error", "message": "Internal Server Error: %s"}', [E.Message], 'application/json', 500);
    end;
  end;

  // Memastikan pembersihan memori secara aman (Thread-Safe)
  vQueryUser.Free;
  vQueryPegawai.Free;
  JSONData.Free;
end;

end.
