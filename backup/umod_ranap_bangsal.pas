unit umod_ranap_bangsal;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, fpjson, jsonparser;

type
  { TRouteRanapBangsalCRUD }
  TRouteRanapBangsalCRUD = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TRouteRanapBangsalCRUD }
uses uhandlerapi, uhelper;

procedure TRouteRanapBangsalCRUD.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET, rmPOST];
  Pattern := 'api/v1/ranap/bangsal'; // Endpoint Terpadu Manajemen Depo/Bangsal
end;

procedure TRouteRanapBangsalCRUD.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vKdBangsal, vNmBangsal, vStatus, vKeyword, vPayloadStr: string;
  vQuery, vQuerySub: TZQuery;
  vSQL: TStringList;
  vJSONData: TJSONData;
  vJSONReq, vJSONItem, vObjBangsal: TJSONObject;
  vRootArray: TJSONArray;
begin
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  vQuery    := TZQuery.Create(nil); vQuery.Connection    := uhandlerapi.gZConn;
  vQuerySub := TZQuery.Create(nil); vQuerySub.Connection := uhandlerapi.gZConn;
  vSQL      := TStringList.Create;

  try
    // =================================================================
    // 1. OPERATION: GET (READ LIST / SEARCH / DETAIL BANGSAL)
    // =================================================================
    if ARequest.Method = 'GET' then
    begin
      vKdBangsal := Trim(ARequest.Params.Values['kd_bangsal']);
      vKeyword   := Trim(ARequest.Params.Values['keyword']);
      vStatus    := Trim(ARequest.Params.Values['status']); // Filter status '1' (aktif) atau '0' (nonaktif)

      vSQL.Clear;
      vSQL.Add('SELECT kd_bangsal, nm_bangsal, status FROM bangsal WHERE 1=1');

      // Jalur Filter Spesifik ID Primary Key
      if vKdBangsal <> '' then
        vSQL.Add('  AND kd_bangsal = :kd_bangsal')
      else
      begin
        // Jalur Filter Keyword Pencarian
        if vKeyword <> '' then
          vSQL.Add('  AND (kd_bangsal LIKE :keyword OR nm_bangsal LIKE :keyword)');
        // Jalur Filter Status Aktif/Tidak
        if vStatus <> '' then
          vSQL.Add('  AND status = :status');
      end;

      vSQL.Add('ORDER BY nm_bangsal ASC');

      vQuery.SQL.Text := vSQL.Text;

      if vKdBangsal <> '' then
        vQuery.ParamByName('kd_bangsal').AsString := vKdBangsal;
      if (vKdBangsal = '') and (vKeyword <> '') then
        vQuery.ParamByName('keyword').AsString := '%' + vKeyword + '%';
      if (vKdBangsal = '') and (vStatus <> '') then
        vQuery.ParamByName('status').AsString := vStatus;

      vQuery.Open;

      // Jika meminta detail satu kode bangsal tertentu
      if (vKdBangsal <> '') then
      begin
        if vQuery.EOF then
        begin
          AResponse.Send('{"status": "error", "message": "Data depo/bangsal tidak ditemukan!"}', 'application/json', 404);
          Exit;
        end;

        vJSONItem := TJSONObject.Create;
        try
          vJSONItem.Add('kd_bangsal', Trim(vQuery.FieldByName('kd_bangsal').AsString));
          vJSONItem.Add('nm_bangsal', Trim(vQuery.FieldByName('nm_bangsal').AsString));
          vJSONItem.Add('status', Trim(vQuery.FieldByName('status').AsString));
          AResponse.Send(vJSONItem.AsJSON, 'application/json; charset=utf-8', 200);
        finally
          vJSONItem.Free;
        end;
      end
      else
      begin
        // Jalur output Array List Data untuk dropdown pencarian resep obat
        vRootArray := TJSONArray.Create;
        try
          while not vQuery.EOF do
          begin
            vObjBangsal := TJSONObject.Create;
            vObjBangsal.Add('kd_bangsal', Trim(vQuery.FieldByName('kd_bangsal').AsString));
            vObjBangsal.Add('nm_bangsal', Trim(vQuery.FieldByName('nm_bangsal').AsString));
            vObjBangsal.Add('status', Trim(vQuery.FieldByName('status').AsString));
            vRootArray.Add(vObjBangsal);
            vQuery.Next;
          end;
          AResponse.Send(vRootArray.AsJSON, 'application/json; charset=utf-8', 200);
        finally
          vRootArray.Free;
        end;
      end;
    end

    // =================================================================
    // 2. OPERATION: POST (SAVE BARU / UPSERT PATTERN)
    // =================================================================
    else if ARequest.Method = 'POST' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData   := GetJSON(vPayloadStr);
        vJSONReq    := TJSONObject(vJSONData);

        vKdBangsal  := Uppercase(Trim(vJSONReq.Get('kd_bangsal', '')));
        vNmBangsal  := Trim(vJSONReq.Get('nm_bangsal', ''));
        vStatus     := Trim(vJSONReq.Get('status', '1')); // Default aktif jika tidak diisi

        if (vKdBangsal = '') or (vNmBangsal = '') then
        begin
          AResponse.Send('{"status": "error", "message": "kd_bangsal dan nm_bangsal wajib diisi!"}', 'application/json', 400);
          Exit;
        end;

        // Validasi panjang kode bangsal sesuai batasan CHAR(5) DDL Anda
        if Length(vKdBangsal) > 5 then
        begin
          AResponse.Send('{"status": "error", "message": "kd_bangsal tidak boleh lebih dari 5 karakter!"}', 'application/json', 400);
          Exit;
        end;

        uhandlerapi.gZConn.StartTransaction;
        try
          // Deteksi Eksistensi Data (Upsert Pattern)
          vQuery.SQL.Clear;
          vQuery.SQL.Add('SELECT COUNT(*) AS jumlah FROM bangsal WHERE kd_bangsal = :kd_bangsal');
          vQuery.ParamByName('kd_bangsal').AsString := vKdBangsal;
          vQuery.Open;

          if vQuery.FieldByName('jumlah').AsInteger > 0 then
          begin
            // Mode Update Data
            vQuerySub.SQL.Clear;
            vQuerySub.SQL.Add('UPDATE bangsal SET nm_bangsal = :nm_bangsal, status = :status WHERE kd_bangsal = :kd_bangsal');
            vQuerySub.ParamByName('kd_bangsal').AsString := vKdBangsal;
            vQuerySub.ParamByName('nm_bangsal').AsString := vNmBangsal;
            vQuerySub.ParamByName('status').AsString     := vStatus;
            vQuerySub.ExecSQL;

            uhandlerapi.gZConn.Commit;
            AResponse.Send('{"status": "success", "message": "Data bangsal berhasil diperbarui"}', 'application/json', 200);
          end
          else
          begin
            // Mode Insert Data Baru
            vQuerySub.SQL.Clear;
            vQuerySub.SQL.Add('INSERT INTO bangsal (kd_bangsal, nm_bangsal, status) VALUES (:kd_bangsal, :nm_bangsal, :status)');
            vQuerySub.ParamByName('kd_bangsal').AsString := vKdBangsal;
            vQuerySub.ParamByName('nm_bangsal').AsString := vNmBangsal;
            vQuerySub.ParamByName('status').AsString     := vStatus;
            vQuerySub.ExecSQL;

            uhandlerapi.gZConn.Commit;
            AResponse.Send('{"status": "success", "message": "Data bangsal baru berhasil disimpan"}', 'application/json', 201);
          end;

        except
          on E: Exception do
          begin
            if uhandlerapi.gZConn.InTransaction then uhandlerapi.gZConn.Rollback;
            raise;
          end;
        end;

      except
        on E: Exception do
        begin
          AResponse.SendFmt('{"status": "error", "message": "Gagal memproses data bangsal: %s"}', [E.Message], 'application/json', 500);
        end;
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end;

  finally
    vSQL.Free;
    vQuery.Free;
    vQuerySub.Free;
  end;
end;

{ =====================================================================
  ℹ️ DESKRIPSI FUNGSIONALITAS FITUR & ALUR BISNIS BANGSAL
  =====================================================================
  1. IMPLEMENTASI READ/SEARCH LIST (GET):
     - Mampu melakukan penarikan daftar seluruh depo/bangsal dengan pengurutan alfabetis.
     - Mendukung query parameter 'keyword' untuk mencari berdasarkan pecahan karakter nama atau kode.
     - Menyediakan filter 'status' dinamis untuk memisahkan depo aktif yang digunakan dalam e-resep.

  2. STRATEGI UPSERT TRANSACTIONAL (POST):
     - Mengeliminasi kebutuhan method PUT terpisah dengan menerapkan pengecekan COUNT internal row.
     - Kode yang masuk akan di-upper case otomatis demi standarisasi kode relasi foreign key database.
     - Dilengkapi proteksi batasan data CHAR(5) untuk mencegah crash MySQL Data Too Long.
  ===================================================================== }

end.
