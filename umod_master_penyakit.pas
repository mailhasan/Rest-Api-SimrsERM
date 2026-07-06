unit umod_master_penyakit;

{$MODE DELPHI} // Menggunakan mode Delphi agar selaras dengan pola uhandlerapi

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, fpjson, jsonparser, BrookUtility;

type
  { TRouteMasterPenyakitCRUD }
  TRouteMasterPenyakitCRUD = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TRouteMasterPenyakitCRUD }
uses uhandlerapi;

procedure TRouteMasterPenyakitCRUD.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET, rmPOST, rmPUT, rmDELETE];
  Pattern := 'api/v1/penyakit'; // Endpoint URL: /api/penyakit
end;

procedure TRouteMasterPenyakitCRUD.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vKdPenyakit, vNmPenyakit, vCiriCiri, vKeterangan, vKdKtg, vStatus, vTampil, vKeyword, vPayloadStr: string;
  vJSONData: TJSONData;
  vJSONReq, vJSONItem: TJSONObject;
  vJSONArray: TJSONArray;
  vQuery: TZQuery;
begin
  // Validasi Token via Satpam Global uhandlerapi
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  vQuery := TZQuery.Create(nil);
  vQuery.Connection := uhandlerapi.gZConn;

  try
    // =================================================================
    // 1. OPERATION: GET (READ DATA MASTER PENYAKIT + JOIN KATEGORI)
    // =================================================================
    if ARequest.Method = 'GET' then
    begin
      vKeyword := ARequest.Params.Values['keyword'];
      vJSONArray := TJSONArray.Create;

      try
        vQuery.SQL.Clear;
        vQuery.SQL.Add('SELECT p.kd_penyakit, p.nm_penyakit, p.ciri_ciri, p.keterangan, ');
        vQuery.SQL.Add('       p.kd_ktg, kp.nm_kategori, p.status AS status_menular, p.tampil ');
        vQuery.SQL.Add('FROM penyakit p ');
        vQuery.SQL.Add('LEFT JOIN kategori_penyakit kp ON p.kd_ktg = kp.kd_ktg ');
        vQuery.SQL.Add('WHERE 1=1 ');

        if vKeyword <> '' then
        begin
          vQuery.SQL.Add('AND (p.kd_penyakit LIKE :keyword OR p.nm_penyakit LIKE :keyword OR kp.nm_kategori LIKE :keyword) ');
        end;
        vQuery.SQL.Add('ORDER BY p.kd_penyakit ASC LIMIT 100');

        if vKeyword <> '' then
          vQuery.ParamByName('keyword').AsString := '%' + vKeyword + '%';

        vQuery.Open;

        while not vQuery.EOF do
        begin
          vJSONItem := TJSONObject.Create;
          vJSONItem.Add('kd_penyakit', Trim(vQuery.FieldByName('kd_penyakit').AsString));
          vJSONItem.Add('nm_penyakit', Trim(vQuery.FieldByName('nm_penyakit').AsString));
          vJSONItem.Add('ciri_ciri', Trim(vQuery.FieldByName('ciri_ciri').AsString));
          vJSONItem.Add('keterangan', Trim(vQuery.FieldByName('keterangan').AsString));
          vJSONItem.Add('kd_ktg', Trim(vQuery.FieldByName('kd_ktg').AsString));
          vJSONItem.Add('nm_kategori', Trim(vQuery.FieldByName('nm_kategori').AsString));
          vJSONItem.Add('status_menular', vQuery.FieldByName('status_menular').AsString);
          vJSONItem.Add('tampil', vQuery.FieldByName('tampil').AsString);
          vJSONArray.Add(vJSONItem);
          vQuery.Next;
        end;

        AResponse.Send(vJSONArray.AsJSON, 'application/json; charset=utf-8', 200);
      finally
        vJSONArray.Free;
      end;
    end

    // =================================================================
    // 2. OPERATION: POST (CREATE / INSERT MASTER PENYAKIT ANTI-DUPLICATE)
    // =================================================================
    else if ARequest.Method = 'POST' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vKdPenyakit  := Trim(vJSONReq.Get('kd_penyakit', ''));
        vNmPenyakit  := Trim(vJSONReq.Get('nm_penyakit', ''));
        vCiriCiri    := Trim(vJSONReq.Get('ciri_ciri', ''));
        vKeterangan  := Trim(vJSONReq.Get('keterangan', ''));
        vKdKtg       := Trim(vJSONReq.Get('kd_ktg', ''));
        vStatus      := Trim(vJSONReq.Get('status_menular', 'Tidak Menular')); // Menular / Tidak Menular
        vTampil      := Trim(vJSONReq.Get('tampil', 'YA')); // YA / TIDAK

        if (vKdPenyakit = '') or (vNmPenyakit = '') then
          raise Exception.Create('Parameter kd_penyakit dan nm_penyakit wajib diisi!');

        // PRE-CHECK DUPLIKASI KUNCI PRIMER
        vQuery.SQL.Clear;
        vQuery.SQL.Add('SELECT COUNT(*) AS jumlah FROM penyakit WHERE kd_penyakit = :kd_penyakit');
        vQuery.ParamByName('kd_penyakit').AsString := vKdPenyakit;
        vQuery.Open;

        if vQuery.FieldByName('jumlah').AsInteger > 0 then
        begin
          // Jika kode penyakit sudah ada, otomatis alihkan ke operasi UPDATE (Upsert)
          vQuery.Close;
          vQuery.SQL.Clear;
          vQuery.SQL.Add('UPDATE penyakit SET nm_penyakit = :nama, ciri_ciri = :ciri, keterangan = :ket, ');
          vQuery.SQL.Add('                    kd_ktg = :ktg, status = :status, tampil = :tampil ');
          vQuery.SQL.Add('WHERE kd_penyakit = :kode');
          vQuery.ParamByName('kode').AsString := vKdPenyakit;
          vQuery.ParamByName('nama').AsString := vNmPenyakit;
          vQuery.ParamByName('ciri').AsString := vCiriCiri;
          vQuery.ParamByName('ket').AsString := vKeterangan;
          vQuery.ParamByName('ktg').AsString := vKdKtg;
          vQuery.ParamByName('status').AsString := vStatus;
          vQuery.ParamByName('tampil').AsString := vTampil;
          vQuery.ExecSQL;

          AResponse.Send('{"status": "success", "message": "Kode penyakit sudah ada, data otomatis diperbarui (Updated)"}', 'application/json', 200);
          Exit;
        end;
        vQuery.Close;

        // JALUR INSERT BARU
        vQuery.SQL.Clear;
        vQuery.SQL.Add('INSERT INTO penyakit (kd_penyakit, nm_penyakit, ciri_ciri, keterangan, kd_ktg, status, tampil) ');
        vQuery.SQL.Add('VALUES (:kode, :nama, :ciri, :ket, :ktg, :status, :tampil)');
        vQuery.ParamByName('kode').AsString := vKdPenyakit;
        vQuery.ParamByName('nama').AsString := vNmPenyakit;
        vQuery.ParamByName('ciri').AsString := vCiriCiri;
        vQuery.ParamByName('ket').AsString := vKeterangan;
        vQuery.ParamByName('ktg').AsString := vKdKtg;
        vQuery.ParamByName('status').AsString := vStatus;
        vQuery.ParamByName('tampil').AsString := vTampil;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Master penyakit baru berhasil ditambahkan"}', 'application/json', 201);
      except
        on E: Exception do
        begin
          if Pos('foreign key constraint fails', LowerCase(E.Message)) > 0 then
            AResponse.Send('{"status": "error", "message": "Gagal: Kode Kategori (kd_ktg) tidak terdaftar di master kategori_penyakit!"}', 'application/json', 400)
          else
            AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
        end;
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 3. OPERATION: PUT (UPDATE DATA MASTER PENYAKIT)
    // =================================================================
    else if ARequest.Method = 'PUT' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vKdPenyakit  := Trim(vJSONReq.Get('kd_penyakit', ''));
        vNmPenyakit  := Trim(vJSONReq.Get('nm_penyakit', ''));
        vCiriCiri    := Trim(vJSONReq.Get('ciri_ciri', ''));
        vKeterangan  := Trim(vJSONReq.Get('keterangan', ''));
        vKdKtg       := Trim(vJSONReq.Get('kd_ktg', ''));
        vStatus      := Trim(vJSONReq.Get('status_menular', 'Tidak Menular'));
        vTampil      := Trim(vJSONReq.Get('tampil', 'YA'));

        if vKdPenyakit = '' then raise Exception.Create('Parameter kd_penyakit harus dikirim untuk update!');

        vQuery.SQL.Clear;
        vQuery.SQL.Add('UPDATE penyakit SET nm_penyakit = :nama, ciri_ciri = :ciri, keterangan = :ket, ');
        vQuery.SQL.Add('                    kd_ktg = :ktg, status = :status, tampil = :tampil ');
        vQuery.SQL.Add('WHERE kd_penyakit = :kode');
        vQuery.ParamByName('kode').AsString := vKdPenyakit;
        vQuery.ParamByName('nama').AsString := vNmPenyakit;
        vQuery.ParamByName('ciri').AsString := vCiriCiri;
        vQuery.ParamByName('ket').AsString := vKeterangan;
        vQuery.ParamByName('ktg').AsString := vKdKtg;
        vQuery.ParamByName('status').AsString := vStatus;
        vQuery.ParamByName('tampil').AsString := vTampil;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Master penyakit berhasil diperbarui"}', 'application/json', 200);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 4. OPERATION: DELETE (HAPUS DATA MASTER PENYAKIT)
    // =================================================================
    else if ARequest.Method = 'DELETE' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vKdPenyakit := Trim(vJSONReq.Get('kd_penyakit', ''));

        if vKdPenyakit = '' then raise Exception.Create('Hapus data master membutuhkan kd_penyakit!');

        vQuery.SQL.Clear;
        vQuery.SQL.Add('DELETE FROM penyakit WHERE kd_penyakit = :kode');
        vQuery.ParamByName('kode').AsString := vKdPenyakit;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Master penyakit berhasil dihapus"}', 'application/json', 200);
      except
        on E: Exception do
        begin
          if Pos('foreign key constraint fails', LowerCase(E.Message)) > 0 then
            AResponse.Send('{"status": "error", "message": "Gagal: Penyakit ini tidak bisa dihapus karena kodenya sedang digunakan pada data tabel diagnosa_pasien!"}', 'application/json', 400)
          else
            AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
        end;
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end;

  finally
    vQuery.Free;
  end;
end;

end.
