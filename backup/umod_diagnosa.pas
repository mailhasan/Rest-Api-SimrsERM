unit umod_diagnosa;

{$MODE DELPHI} // Menggunakan mode Delphi agar selaras dengan uhandlerapi

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse,BrookUtility, fpjson, jsonparser;

type
  { TRouteDiagnosaCRUD }
  TRouteDiagnosaCRUD = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TRouteDiagnosaCRUD }

uses uhandlerapi;

procedure TRouteDiagnosaCRUD.AfterConstruction;
begin
  inherited AfterConstruction; // Wajib panggil inherited di struktur router class-based
  // Mengaktifkan semua metode HTTP untuk operasional CRUD terpadu
  Methods := [rmGET, rmPOST, rmPUT, rmDELETE];
  Pattern := 'api/v1/diagnosa';
end;

procedure TRouteDiagnosaCRUD.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vNoRawat, vKdPenyakit, vStatusRawat, vStatusPenyakit, vKeyword, vPayloadStr: string;
  vPrioritas: Integer;
  vJSONData: TJSONData;
  vJSONReq, vJSONRes: TJSONObject;
  vJSONArray: TJSONArray;
  vQuery: TZQuery;
begin
  // Proteksi Keamanan: Validasi Token via middleware satpam global uhandlerapi
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  vQuery := TZQuery.Create(nil);
  // Mengambil instance global gZConn melalui variabel terikat dari unit uhandlerapi
  vQuery.Connection := uhandlerapi.gZConn;

  vJSONRes := TJSONObject.Create;

  try
    // =================================================================
    // 1. OPERATION: GET (READ / SEARCH DATA MASTER & DATA TERINPUT)
    // =================================================================
    if ARequest.Method = 'GET' then
    begin
      vNoRawat := ARequest.Params.Values['no_rawat'];
      vKeyword := ARequest.Params.Values['keyword'];
      vJSONArray := TJSONArray.Create;

      try
        vQuery.SQL.Clear;

        // JALUR A: Jika dilempar param ?no_rawat=..., tampilkan diagnosa terinput pasien
        if vNoRawat <> '' then
        begin
          vQuery.SQL.Add('SELECT dp.no_rawat, dp.kd_penyakit, p.nm_penyakit, dp.status, dp.prioritas, dp.status_penyakit ');
          vQuery.SQL.Add('FROM diagnosa_pasien dp ');
          vQuery.SQL.Add('LEFT JOIN penyakit p ON dp.kd_penyakit = p.kd_penyakit ');
          vQuery.SQL.Add('WHERE TRIM(dp.no_rawat) = :no_rawat ');
          vQuery.SQL.Add('ORDER BY dp.prioritas ASC');
          vQuery.ParamByName('no_rawat').AsString := vNoRawat;
          vQuery.Open;

          while not vQuery.EOF do
          begin
            vJSONReq := TJSONObject.Create;
            vJSONReq.Add('no_rawat', Trim(vQuery.FieldByName('no_rawat').AsString));
            vJSONReq.Add('kd_penyakit', Trim(vQuery.FieldByName('kd_penyakit').AsString));
            vJSONReq.Add('nm_penyakit', Trim(vQuery.FieldByName('nm_penyakit').AsString));
            vJSONReq.Add('status_rawat', vQuery.FieldByName('status').AsString);
            vJSONReq.Add('prioritas', vQuery.FieldByName('prioritas').AsInteger);
            vJSONReq.Add('status_penyakit', vQuery.FieldByName('status_penyakit').AsString);
            vJSONArray.Add(vJSONReq);
            vQuery.Next;
          end;
        end
        // JALUR B: Jika tidak ada no_rawat, maka difungsikan sebagai pencarian Master Penyakit ICD-10
        else
        begin
          vQuery.SQL.Add('SELECT kd_penyakit, nm_penyakit, ciri_ciri, status FROM penyakit WHERE tampil = "YA" ');
          if vKeyword <> '' then
            vQuery.SQL.Add('AND (kd_penyakit LIKE :keyword OR nm_penyakit LIKE :keyword) ');
          vQuery.SQL.Add('ORDER BY kd_penyakit ASC LIMIT 50');

          if vKeyword <> '' then
            vQuery.ParamByName('keyword').AsString := '%' + vKeyword + '%';
          vQuery.Open;

          while not vQuery.EOF do
          begin
            vJSONReq := TJSONObject.Create;
            vJSONReq.Add('kd_penyakit', Trim(vQuery.FieldByName('kd_penyakit').AsString));
            vJSONReq.Add('nm_penyakit', Trim(vQuery.FieldByName('nm_penyakit').AsString));
            vJSONReq.Add('ciri_ciri', Trim(vQuery.FieldByName('ciri_ciri').AsString));
            vJSONReq.Add('klasifikasi', vQuery.FieldByName('status').AsString);
            vJSONArray.Add(vJSONReq);
            vQuery.Next;
          end;
        end;

        AResponse.Send(vJSONArray.AsJSON, 'application/json; charset=utf-8', 200);
      finally
        vJSONArray.Free;
      end;
    end

    // =================================================================
    // 2. OPERATION: POST (CREATE / INSERT DIAGNOSA BARU)
    // =================================================================
    els if ARequest.Method = 'POST' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat        := Trim(vJSONReq.Get('no_rawat', ''));
        vKdPenyakit     := Trim(vJSONReq.Get('kd_penyakit', ''));
        vStatusRawat    := Trim(vJSONReq.Get('status_rawat', '')); // Ralan / Ranap
        vPrioritas      := vJSONReq.Get('prioritas', 2);
        vStatusPenyakit := Trim(vJSONReq.Get('status_penyakit', 'Baru')); // Baru / Lama

        if (vNoRawat = '') or (vKdPenyakit = '') or (vStatusRawat = '') then
          raise Exception.Create('Parameter no_rawat, kd_penyakit, dan status_rawat wajib dikirim!');

        // ----------------=============================================
        // VALIDASI INPUT ANTI-DUPLIKASI (PRE-CHECK SELECT)
        // ----------------=============================================
        vQuery.SQL.Clear;
        vQuery.SQL.Add('SELECT COUNT(*) AS jumlah FROM diagnosa_pasien ');
        vQuery.SQL.Add('WHERE no_rawat = :no_rawat AND kd_penyakit = :kd_penyakit AND status = :status');
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('kd_penyakit').AsString := vKdPenyakit;
        vQuery.ParamByName('status').AsString := vStatusRawat;
        vQuery.Open;

        if vQuery.FieldByName('jumlah').AsInteger > 0 then
        begin
          // JALUR A: Jika sudah ada, alihkan secara otomatis menjadi UPDATE (Upsert)
          vQuery.Close;
          vQuery.SQL.Clear;
          vQuery.SQL.Add('UPDATE diagnosa_pasien SET prioritas = :prioritas, status_penyakit = :status_penyakit ');
          vQuery.SQL.Add('WHERE no_rawat = :no_rawat AND kd_penyakit = :kd_penyakit AND status = :status');
          vQuery.ParamByName('no_rawat').AsString := vNoRawat;
          vQuery.ParamByName('kd_penyakit').AsString := vKdPenyakit;
          vQuery.ParamByName('status').AsString := vStatusRawat;
          vQuery.ParamByName('prioritas').AsInteger := vPrioritas;
          vQuery.ParamByName('status_penyakit').AsString := vStatusPenyakit;
          vQuery.ExecSQL;

          AResponse.Send('{"status": "success", "message": "Data sudah ada, otomatis diperbarui (Updated)"}', 'application/json', 200);
          Exit;
        end;
        vQuery.Close;
        // ----------------=============================================

        // JALUR B: Lolos validasi, data benar-benar baru, jalankan INSERT
        vQuery.SQL.Text := 'INSERT INTO diagnosa_pasien (no_rawat, kd_penyakit, status, prioritas, status_penyakit) ' +
                           'VALUES (:no_rawat, :kd_penyakit, :status, :prioritas, :status_penyakit)';
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('kd_penyakit').AsString := vKdPenyakit;
        vQuery.ParamByName('status').AsString := vStatusRawat;
        vQuery.ParamByName('prioritas').AsInteger := vPrioritas;
        vQuery.ParamByName('status_penyakit').AsString := vStatusPenyakit;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data diagnosa berhasil disimpan"}', 'application/json', 201);
      except
        on E: Exception do
        begin
          // Cadangan penangkap error biner via string matching MySQL Driver
          if (Pos('foreign key constraint fails', LowerCase(E.Message)) > 0) then
            AResponse.Send('{"status": "error", "message": "Gagal: Nomor Rawat atau Kode Penyakit tidak valid / tidak terdaftar di database!"}', 'application/json', 400)
          else if (Pos('duplicate entry', LowerCase(E.Message)) > 0) or (Pos('key_violation', LowerCase(E.Message)) > 0) then
            AResponse.Send('{"status": "error", "message": "Gagal: Diagnosa penyakit tersebut sudah terinput pada kunjungan ini!"}', 'application/json', 409)
          else
            AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
        end;
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 3. OPERATION: PUT (UPDATE DATA DIAGNOSA)
    // =================================================================
    else if ARequest.Method = 'PUT' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat        := Trim(vJSONReq.Get('no_rawat', ''));
        vKdPenyakit     := Trim(vJSONReq.Get('kd_penyakit', ''));
        vStatusRawat    := Trim(vJSONReq.Get('status_rawat', '')); // Key komposit primer (status)
        vPrioritas      := vJSONReq.Get('prioritas', 2);
        vStatusPenyakit := Trim(vJSONReq.Get('status_penyakit', 'Baru'));

        vQuery.SQL.Text := 'UPDATE diagnosa_pasien SET prioritas = :prioritas, status_penyakit = :status_penyakit ' +
                           'WHERE no_rawat = :no_rawat AND kd_penyakit = :kd_penyakit AND status = :status';
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('kd_penyakit').AsString := vKdPenyakit;
        vQuery.ParamByName('status').AsString := vStatusRawat;
        vQuery.ParamByName('prioritas').AsInteger := vPrioritas;
        vQuery.ParamByName('status_penyakit').AsString := vStatusPenyakit;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data diagnosa berhasil diperbarui"}', 'application/json', 200);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 4. OPERATION: DELETE (HAPUS DATA VIA BODY JSON RAW)
    // =================================================================
    else if ARequest.Method = 'DELETE' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat     := Trim(vJSONReq.Get('no_rawat', ''));
        vKdPenyakit  := Trim(vJSONReq.Get('kd_penyakit', ''));
        vStatusRawat := Trim(vJSONReq.Get('status_rawat', ''));

        if (vNoRawat = '') or (vKdPenyakit = '') or (vStatusRawat = '') then
          raise Exception.Create('Hapus data membutuhkan no_rawat, kd_penyakit, dan status_rawat!');

        vQuery.SQL.Text := 'DELETE FROM diagnosa_pasien WHERE no_rawat = :no_rawat AND kd_penyakit = :kd_penyakit AND status = :status';
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('kd_penyakit').AsString := vKdPenyakit;
        vQuery.ParamByName('status').AsString := vStatusRawat;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data diagnosa berhasil dihapus"}', 'application/json', 200);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end;

  finally
    vJSONRes.Free;
    vQuery.Free;
  end;
end;

end.
