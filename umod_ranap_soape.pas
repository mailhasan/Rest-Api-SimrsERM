unit umod_ranap_soape;

{$MODE DELPHI} // Menggunakan mode Delphi agar selaras dengan pola uhandlerapi

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, fpjson, jsonparser;

type
  { TRouteRanapSOAPECRUD }
  TRouteRanapSOAPECRUD = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TRouteRanapSOAPECRUD }
uses uhandlerapi;

procedure TRouteRanapSOAPECRUD.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET, rmPOST, rmPUT, rmDELETE];
  Pattern := 'api/v1/ranap/soape'; // Mengikuti standard namespace api/v1/ Anda
end;

procedure TRouteRanapSOAPECRUD.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vNoRawat, vNoRkmMedis, vTglAwal, vTglAkhir, vPayloadStr: string;
  vTglPerawatan, vJamRawat, vSuhu, vTensi, vNadi, vRespirasi, vBerat, vSpo2, vGcs, vKesadaran: string;
  vKeluhan, vPemeriksaan, vPenilaian, vRtl, vInstruksi, vEvaluasi, vAlergi, vNip: string;
  vFilterSQL: TStringList;
  vQuery: TZQuery;
  vJSONData: TJSONData;
  vJSONReq: TJSONObject;
  vJSONArray: TJSONArray;
begin
  // Proteksi Keamanan: Validasi Token via middleware satpam global uhandlerapi
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  vQuery := TZQuery.Create(nil);
  vQuery.Connection := uhandlerapi.gZConn;
  vFilterSQL := TStringList.Create;

  try
    // =================================================================
    // 1. OPERATION: GET (READ / SEARCH MULTI-PARAMETER DINAMIS)
    // =================================================================
    if ARequest.Method = 'GET' then
    begin
      // Mengikuti acuan sukses Anda: menggunakan ARequest.Params.Values
      vNoRawat    := ARequest.Params.Values['no_rawat'];
      vNoRkmMedis := ARequest.Params.Values['no_rkm_medis'];
      vTglAwal    := ARequest.Params.Values['tgl_awal'];
      vTglAkhir   := ARequest.Params.Values['tgl_akhir'];

      vJSONArray := TJSONArray.Create;
      try
        vFilterSQL.Clear;
        vFilterSQL.Add('SELECT pr.no_rawat, pr.tgl_perawatan, pr.jam_rawat,');
        vFilterSQL.Add('       p.nm_pasien, p.no_rkm_medis,');
        vFilterSQL.Add('       pr.suhu_tubuh, pr.tensi, pr.nadi, pr.respirasi, pr.berat, pr.alergi,');
        vFilterSQL.Add('       pr.SpO2, pr.GCS, pr.kesadaran,');
        vFilterSQL.Add('       pr.keluhan, pr.pemeriksaan, pr.penilaian, pr.rtl AS plan, pr.instruksi, pr.evaluasi,');
        vFilterSQL.Add('       pr.nip, pg.nama AS nama_petugas, pg.`jbtn`');
        vFilterSQL.Add('FROM pemeriksaan_ranap pr');
        vFilterSQL.Add('JOIN reg_periksa rp ON pr.no_rawat = rp.no_rawat');
        vFilterSQL.Add('JOIN pasien p ON rp.no_rkm_medis = p.no_rkm_medis');
        vFilterSQL.Add('LEFT JOIN pegawai pg ON pr.nip = pg.nik');
        vFilterSQL.Add('WHERE 1=1');

        // Logika Klausa WHERE Dinamis Mandiri
        if vNoRawat <> '' then 
          vFilterSQL.Add('AND pr.no_rawat = :no_rawat');
          
        if vNoRkmMedis <> '' then 
          vFilterSQL.Add('AND p.no_rkm_medis = :no_rkm_medis');
          
        if (vTglAwal <> '') and (vTglAkhir <> '') then 
          vFilterSQL.Add('AND pr.tgl_perawatan BETWEEN :tgl_awal AND :tgl_akhir');

        vFilterSQL.Add('ORDER BY pr.tgl_perawatan DESC, pr.jam_rawat DESC');
        vQuery.SQL.Text := vFilterSQL.Text;

        // Binding Parameter Sesuai SQL Terbentuk
        if vNoRawat <> '' then 
          vQuery.ParamByName('no_rawat').AsString := vNoRawat;
          
        if vNoRkmMedis <> '' then 
          vQuery.ParamByName('no_rkm_medis').AsString := vNoRkmMedis;
          
        if (vTglAwal <> '') and (vTglAkhir <> '') then
        begin
          vQuery.ParamByName('tgl_awal').AsString := vTglAwal;
          vQuery.ParamByName('tgl_akhir').AsString := vTglAkhir;
        end;

        vQuery.Open;

        while not vQuery.EOF do
        begin
          vJSONReq := TJSONObject.Create;
          vJSONReq.Add('no_rawat', Trim(vQuery.FieldByName('no_rawat').AsString));
          vJSONReq.Add('tgl_perawatan', vQuery.FieldByName('tgl_perawatan').AsString);
          vJSONReq.Add('jam_rawat', vQuery.FieldByName('jam_rawat').AsString);
          vJSONReq.Add('nm_pasien', Trim(vQuery.FieldByName('nm_pasien').AsString));
          vJSONReq.Add('no_rkm_medis', Trim(vQuery.FieldByName('no_rkm_medis').AsString));
          vJSONReq.Add('suhu_tubuh', Trim(vQuery.FieldByName('suhu_tubuh').AsString));
          vJSONReq.Add('tensi', Trim(vQuery.FieldByName('tensi').AsString));
          vJSONReq.Add('nadi', Trim(vQuery.FieldByName('nadi').AsString));
          vJSONReq.Add('respirasi', Trim(vQuery.FieldByName('respirasi').AsString));
          vJSONReq.Add('berat', Trim(vQuery.FieldByName('berat').AsString));
          vJSONReq.Add('alergi', Trim(vQuery.FieldByName('alergi').AsString));
          vJSONReq.Add('spo2', Trim(vQuery.FieldByName('SpO2').AsString));
          vJSONReq.Add('gcs', Trim(vQuery.FieldByName('GCS').AsString));
          vJSONReq.Add('kesadaran', Trim(vQuery.FieldByName('kesadaran').AsString));
          vJSONReq.Add('keluhan', Trim(vQuery.FieldByName('keluhan').AsString));
          vJSONReq.Add('pemeriksaan', Trim(vQuery.FieldByName('pemeriksaan').AsString));
          vJSONReq.Add('penilaian', Trim(vQuery.FieldByName('penilaian').AsString));
          vJSONReq.Add('plan', Trim(vQuery.FieldByName('plan').AsString));
          vJSONReq.Add('instruksi', Trim(vQuery.FieldByName('instruksi').AsString));
          vJSONReq.Add('evaluasi', Trim(vQuery.FieldByName('evaluasi').AsString));
          vJSONReq.Add('nip', Trim(vQuery.FieldByName('nip').AsString));
          vJSONReq.Add('nama_petugas', Trim(vQuery.FieldByName('nama_petugas').AsString));
          vJSONReq.Add('jabatan', Trim(vQuery.FieldByName('jbtn').AsString));

          vJSONArray.Add(vJSONReq);
          vQuery.Next;
        end;

        AResponse.Send(vJSONArray.AsJSON, 'application/json; charset=utf-8', 200);
      finally
        vJSONArray.Free;
      end;
    end

    // =================================================================
    // 2. OPERATION: POST (CREATE / INSERT DATA PEMERIKSAAN)
    // =================================================================
    else if ARequest.Method = 'POST' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat      := Trim(vJSONReq.Get('no_rawat', ''));
        vTglPerawatan := Trim(vJSONReq.Get('tgl_perawatan', ''));
        vJamRawat     := Trim(vJSONReq.Get('jam_rawat', ''));

        if (vNoRawat = '') or (vTglPerawatan = '') or (vJamRawat = '') then
          raise Exception.Create('Parameter no_rawat, tgl_perawatan, dan jam_rawat wajib dikirim!');

        // Pre-check duplikasi PK Komposit
        vQuery.SQL.Clear;
        vQuery.SQL.Add('SELECT COUNT(*) AS jumlah FROM pemeriksaan_ranap ');
        vQuery.SQL.Add('WHERE no_rawat = :no_rawat AND tgl_perawatan = :tgl_perawatan AND jam_rawat = :jam_rawat');
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tgl_perawatan').AsString := vTglPerawatan;
        vQuery.ParamByName('jam_rawat').AsString := vJamRawat;
        vQuery.Open;

        if vQuery.FieldByName('jumlah').AsInteger > 0 then
        begin
          AResponse.Send('{"status": "error", "message": "Gagal: Data pemeriksaan sudah ada pada tanggal dan jam tersebut!"}', 'application/json', 409);
          Exit;
        end;
        vQuery.Close;

        vSuhu        := vJSONReq.Get('suhu_tubuh', '-');
        vTensi       := vJSONReq.Get('tensi', '-');
        vNadi        := vJSONReq.Get('nadi', '-');
        vRespirasi   := vJSONReq.Get('respirasi', '-');
        vBerat       := vJSONReq.Get('berat', '-');
        vSpo2        := vJSONReq.Get('spo2', '-');
        vGcs         := vJSONReq.Get('gcs', '-');
        vKesadaran   := vJSONReq.Get('kesadaran', 'Compos Mentis');
        vKeluhan     := vJSONReq.Get('keluhan', '');
        vPemeriksaan := vJSONReq.Get('pemeriksaan', '');
        vPenilaian   := vJSONReq.Get('penilaian', '');
        vRtl         := vJSONReq.Get('plan', '');
        vInstruksi   := vJSONReq.Get('instruksi', '');
        vEvaluasi    := vJSONReq.Get('evaluasi', '');
        vAlergi      := vJSONReq.Get('alergi', '-');
        vNip         := vJSONReq.Get('nip', '');

        vQuery.SQL.Clear;
        vQuery.SQL.Add('INSERT INTO pemeriksaan_ranap (no_rawat, tgl_perawatan, jam_rawat, suhu_tubuh, tensi,');
        vQuery.SQL.Add('nadi, respirasi, berat, SpO2, GCS, kesadaran, keluhan, pemeriksaan, penilaian, rtl, ');
        vQuery.SQL.Add('instruksi, evaluasi, alergi, nip)');
        vQuery.SQL.Add('VALUES (:no_rawat, :tgl_perawatan, :jam_rawat, :suhu, :tensi, :nadi, :respirasi, :berat, ');
        vQuery.SQL.Add(':spo2, :gcs, :kesadaran, :keluhan, :pemeriksaan, :penilaian, :rtl, :instruksi, :evaluasi, :alergi, :nip)');
        
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tgl_perawatan').AsString := vTglPerawatan;
        vQuery.ParamByName('jam_rawat').AsString := vJamRawat;
        vQuery.ParamByName('suhu').AsString := vSuhu;
        vQuery.ParamByName('tensi').AsString := vTensi;
        vQuery.ParamByName('nadi').AsString := vNadi;
        vQuery.ParamByName('respirasi').AsString := vRespirasi;
        vQuery.ParamByName('berat').AsString := vBerat;
        vQuery.ParamByName('spo2').AsString := vSpo2;
        vQuery.ParamByName('gcs').AsString := vGcs;
        vQuery.ParamByName('kesadaran').AsString := vKesadaran;
        vQuery.ParamByName('keluhan').AsString := vKeluhan;
        vQuery.ParamByName('pemeriksaan').AsString := vPemeriksaan;
        vQuery.ParamByName('penilaian').AsString := vPenilaian;
        vQuery.ParamByName('rtl').AsString := vRtl;
        vQuery.ParamByName('instruksi').AsString := vInstruksi;
        vQuery.ParamByName('evaluasi').AsString := vEvaluasi;
        vQuery.ParamByName('alergi').AsString := vAlergi;
        vQuery.ParamByName('nip').AsString := vNip;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data pemeriksaan SOAPE berhasil disimpan"}', 'application/json', 201);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 3. OPERATION: PUT (UPDATE DATA PEMERIKSAAN)
    // =================================================================
    else if ARequest.Method = 'PUT' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat      := Trim(vJSONReq.Get('no_rawat', ''));
        vTglPerawatan := Trim(vJSONReq.Get('tgl_perawatan', ''));
        vJamRawat     := Trim(vJSONReq.Get('jam_rawat', ''));

        if (vNoRawat = '') or (vTglPerawatan = '') or (vJamRawat = '') then
          raise Exception.Create('Identifikasi kunci (no_rawat, tgl_perawatan, jam_rawat) wajib disertakan!');

        vSuhu        := vJSONReq.Get('suhu_tubuh', '-');
        vTensi       := vJSONReq.Get('tensi', '-');
        vNadi        := vJSONReq.Get('nadi', '-');
        vRespirasi   := vJSONReq.Get('respirasi', '-');
        vBerat       := vJSONReq.Get('berat', '-');
        vSpo2        := vJSONReq.Get('spo2', '-');
        vGcs         := vJSONReq.Get('gcs', '-');
        vKesadaran   := vJSONReq.Get('kesadaran', 'Compos Mentis');
        vKeluhan     := vJSONReq.Get('keluhan', '');
        vPemeriksaan := vJSONReq.Get('pemeriksaan', '');
        vPenilaian   := vJSONReq.Get('penilaian', '');
        vRtl         := vJSONReq.Get('plan', '');
        vInstruksi   := vJSONReq.Get('instruksi', '');
        vEvaluasi    := vJSONReq.Get('evaluasi', '');
        vAlergi      := vJSONReq.Get('alergi', '-');
        vNip         := vJSONReq.Get('nip', '');

        vQuery.SQL.Clear;
        vQuery.SQL.Add('UPDATE pemeriksaan_ranap SET suhu_tubuh = :suhu, tensi = :tensi, nadi = :nadi, respirasi = :respirasi,');
        vQuery.SQL.Add('berat = :berat, SpO2 = :spo2, GCS = :gcs, kesadaran = :kesadaran, keluhan = :keluhan, pemeriksaan = :pemeriksaan,');
        vQuery.SQL.Add('penilaian = :penilaian, rtl = :rtl, instruksi = :instruksi, evaluasi = :evaluasi, alergi = :alergi, nip = :nip');
        vQuery.SQL.Add('WHERE no_rawat = :no_rawat AND tgl_perawatan = :tgl_perawatan AND jam_rawat = :jam_rawat');

        vQuery.ParamByName('suhu').AsString := vSuhu;
        vQuery.ParamByName('tensi').AsString := vTensi;
        vQuery.ParamByName('nadi').AsString := vNadi;
        vQuery.ParamByName('respirasi').AsString := vRespirasi;
        vQuery.ParamByName('berat').AsString := vBerat;
        vQuery.ParamByName('spo2').AsString := vSpo2;
        vQuery.ParamByName('gcs').AsString := vGcs;
        vQuery.ParamByName('kesadaran').AsString := vKesadaran;
        vQuery.ParamByName('keluhan').AsString := vKeluhan;
        vQuery.ParamByName('pemeriksaan').AsString := vPemeriksaan;
        vQuery.ParamByName('penilaian').AsString := vPenilaian;
        vQuery.ParamByName('rtl').AsString := vRtl;
        vQuery.ParamByName('instruksi').AsString := vInstruksi;
        vQuery.ParamByName('evaluasi').AsString := vEvaluasi;
        vQuery.ParamByName('alergi').AsString := vAlergi;
        vQuery.ParamByName('nip').AsString := vNip;
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tgl_perawatan').AsString := vTglPerawatan;
        vQuery.ParamByName('jam_rawat').AsString := vJamRawat;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data pemeriksaan SOAPE berhasil diperbarui"}', 'application/json', 200);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 4. OPERATION: DELETE (DELETE DATA)
    // =================================================================
    else if ARequest.Method = 'DELETE' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat      := Trim(vJSONReq.Get('no_rawat', ''));
        vTglPerawatan := Trim(vJSONReq.Get('tgl_perawatan', ''));
        vJamRawat     := Trim(vJSONReq.Get('jam_rawat', ''));

        if (vNoRawat = '') or (vTglPerawatan = '') or (vJamRawat = '') then
          raise Exception.Create('Penghapusan data SOAPE membutuhkan no_rawat, tgl_perawatan, dan jam_rawat!');

        vQuery.SQL.Clear;
        vQuery.SQL.Add('DELETE FROM pemeriksaan_ranap WHERE no_rawat = :no_rawat AND tgl_perawatan = :tgl_perawatan AND jam_rawat = :jam_rawat');
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tgl_perawatan').AsString := vTglPerawatan;
        vQuery.ParamByName('jam_rawat').AsString := vJamRawat;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data pemeriksaan SOAPE berhasil dihapus"}', 'application/json', 200);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end;

  finally
    vFilterSQL.Free;
    vQuery.Free;
  end;
end;

end.
