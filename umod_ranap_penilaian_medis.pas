unit umod_ranap_penilaian_medis;

{$MODE DELPHI} // Menggunakan mode Delphi agar selaras dengan pola uhandlerapi

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, fpjson, jsonparser;

type
  { TRouteRanapPenilaianMedisCRUD }
  TRouteRanapPenilaianMedisCRUD = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TRouteRanapPenilaianMedisCRUD }
uses uhandlerapi;

function PerbaikiFormatTanggal(AStringTanggal: string): string;
var
  vTgl, vBln, vThn, vJam: string;
begin
  Result := AStringTanggal; // Nilai default jika format sudah benar
  
  // Deteksi jika string menggunakan pemisah garis miring (DD/MM/YYYY...)
  if (Pos('/', AStringTanggal) = 3) and (Length(AStringTanggal) >= 10) then
  begin
    vTgl := Copy(AStringTanggal, 1, 2);
    vBln := Copy(AStringTanggal, 4, 2);
    vThn := Copy(AStringTanggal, 7, 4);
    vJam := Copy(AStringTanggal, 11, Length(AStringTanggal)); // Ambil sisa jam jika ada
    
    Result := vThn + '-' + vBln + '-' + vTgl + vJam;
  end;
end;

procedure TRouteRanapPenilaianMedisCRUD.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET, rmPOST, rmPUT, rmDELETE];
  Pattern := 'api/v1/ranap/penilaian-medis'; // Endpoint Terpadu
end;

procedure TRouteRanapPenilaianMedisCRUD.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vNoRawat, vNoRkmMedis, vTglAwal, vTglAkhir, vPayloadStr: string;
  vTanggal, vKdDokter, vAnamnesis, vHubungan, vKeluhanUtama, vRps, vRpk, vRpd, vRpo, vAlergi: string;
  vKeadaan, vGcs, vKesadaran, vTd, vNadi, vRr, vSuhu, vSpo, vBb, vTb: string;
  vKepala, vMata, vGigi, vTht, vThoraks, vJantung, vParu, vAbdomen, vEkstremitas, vGenital, vKulit: string;
  vKetFisik, vKetLokalis, vLab, vRad, vPenunjang, vDiagnosis, vTata, vEdukasi: string;
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
    // 1. OPERATION: GET (READ / SEARCH MULTI-PARAMETER)
    // =================================================================
    if ARequest.Method = 'GET' then
    begin
      vNoRawat    := ARequest.Params.Values['no_rawat'];
      vNoRkmMedis := ARequest.Params.Values['no_rkm_medis'];
      vTglAwal    := ARequest.Params.Values['tgl_awal'];
      vTglAkhir   := ARequest.Params.Values['tgl_akhir'];

      vJSONArray := TJSONArray.Create;
      try
        vFilterSQL.Clear;
        vFilterSQL.Add('SELECT reg_periksa.no_rawat, pasien.no_rkm_medis, pasien.nm_pasien,');
        vFilterSQL.Add('       IF(pasien.jk="L","Laki-Laki","Perempuan") AS jk, pasien.tgl_lahir,');
        vFilterSQL.Add('       penilaian_medis_ranap.tanggal, penilaian_medis_ranap.kd_dokter,');
        vFilterSQL.Add('       penilaian_medis_ranap.anamnesis, penilaian_medis_ranap.hubungan,');
        vFilterSQL.Add('       penilaian_medis_ranap.keluhan_utama, penilaian_medis_ranap.rps,');
        vFilterSQL.Add('       penilaian_medis_ranap.rpk, penilaian_medis_ranap.rpd, penilaian_medis_ranap.rpo,');
        vFilterSQL.Add('       penilaian_medis_ranap.alergi, penilaian_medis_ranap.keadaan,');
        vFilterSQL.Add('       penilaian_medis_ranap.gcs, penilaian_medis_ranap.kesadaran,');
        vFilterSQL.Add('       penilaian_medis_ranap.td, penilaian_medis_ranap.nadi,');
        vFilterSQL.Add('       penilaian_medis_ranap.rr, penilaian_medis_ranap.suhu,');
        vFilterSQL.Add('       penilaian_medis_ranap.spo, penilaian_medis_ranap.bb, penilaian_medis_ranap.tb,');
        vFilterSQL.Add('       penilaian_medis_ranap.kepala, penilaian_medis_ranap.mata,');
        vFilterSQL.Add('       penilaian_medis_ranap.gigi, penilaian_medis_ranap.tht,');
        vFilterSQL.Add('       penilaian_medis_ranap.thoraks, penilaian_medis_ranap.jantung,');
        vFilterSQL.Add('       penilaian_medis_ranap.paru, penilaian_medis_ranap.abdomen,');
        vFilterSQL.Add('       penilaian_medis_ranap.ekstremitas, penilaian_medis_ranap.genital,');
        vFilterSQL.Add('       penilaian_medis_ranap.kulit, penilaian_medis_ranap.ket_fisik,');
        vFilterSQL.Add('       penilaian_medis_ranap.ket_lokalis, penilaian_medis_ranap.lab,');
        vFilterSQL.Add('       penilaian_medis_ranap.rad, penilaian_medis_ranap.penunjang,');
        vFilterSQL.Add('       penilaian_medis_ranap.diagnosis, penilaian_medis_ranap.tata,');
        vFilterSQL.Add('       penilaian_medis_ranap.edukasi, dokter.nm_dokter');
        vFilterSQL.Add('FROM reg_periksa');
        vFilterSQL.Add('INNER JOIN pasien ON reg_periksa.no_rkm_medis = pasien.no_rkm_medis');
        vFilterSQL.Add('INNER JOIN penilaian_medis_ranap ON reg_periksa.no_rawat = penilaian_medis_ranap.no_rawat');
        vFilterSQL.Add('INNER JOIN dokter ON penilaian_medis_ranap.kd_dokter = dokter.kd_dokter');
        vFilterSQL.Add('WHERE 1=1');

        if vNoRawat <> '' then
          vFilterSQL.Add('AND penilaian_medis_ranap.no_rawat = :no_rawat');

        if vNoRkmMedis <> '' then
          vFilterSQL.Add('AND pasien.no_rkm_medis = :no_rkm_medis');

        if (vTglAwal <> '') and (vTglAkhir <> '') then
          vFilterSQL.Add('AND penilaian_medis_ranap.tanggal BETWEEN :tgl_awal AND :tgl_akhir');

        vFilterSQL.Add('ORDER BY penilaian_medis_ranap.tanggal DESC');
        vQuery.SQL.Text := vFilterSQL.Text;

        if vNoRawat <> '' then vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        if vNoRkmMedis <> '' then vQuery.ParamByName('no_rkm_medis').AsString := vNoRkmMedis;
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
          vJSONReq.Add('no_rkm_medis', Trim(vQuery.FieldByName('no_rkm_medis').AsString));
          vJSONReq.Add('nm_pasien', Trim(vQuery.FieldByName('nm_pasien').AsString));
          vJSONReq.Add('jk', vQuery.FieldByName('jk').AsString);
          vJSONReq.Add('tgl_lahir', vQuery.FieldByName('tgl_lahir').AsString);
          vJSONReq.Add('tanggal', vQuery.FieldByName('tanggal').AsString);
          vJSONReq.Add('kd_dokter', Trim(vQuery.FieldByName('kd_dokter').AsString));
          vJSONReq.Add('nm_dokter', Trim(vQuery.FieldByName('nm_dokter').AsString));
          vJSONReq.Add('anamnesis', vQuery.FieldByName('anamnesis').AsString);
          vJSONReq.Add('hubungan', vQuery.FieldByName('hubungan').AsString);
          vJSONReq.Add('keluhan_utama', vQuery.FieldByName('keluhan_utama').AsString);
          vJSONReq.Add('rps', vQuery.FieldByName('rps').AsString);
          vJSONReq.Add('rpk', vQuery.FieldByName('rpk').AsString);
          vJSONReq.Add('rpd', vQuery.FieldByName('rpd').AsString);
          vJSONReq.Add('rpo', vQuery.FieldByName('rpo').AsString);
          vJSONReq.Add('alergi', vQuery.FieldByName('alergi').AsString);
          vJSONReq.Add('keadaan', vQuery.FieldByName('keadaan').AsString);
          vJSONReq.Add('gcs', vQuery.FieldByName('gcs').AsString);
          vJSONReq.Add('kesadaran', vQuery.FieldByName('kesadaran').AsString);
          vJSONReq.Add('td', vQuery.FieldByName('td').AsString);
          vJSONReq.Add('nadi', vQuery.FieldByName('nadi').AsString);
          vJSONReq.Add('rr', vQuery.FieldByName('rr').AsString);
          vJSONReq.Add('suhu', vQuery.FieldByName('suhu').AsString);
          vJSONReq.Add('spo', vQuery.FieldByName('spo').AsString);
          vJSONReq.Add('bb', vQuery.FieldByName('bb').AsString);
          vJSONReq.Add('tb', vQuery.FieldByName('tb').AsString);
          vJSONReq.Add('kepala', vQuery.FieldByName('kepala').AsString);
          vJSONReq.Add('mata', vQuery.FieldByName('mata').AsString);
          vJSONReq.Add('gigi', vQuery.FieldByName('gigi').AsString);
          vJSONReq.Add('tht', vQuery.FieldByName('tht').AsString);
          vJSONReq.Add('thoraks', vQuery.FieldByName('thoraks').AsString);
          vJSONReq.Add('jantung', vQuery.FieldByName('jantung').AsString);
          vJSONReq.Add('paru', vQuery.FieldByName('paru').AsString);
          vJSONReq.Add('abdomen', vQuery.FieldByName('abdomen').AsString);
          vJSONReq.Add('ekstremitas', vQuery.FieldByName('ekstremitas').AsString);
          vJSONReq.Add('genital', vQuery.FieldByName('genital').AsString);
          vJSONReq.Add('kulit', vQuery.FieldByName('kulit').AsString);
          vJSONReq.Add('ket_fisik', vQuery.FieldByName('ket_fisik').AsString);
          vJSONReq.Add('ket_lokalis', vQuery.FieldByName('ket_lokalis').AsString);
          vJSONReq.Add('lab', vQuery.FieldByName('lab').AsString);
          vJSONReq.Add('rad', vQuery.FieldByName('rad').AsString);
          vJSONReq.Add('penunjang', vQuery.FieldByName('penunjang').AsString);
          vJSONReq.Add('diagnosis', vQuery.FieldByName('diagnosis').AsString);
          vJSONReq.Add('tata', vQuery.FieldByName('tata').AsString);
          vJSONReq.Add('edukasi', vQuery.FieldByName('edukasi').AsString);

          vJSONArray.Add(vJSONReq);
          vQuery.Next;
        end;

        AResponse.Send(vJSONArray.AsJSON, 'application/json; charset=utf-8', 200);
      finally
        vJSONArray.Free;
      end;
    end

    // =================================================================
    // 2. OPERATION: POST (INSERT PENILAIAN MEDIS)
    // =================================================================
    else if ARequest.Method = 'POST' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat := Trim(vJSONReq.Get('no_rawat', ''));
        vTanggal := Trim(vJSONReq.Get('tanggal', ''));
        vTanggal := PerbaikiFormatTanggal(vTanggal); // Auto-format ke YYYY-MM-DD

        if (vNoRawat = '') or (vTanggal = '') then
          raise Exception.Create('Parameter no_rawat dan tanggal wajib diisi!');

        // Pre-Check 1: Anti Duplikasi Composite Key (no_rawat + tanggal)
        vQuery.SQL.Clear;
        vQuery.SQL.Add('SELECT COUNT(*) AS jumlah FROM penilaian_medis_ranap WHERE no_rawat = :no_rawat AND tanggal = :tanggal');
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tanggal').AsString := vTanggal;
        vQuery.Open;
        if vQuery.FieldByName('jumlah').AsInteger > 0 then
        begin
          AResponse.Send('{"status": "error", "message": "Gagal: Penilaian medis sudah ada untuk nomor rawat dan tanggal tersebut!"}', 'application/json', 409);
          Exit;
        end;
        vQuery.Close;

        // Pre-Check 2: Kebijakan Aturan Utama (1 No Rawat hanya boleh memiliki 1 Penilaian Awal Medis)
        vQuery.SQL.Clear;
        vQuery.SQL.Add('SELECT COUNT(*) AS jumlah FROM penilaian_medis_ranap WHERE no_rawat = :no_rawat');
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.Open;
        if vQuery.FieldByName('jumlah').AsInteger > 0 then
        begin
          AResponse.Send('{"status": "error", "message": "Gagal: Data penilaian medis awal sudah pernah dibuat untuk nomor rawat ini!"}', 'application/json', 409);
          Exit;
        end;
        vQuery.Close;

        // Ambil Data Payload Lainnya
        vKdDokter     := vJSONReq.Get('kd_dokter', '');
        vAnamnesis    := vJSONReq.Get('anamnesis', 'Autonamnesis');
        vHubungan     := vJSONReq.Get('hubungan', '-');
        vKeluhanUtama := vJSONReq.Get('keluhan_utama', '');
        vRps          := vJSONReq.Get('rps', '-');
        vRpk          := vJSONReq.Get('rpk', '-');
        vRpd          := vJSONReq.Get('rpd', '-');
        vRpo          := vJSONReq.Get('rpo', '-');
        vAlergi       := vJSONReq.Get('alergi', '-');
        vKeadaan      := vJSONReq.Get('keadaan', 'Baik');
        vGcs          := vJSONReq.Get('gcs', '15');
        vKesadaran    := vJSONReq.Get('kesadaran', 'Compos Mentis');
        vTd           := vJSONReq.Get('td', '-');
        vNadi         := vJSONReq.Get('nadi', '-');
        vRr           := vJSONReq.Get('rr', '-');
        vSuhu         := vJSONReq.Get('suhu', '-');
        vSpo          := vJSONReq.Get('spo', '-');
        vBb           := vJSONReq.Get('bb', '-');
        vTb           := vJSONReq.Get('tb', '-');
        vKepala       := vJSONReq.Get('kepala', 'Normal');
        vMata         := vJSONReq.Get('mata', 'Normal');
        vGigi         := vJSONReq.Get('gigi', 'Normal');
        vTht          := vJSONReq.Get('tht', 'Normal');
        vThoraks      := vJSONReq.Get('thoraks', 'Normal');
        vJantung      := vJSONReq.Get('jantung', 'Normal');
        vParu         := vJSONReq.Get('paru', 'Normal');
        vAbdomen      := vJSONReq.Get('abdomen', 'Normal');
        vEkstremitas  := vJSONReq.Get('ekstremitas', 'Normal');
        vGenital      := vJSONReq.Get('genital', 'Normal');
        vKulit        := vJSONReq.Get('kulit', 'Normal');
        vKetFisik     := vJSONReq.Get('ket_fisik', '-');
        vKetLokalis   := vJSONReq.Get('ket_lokalis', '-');
        vLab          := vJSONReq.Get('lab', '-');
        vRad          := vJSONReq.Get('rad', '-');
        vPenunjang    := vJSONReq.Get('penunjang', '-');
        vDiagnosis    := vJSONReq.Get('diagnosis', '');
        vTata         := vJSONReq.Get('tata', '');
        vEdukasi      := vJSONReq.Get('edukasi', '-');

        // Proses INSERT INTO
        vQuery.SQL.Clear;
        vQuery.SQL.Add('INSERT INTO penilaian_medis_ranap (no_rawat, tanggal, kd_dokter, anamnesis, hubungan, keluhan_utama,');
        vQuery.SQL.Add('rps, rpk, rpd, rpo, alergi, keadaan, gcs, kesadaran, td, nadi, rr, suhu, spo, bb, tb, kepala, mata, gigi,');
        vQuery.SQL.Add('tht, thoraks, jantung, paru, abdomen, ekstremitas, genital, kulit, ket_fisik, ket_lokalis, lab, rad, penunjang, diagnosis, tata, edukasi)');
        vQuery.SQL.Add('VALUES (:no_rawat, :tanggal, :kd_dokter, :anamnesis, :hubungan, :keluhan_utama, :rps, :rpk, :rpd, :rpo, :alergi,');
        vQuery.SQL.Add(':keadaan, :gcs, :kesadaran, :td, :nadi, :rr, :suhu, :spo, :bb, :tb, :kepala, :mata, :gigi, :tht, :thoraks, :jantung, :paru, :abdomen, :ekstremitas, :genital, :kulit, :ket_fisik, :ket_lokalis, :lab, :rad, :penunjang, :diagnosis, :tata, :edukasi)');

        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tanggal').AsString := vTanggal;
        vQuery.ParamByName('kd_dokter').AsString := vKdDokter;
        vQuery.ParamByName('anamnesis').AsString := vAnamnesis;
        vQuery.ParamByName('hubungan').AsString := vHubungan;
        vQuery.ParamByName('keluhan_utama').AsString := vKeluhanUtama;
        vQuery.ParamByName('rps').AsString := vRps;
        vQuery.ParamByName('rpk').AsString := vRpk;
        vQuery.ParamByName('rpd').AsString := vRpd;
        vQuery.ParamByName('rpo').AsString := vRpo;
        vQuery.ParamByName('alergi').AsString := vAlergi;
        vQuery.ParamByName('keadaan').AsString := vKeadaan;
        vQuery.ParamByName('gcs').AsString := vGcs;
        vQuery.ParamByName('kesadaran').AsString := vKesadaran;
        vQuery.ParamByName('td').AsString := vTd;
        vQuery.ParamByName('nadi').AsString := vNadi;
        vQuery.ParamByName('rr').AsString := vRr;
        vQuery.ParamByName('suhu').AsString := vSuhu;
        vQuery.ParamByName('spo').AsString := vSpo;
        vQuery.ParamByName('bb').AsString := vBb;
        vQuery.ParamByName('tb').AsString := vTb;
        vQuery.ParamByName('kepala').AsString := vKepala;
        vQuery.ParamByName('mata').AsString := vMata;
        vQuery.ParamByName('gigi').AsString := vGigi;
        vQuery.ParamByName('tht').AsString := vTht;
        vQuery.ParamByName('thoraks').AsString := vThoraks;
        vQuery.ParamByName('jantung').AsString := vJantung;
        vQuery.ParamByName('paru').AsString := vParu;
        vQuery.ParamByName('abdomen').AsString := vAbdomen;
        vQuery.ParamByName('ekstremitas').AsString := vEkstremitas;
        vQuery.ParamByName('genital').AsString := vGenital;
        vQuery.ParamByName('kulit').AsString := vKulit;
        vQuery.ParamByName('ket_fisik').AsString := vKetFisik;
        vQuery.ParamByName('ket_lokalis').AsString := vKetLokalis;
        vQuery.ParamByName('lab').AsString := vLab;
        vQuery.ParamByName('rad').AsString := vRad;
        vQuery.ParamByName('penunjang').AsString := vPenunjang;
        vQuery.ParamByName('diagnosis').AsString := vDiagnosis;
        vQuery.ParamByName('tata').AsString := vTata;
        vQuery.ParamByName('edukasi').AsString := vEdukasi;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data penilaian medis rawat inap berhasil disimpan"}', 'application/json', 201);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 3. OPERATION: PUT (UPDATE DATA PENILAIAN MEDIS)
    // =================================================================
    else if ARequest.Method = 'PUT' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat := Trim(vJSONReq.Get('no_rawat', ''));
        vTanggal := Trim(vJSONReq.Get('tanggal', ''));
        vTanggal := PerbaikiFormatTanggal(vTanggal); // Auto-format ke YYYY-MM-DD

        if (vNoRawat = '') or (vTanggal = '') then
          raise Exception.Create('Identifikasi kunci (no_rawat dan tanggal) wajib disertakan!');

        vKdDokter     := vJSONReq.Get('kd_dokter', '');
        vAnamnesis    := vJSONReq.Get('anamnesis', 'Autonamnesis');
        vHubungan     := vJSONReq.Get('hubungan', '-');
        vKeluhanUtama := vJSONReq.Get('keluhan_utama', '');
        vRps          := vJSONReq.Get('rps', '-');
        vRpk          := vJSONReq.Get('rpk', '-');
        vRpd          := vJSONReq.Get('rpd', '-');
        vRpo          := vJSONReq.Get('rpo', '-');
        vAlergi       := vJSONReq.Get('alergi', '-');
        vKeadaan      := vJSONReq.Get('keadaan', 'Baik');
        vGcs          := vJSONReq.Get('gcs', '15');
        vKesadaran    := vJSONReq.Get('kesadaran', 'Compos Mentis');
        vTd           := vJSONReq.Get('td', '-');
        vNadi         := vJSONReq.Get('nadi', '-');
        vRr           := vJSONReq.Get('rr', '-');
        vSuhu         := vJSONReq.Get('suhu', '-');
        vSpo          := vJSONReq.Get('spo', '-');
        vBb           := vJSONReq.Get('bb', '-');
        vTb           := vJSONReq.Get('tb', '-');
        vKepala       := vJSONReq.Get('kepala', 'Normal');
        vMata         := vJSONReq.Get('mata', 'Normal');
        vGigi         := vJSONReq.Get('gigi', 'Normal');
        vTht          := vJSONReq.Get('tht', 'Normal');
        vThoraks      := vJSONReq.Get('thoraks', 'Normal');
        vJantung      := vJSONReq.Get('jantung', 'Normal');
        vParu         := vJSONReq.Get('paru', 'Normal');
        vAbdomen      := vJSONReq.Get('abdomen', 'Normal');
        vEkstremitas  := vJSONReq.Get('ekstremitas', 'Normal');
        vGenital      := vJSONReq.Get('genital', 'Normal');
        vKulit        := vJSONReq.Get('kulit', 'Normal');
        vKetFisik     := vJSONReq.Get('ket_fisik', '-');
        vKetLokalis   := vJSONReq.Get('ket_lokalis', '-');
        vLab          := vJSONReq.Get('lab', '-');
        vRad          := vJSONReq.Get('rad', '-');
        vPenunjang    := vJSONReq.Get('penunjang', '-');
        vDiagnosis    := vJSONReq.Get('diagnosis', '');
        vTata         := vJSONReq.Get('tata', '');
        vEdukasi      := vJSONReq.Get('edukasi', '-');

        vQuery.SQL.Clear;
        vQuery.SQL.Add('UPDATE penilaian_medis_ranap SET kd_dokter = :kd_dokter, anamnesis = :anamnesis, hubungan = :hubungan,');
        vQuery.SQL.Add('keluhan_utama = :keluhan_utama, rps = :rps, rpk = :rpk, rpd = :rpd, rpo = :rpo, alergi = :alergi, keadaan = :keadaan,');
        vQuery.SQL.Add('gcs = :gcs, kesadaran = :kesadaran, td = :td, nadi = :nadi, rr = :rr, suhu = :suhu, spo = :spo, bb = :bb, tb = :tb,');
        vQuery.SQL.Add('kepala = :kepala, mata = :mata, gigi = :gigi, tht = :tht, thoraks = :thoraks, jantung = :jantung, paru = :paru,');
        vQuery.SQL.Add('abdomen = :abdomen, ekstremitas = :ekstremitas, genital = :genital, kulit = :kulit, ket_fisik = :ket_fisik,');
        vQuery.SQL.Add('ket_lokalis = :ket_lokalis, lab = :lab, rad = :rad, penunjang = :penunjang, diagnosis = :diagnosis, tata = :tata, edukasi = :edukasi');
        vQuery.SQL.Add('WHERE no_rawat = :no_rawat AND tanggal = :tanggal');

        vQuery.ParamByName('kd_dokter').AsString := vKdDokter;
        vQuery.ParamByName('anamnesis').AsString := vAnamnesis;
        vQuery.ParamByName('hubungan').AsString := vHubungan;
        vQuery.ParamByName('keluhan_utama').AsString := vKeluhanUtama;
        vQuery.ParamByName('rps').AsString := vRps;
        vQuery.ParamByName('rpk').AsString := vRpk;
        vQuery.ParamByName('rpd').AsString := vRpd;
        vQuery.ParamByName('rpo').AsString := vRpo;
        vQuery.ParamByName('alergi').AsString := vAlergi;
        vQuery.ParamByName('keadaan').AsString := vKeadaan;
        vQuery.ParamByName('gcs').AsString := vGcs;
        vQuery.ParamByName('kesadaran').AsString := vKesadaran;
        vQuery.ParamByName('td').AsString := vTd;
        vQuery.ParamByName('nadi').AsString := vNadi;
        vQuery.ParamByName('rr').AsString := vRr;
        vQuery.ParamByName('suhu').AsString := vSuhu;
        vQuery.ParamByName('spo').AsString := vSpo;
        vQuery.ParamByName('bb').AsString := vBb;
        vQuery.ParamByName('tb').AsString := vTb;
        vQuery.ParamByName('kepala').AsString := vKepala;
        vQuery.ParamByName('mata').AsString := vMata;
        vQuery.ParamByName('gigi').AsString := vGigi;
        vQuery.ParamByName('tht').AsString := vTht;
        vQuery.ParamByName('thoraks').AsString := vThoraks;
        vQuery.ParamByName('jantung').AsString := vJantung;
        vQuery.ParamByName('paru').AsString := vParu;
        vQuery.ParamByName('abdomen').AsString := vAbdomen;
        vQuery.ParamByName('ekstremitas').AsString := vEkstremitas;
        vQuery.ParamByName('genital').AsString := vGenital;
        vQuery.ParamByName('kulit').AsString := vKulit;
        vQuery.ParamByName('ket_fisik').AsString := vKetFisik;
        vQuery.ParamByName('ket_lokalis').AsString := vKetLokalis;
        vQuery.ParamByName('lab').AsString := vLab;
        vQuery.ParamByName('rad').AsString := vRad;
        vQuery.ParamByName('penunjang').AsString := vPenunjang;
        vQuery.ParamByName('diagnosis').AsString := vDiagnosis;
        vQuery.ParamByName('tata').AsString := vTata;
        vQuery.ParamByName('edukasi').AsString := vEdukasi;
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tanggal').AsString := vTanggal;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data penilaian medis berhasil diperbarui"}', 'application/json', 200);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end

    // =================================================================
    // 4. OPERATION: DELETE (DELETE DATA VIA COMPOSITE KEY)
    // =================================================================
    else if ARequest.Method = 'DELETE' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoRawat := Trim(vJSONReq.Get('no_rawat', ''));
        vTanggal := Trim(vJSONReq.Get('tanggal', ''));
        vTanggal := PerbaikiFormatTanggal(vTanggal); // Auto-format ke YYYY-MM-DD

        if (vNoRawat = '') or (vTanggal = '') then
          raise Exception.Create('Penghapusan data membutuhkan parameter no_rawat dan tanggal!');

        vQuery.SQL.Clear;
        vQuery.SQL.Add('DELETE FROM penilaian_medis_ranap WHERE no_rawat = :no_rawat AND tanggal = :tanggal');
        vQuery.ParamByName('no_rawat').AsString := vNoRawat;
        vQuery.ParamByName('tanggal').AsString := vTanggal;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data penilaian medis berhasil dihapus"}', 'application/json', 200);
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
