unit umod_inacbg;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset,ZConnection, BrookURLRouter, BrookHTTPRequest, BrookHTTPResponse,
  BrookUtility, fpjson, jsonparser, Math;

type
  { TRouteInacbgPasien }
  TRouteInacbgPasien = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

  { TRouteInacbgDetailPasien }
  TRouteInacbgDetailPasien = class(TBrookURLRoute)
  private
    function AmbilTotalBiaya(gZConn: TZConnection; const ANoRawat, AQueryStr: string): Double;
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

// Merujuk ke core handler untuk menggunakan database pool global (gZConn) dan Auth Middleware
uses uhandlerapi;

procedure TRouteInacbgPasien.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];
  Pattern := '/api/v1/inacbg/pasien'; // Endpoint Modul INACBG
end;

procedure TRouteInacbgPasien.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vQueryUtama, vQuerySub: TZQuery;
  vTglAwal, vTglAkhir, vCaraBayar, vKeyword, vNoRawat: string;
  JSONArray, JSONDiagnosa, JSONProsedur: TJSONArray;
  JSONObject, JSONSubObj: TJSONObject;
  vStatusKirim: Integer;
  // untuk kompres
  vJSONMentah, vJSONKompres: string;
begin
  // Wajib Amankan Modul Klaim dengan Token Authentication
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  // 1. Tangkap parameter filter query string dari URL (?tgl_awal=...&tgl_akhir=...&carabayar=...&search=...)
  vTglAwal   := Trim(ARequest.Params.Values['tgl_awal']);
  vTglAkhir  := Trim(ARequest.Params.Values['tgl_akhir']);
  vCaraBayar := Trim(ARequest.Params.Values['carabayar']);
  vKeyword   := Trim(ARequest.Params.Values['search']);

  // Validasi parameter tanggal wajib ada
  if (vTglAwal = '') or (vTglAkhir = '') then
  begin
    AResponse.Send('{"status": "error", "message": "Parameter tgl_awal dan tgl_akhir wajib diisi (YYYY-MM-DD)"}', 'application/json', 400);
    Exit;
  end;

  vQueryUtama := TZQuery.Create(nil);
  vQueryUtama.Connection := uhandlerapi.gZConn;

  vQuerySub := TZQuery.Create(nil);
  vQuerySub.Connection := uhandlerapi.gZConn;

  JSONArray := TJSONArray.Create;

  try
    // 2. Susun Query Utama (List Data Pasien)
    vQueryUtama.SQL.Clear;
    vQueryUtama.SQL.Add('SELECT ');
    vQueryUtama.SQL.Add('  reg_periksa.no_reg, reg_periksa.no_rawat, reg_periksa.tgl_registrasi, reg_periksa.jam_reg, ');
    vQueryUtama.SQL.Add('  reg_periksa.kd_dokter, dokter.nm_dokter, reg_periksa.no_rkm_medis, pasien.nm_pasien, ');
    vQueryUtama.SQL.Add('  IF(pasien.jk="L","Laki-Laki","Perempuan") as jk, pasien.umur, poliklinik.nm_poli, ');
    vQueryUtama.SQL.Add('  reg_periksa.p_jawab, reg_periksa.almt_pj, reg_periksa.hubunganpj, reg_periksa.biaya_reg, ');
    vQueryUtama.SQL.Add('  reg_periksa.status_bayar, penjab.png_jawab ');
    vQueryUtama.SQL.Add('FROM reg_periksa ');
    vQueryUtama.SQL.Add('INNER JOIN dokter ON reg_periksa.kd_dokter = dokter.kd_dokter ');
    vQueryUtama.SQL.Add('INNER JOIN pasien ON reg_periksa.no_rkm_medis = pasien.no_rkm_medis ');
    vQueryUtama.SQL.Add('INNER JOIN poliklinik ON reg_periksa.kd_poli = poliklinik.kd_poli ');
    vQueryUtama.SQL.Add('INNER JOIN penjab ON reg_periksa.kd_pj = penjab.kd_pj ');
    vQueryUtama.SQL.Add('WHERE reg_periksa.stts <> "Batal" ');
    vQueryUtama.SQL.Add('  AND reg_periksa.tgl_registrasi BETWEEN :tglAwal AND :tglAkhir ');

    // Kondisional Parameter Cara Bayar (Biasanya difilter kata "BPJS")
    if vCaraBayar <> '' then
    begin
      vQueryUtama.SQL.Add('  AND penjab.png_jawab LIKE :carabayar ');
      vQueryUtama.ParamByName('carabayar').AsString := '%' + vCaraBayar + '%';
    end;

    // Kondisional Parameter Search (Multiple Fields: No RM, Nama Pasien, No Rawat)
    if vKeyword <> '' then
    begin
      vQueryUtama.SQL.Add('  AND (reg_periksa.no_rawat LIKE :key ');
      vQueryUtama.SQL.Add('  OR reg_periksa.no_rkm_medis LIKE :key ');
      vQueryUtama.SQL.Add('  OR pasien.nm_pasien LIKE :key) ');
      vQueryUtama.ParamByName('key').AsString := '%' + vKeyword + '%';
    end;

    vQueryUtama.SQL.Add('ORDER BY reg_periksa.tgl_registrasi, reg_periksa.jam_reg DESC');

    vQueryUtama.ParamByName('tglAwal').AsString := vTglAwal;
    vQueryUtama.ParamByName('tglAkhir').AsString := vTglAkhir;
    vQueryUtama.Open;

    // 3. Looping Hasil & Ambil Data Pendukung Menggunakan Data Per-Baris (No Rawat)
    while not vQueryUtama.EOF do
    begin
      vNoRawat := vQueryUtama.FieldByName('no_rawat').AsString;
      JSONObject := TJSONObject.Create;

      // Masukkan Data Demografi & Registrasi Utama
      JSONObject.Add('no_reg', vQueryUtama.FieldByName('no_reg').AsString);
      JSONObject.Add('no_rawat', vNoRawat);
      JSONObject.Add('tgl_registrasi', vQueryUtama.FieldByName('tgl_registrasi').AsString);
      JSONObject.Add('jam_reg', vQueryUtama.FieldByName('jam_reg').AsString);
      JSONObject.Add('dokter', vQueryUtama.FieldByName('nm_dokter').AsString);
      JSONObject.Add('no_rm', vQueryUtama.FieldByName('no_rkm_medis').AsString);
      JSONObject.Add('nama_pasien', vQueryUtama.FieldByName('nm_pasien').AsString);
      JSONObject.Add('jk', vQueryUtama.FieldByName('jk').AsString);
      JSONObject.Add('umur', vQueryUtama.FieldByName('umur').AsString);
      JSONObject.Add('poliklinik', vQueryUtama.FieldByName('nm_poli').AsString);
      JSONObject.Add('png_jawab', vQueryUtama.FieldByName('png_jawab').AsString);
      JSONObject.Add('status_bayar', vQueryUtama.FieldByName('status_bayar').AsString);

      // --- SUB QUERY 1: Cek Status Kirim Klaim INACBG ---
      vQuerySub.SQL.Clear;
      vQuerySub.SQL.Add('SELECT COUNT(no_rawat) AS hitung FROM inacbg_klaim_baru2 WHERE no_rawat = :norawat');
      vQuerySub.ParamByName('norawat').AsString := vNoRawat;
      vQuerySub.Open;
      vStatusKirim := vQuerySub.FieldByName('hitung').AsInteger;
      vQuerySub.Close;

      if vStatusKirim > 0 then
        JSONObject.Add('status_klaim', 'Sudah Dikirim')
      else
        JSONObject.Add('status_klaim', 'Belum Dikirim');

      // --- SUB QUERY 2: Ambil Daftar Diagnosa (ICD-10) ---
      JSONDiagnosa := TJSONArray.Create;
      vQuerySub.SQL.Clear;
      vQuerySub.SQL.Add('SELECT kd_penyakit FROM diagnosa_pasien WHERE no_rawat = :norawat ORDER BY prioritas ASC');
      vQuerySub.ParamByName('norawat').AsString := vNoRawat;
      vQuerySub.Open;
      while not vQuerySub.EOF do
      begin
        JSONDiagnosa.Add(vQuerySub.FieldByName('kd_penyakit').AsString);
        vQuerySub.Next;
      end;
      vQuerySub.Close;
      JSONObject.Add('diagnosa_icd10', JSONDiagnosa);

      // --- SUB QUERY 3: Ambil Daftar Prosedur (ICD-9 CM) ---
      JSONProsedur := TJSONArray.Create;
      vQuerySub.SQL.Clear;
      // HAPUS kolom 'jumlah' dari SELECT
      vQuerySub.SQL.Add('SELECT kode FROM prosedur_pasien WHERE no_rawat = :norawat ORDER BY prioritas ASC');
      vQuerySub.ParamByName('norawat').AsString := vNoRawat;
      vQuerySub.Open;
      while not vQuerySub.EOF do
      begin
        JSONSubObj := TJSONObject.Create;
        JSONSubObj.Add('kode_prosedur', vQuerySub.FieldByName('kode').AsString);
        // HAPUS baris pembacaan field 'jumlah' di sini jika tidak ada kolomnya
        // atau jika INACBG butuh default angka, hardcode saja jadi 1:
        JSONSubObj.Add('jumlah', 1);

        JSONProsedur.Add(JSONSubObj);
        vQuerySub.Next;
      end;
      vQuerySub.Close;
      JSONObject.Add('prosedur_icd9', JSONProsedur);

      // Tambahkan Object Lengkap ke Array Kunjungan
      JSONArray.Add(JSONObject);
      vQueryUtama.Next;
    end;

    // Kirim Hasil Akhir
    //sebelumnya AResponse.Send(JSONArray.AsJSON, 'application/json; charset=utf-8', 200);
    // [SEKARANG]: Ubah Menjadi Kompresi GZip dinamis

    vJSONMentah := JSONArray.AsJSON;
    // Cek apakah klien mendukung kompresi (opsional, tapi disarankan)
    if Pos('gzip', LowerCase(ARequest.Headers.Values['Accept-Encoding'])) > 0 then
    begin
      // Lakukan kompresi menggunakan fungsi global dari uhandlerapi
      vJSONKompres := uhandlerapi.KompresStringKeGZip(vJSONMentah);

      // Wajib beri tahu klien (Postman/Browser) via Header bahwa data ini dikompresi
      AResponse.Headers.Add('Content-Encoding', 'deflate'); // Sesuai dengan cldefault zstream
      AResponse.Headers.Add('X-Compression', 'GZip-Active'); // Penanda custom untuk dokumentasi

      AResponse.Send(vJSONKompres, 'application/json; charset=utf-8', 200);
    end
    else
    begin
      // Jika klien jadul dan tidak mendukung gzip, kirim JSON biasa saja
      AResponse.Send(vJSONMentah, 'application/json; charset=utf-8', 200);
    end;

  except
    on E: Exception do
    begin
      AResponse.SendFmt('{"status": "error", "message": "Inacbg Module Error: %s"}', [E.Message], 'application/json', 500);
    end;
  end;

  // Bebaskan Memori Sistem
  vQueryUtama.Free;
  vQuerySub.Free;
  JSONArray.Free;
end;

// Tambahkan di bagian bawah (Implementation) dari umod_inacbg.pas

{ TRouteInacbgDetailPasien }

procedure TRouteInacbgDetailPasien.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];
  Pattern := '/api/v1/inacbg/detail'; // Endpoint untuk mendapatkan rincian klaim
end;

function TRouteInacbgDetailPasien.AmbilTotalBiaya(gZConn: TZConnection; const ANoRawat, AQueryStr: string): Double;
var
  vQ: TZQuery;
begin
  Result := 0;
  vQ := TZQuery.Create(nil);
  try
    vQ.Connection := gZConn;
    vQ.SQL.Text := AQueryStr;
    if Pos(':norawat', AQueryStr) > 0 then
      vQ.ParamByName('norawat').AsString := ANoRawat;
    vQ.Open;
    if not vQ.IsEmpty then
      Result := vQ.Fields[0].AsFloat;
  finally
    vQ.Free;
  end;
end;

procedure TRouteInacbgDetailPasien.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vNoRawat, vSttsLanjut, vNoSEP, vJSONMentah, vJSONKompres: string;
  vQMain, vQSub: TZQuery;
  JSONRes, JSONBiaya: TJSONObject;
  JSONDiagnosa, JSONProsedur: TJSONArray;
  vBiayaReg, vProsedurNonBedah, vProsedurBedah, vKonsultasi: Double;
  vKeperawatan, vKamar, vKamarIntensif, vObat: Double;
begin
  // Amankan modul dengan Token Auth
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  // Tangkap parameter no_rawat dari URL (contoh: ?no_rawat=2026/06/25/000001)
  vNoRawat := Trim(ARequest.Params.Values['no_rawat']);

  if vNoRawat = '' then
  begin
    AResponse.Send('{"status": "error", "message": "Parameter no_rawat wajib diisi"}', 'application/json', 400);
    Exit;
  end;

  vQMain := TZQuery.Create(nil);
  vQMain.Connection := uhandlerapi.gZConn;

  vQSub := TZQuery.Create(nil);
  vQSub.Connection := uhandlerapi.gZConn;

  JSONRes := TJSONObject.Create;

  try
    // 3.1. Query Data Pasien Utama
    vQMain.SQL.Clear;
    vQMain.SQL.Add('SELECT reg_periksa.no_reg, reg_periksa.no_rawat, reg_periksa.tgl_registrasi, reg_periksa.jam_reg, ');
    vQMain.SQL.Add('       reg_periksa.kd_dokter, dokter.nm_dokter, reg_periksa.no_rkm_medis, pasien.nm_pasien, ');
    vQMain.SQL.Add('       pasien.jk, pasien.umur, pasien.tgl_lahir, poliklinik.nm_poli, reg_periksa.status_lanjut, ');
    vQMain.SQL.Add('       reg_periksa.umurdaftar, reg_periksa.sttsumur, reg_periksa.p_jawab, reg_periksa.almt_pj, ');
    vQMain.SQL.Add('       reg_periksa.hubunganpj, reg_periksa.biaya_reg, reg_periksa.stts_daftar, penjab.png_jawab ');
    vQMain.SQL.Add('FROM reg_periksa ');
    vQMain.SQL.Add('INNER JOIN dokter ON reg_periksa.kd_dokter = dokter.kd_dokter ');
    vQMain.SQL.Add('INNER JOIN pasien ON reg_periksa.no_rkm_medis = pasien.no_rkm_medis ');
    vQMain.SQL.Add('INNER JOIN poliklinik ON reg_periksa.kd_poli = poliklinik.kd_poli ');
    vQMain.SQL.Add('INNER JOIN penjab ON reg_periksa.kd_pj = penjab.kd_pj ');
    vQMain.SQL.Add('WHERE reg_periksa.no_rawat = :norawat LIMIT 1');
    vQMain.ParamByName('norawat').AsString := vNoRawat;
    vQMain.Open;

    if vQMain.IsEmpty then
    begin
      AResponse.Send('{"status": "error", "message": "Data pasien tidak ditemukan"}', 'application/json', 404);
      Exit;
    end;

    vSttsLanjut := vQMain.FieldByName('status_lanjut').AsString;
    vBiayaReg := vQMain.FieldByName('biaya_reg').AsFloat;

    // Set Data Demografi Utama ke JSON Response
    JSONRes.Add('status', 'success');
    JSONRes.Add('no_rawat', vQMain.FieldByName('no_rawat').AsString);
    JSONRes.Add('no_reg', vQMain.FieldByName('no_reg').AsString);
    JSONRes.Add('no_rm', vQMain.FieldByName('no_rkm_medis').AsString);
    JSONRes.Add('nama_pasien', vQMain.FieldByName('nm_pasien').AsString);
    JSONRes.Add('jk', vQMain.FieldByName('jk').AsString);
    JSONRes.Add('tgl_lahir', vQMain.FieldByName('tgl_lahir').AsString);
    JSONRes.Add('umur', vQMain.FieldByName('umur').AsString + ' ' + vQMain.FieldByName('sttsumur').AsString);
    JSONRes.Add('status_lanjut', vSttsLanjut);
    JSONRes.Add('poliklinik', vQMain.FieldByName('nm_poli').AsString);
    JSONRes.Add('png_jawab', vQMain.FieldByName('png_jawab').AsString);

    // 3.2. Query DPJP (Khusus Rawat Inap)
    vQSub.SQL.Text := 'SELECT dokter.nm_dokter FROM dpjp_ranap INNER JOIN dokter ON dpjp_ranap.kd_dokter = dokter.kd_dokter WHERE dpjp_ranap.no_rawat = :norawat LIMIT 1';
    vQSub.ParamByName('norawat').AsString := vNoRawat;
    vQSub.Open;
    if not vQSub.IsEmpty then
      JSONRes.Add('dpjp', vQSub.FieldByName('nm_dokter').AsString)
    else
      JSONRes.Add('dpjp', vQMain.FieldByName('nm_dokter').AsString); // Fallback ke dokter poli utama
    vQSub.Close;

    // 3.3. Logika Pencarian No SEP Kompleks (Ralan vs Ranap)
    vNoSEP := '';
    if vSttsLanjut = 'Ralan' then
    begin
      vQSub.SQL.Text := 'SELECT no_sep FROM bridging_sep WHERE no_rawat = :norawat ORDER BY CONVERT(RIGHT(no_sep,6),SIGNED) DESC LIMIT 1';
      vQSub.ParamByName('norawat').AsString := vNoRawat;
      vQSub.Open;
      if not vQSub.IsEmpty then vNoSEP := vQSub.FieldByName('no_sep').AsString;
      vQSub.Close;
    end
    else if vSttsLanjut = 'Ranap' then
    begin
      vQSub.SQL.Text := 'SELECT no_sep FROM bridging_sep_internal WHERE no_rawat = :norawat ORDER BY CONVERT(RIGHT(no_sep,6),SIGNED) DESC LIMIT 1';
      vQSub.ParamByName('norawat').AsString := vNoRawat;
      vQSub.Open;
      if not vQSub.IsEmpty then vNoSEP := vQSub.FieldByName('no_sep').AsString;
      vQSub.Close;
    end;

    // Jika kosong di kedua tabel bridging, cek tabel custom/riwayat klaim baru bawaan Khanza
    if vNoSEP = '' then
    begin
      vQSub.SQL.Text := 'SELECT no_sep FROM inacbg_klaim_baru2 WHERE no_rawat = :norawat LIMIT 1';
      vQSub.ParamByName('norawat').AsString := vNoRawat;
      vQSub.Open;
      if not vQSub.IsEmpty then vNoSEP := vQSub.FieldByName('no_sep').AsString;
      vQSub.Close;
    end;
    JSONRes.Add('no_sep', vNoSEP);

    // 3.4. Query Diagnosa (ICD-10)
    JSONDiagnosa := TJSONArray.Create;
    vQSub.SQL.Text := 'SELECT kd_penyakit FROM diagnosa_pasien WHERE no_rawat = :norawat ORDER BY prioritas ASC';
    vQSub.ParamByName('norawat').AsString := vNoRawat;
    vQSub.Open;
    while not vQSub.EOF do
    begin
      JSONDiagnosa.Add(vQSub.FieldByName('kd_penyakit').AsString);
      vQSub.Next;
    end;
    vQSub.Close;
    JSONRes.Add('diagnosa', JSONDiagnosa);

    // 3.5. Query Prosedur (ICD-9 CM)
    JSONProsedur := TJSONArray.Create;
    vQSub.SQL.Text := 'SELECT kode FROM prosedur_pasien WHERE no_rawat = :norawat ORDER BY prioritas ASC';
    vQSub.ParamByName('norawat').AsString := vNoRawat;
    vQSub.Open;
    while not vQSub.EOF do
    begin
      JSONProsedur.Add(vQSub.FieldByName('kode').AsString);
      vQSub.Next;
    end;
    vQSub.Close;
    JSONRes.Add('prosedur', JSONProsedur);

    // =================================================================
    // 3.6. AKUMULASI PERHITUNGAN BIAYA RIIL (BILLING RM)
    // =================================================================
    JSONBiaya := TJSONObject.Create;

    // a. Prosedur Non Bedah (Ralan + Ranap Dokter Paramedis)
    vProsedurNonBedah := AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Ralan Dokter Paramedis'' AND nm_perawatan NOT LIKE ''%terapi%''') +
                         AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Ranap Dokter Paramedis'' AND nm_perawatan NOT LIKE ''%terapi%''');
    // Diubah dari Float menjadi String Terformat '0.00'
    JSONBiaya.Add('prosedur_non_bedah', FormatFloat('0.00', vProsedurNonBedah));

    // b. Prosedur Bedah
    vProsedurBedah := AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Operasi''');
    JSONBiaya.Add('prosedur_bedah', FormatFloat('0.00', vProsedurBedah));

    // c. Konsultasi
    vKonsultasi := AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Ranap Dokter''') +
                   AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Ralan Dokter''');
    JSONBiaya.Add('konsultasi', FormatFloat('0.00', vKonsultasi));

    // d. Keperawatan
    vKeperawatan := AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Ranap Paramedis''') +
                    AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Ralan Paramedis''');
    JSONBiaya.Add('keperawatan', FormatFloat('0.00', vKeperawatan));

    // e. Kamar Rawat Biasa (Tanpa Kamar Intensif) + Biaya Registrasi Awal
    vKamar := AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Kamar'' AND nm_perawatan NOT LIKE ''%ICU%'' AND nm_perawatan NOT LIKE ''%CVCU%'' AND nm_perawatan NOT LIKE ''%HCU%'' AND nm_perawatan NOT LIKE ''%NICU%'' AND nm_perawatan NOT LIKE ''%PICU%''') + vBiayaReg;
    JSONBiaya.Add('kamar', FormatFloat('0.00', vKamar))

    // f. Rawat Intensif (Kamar Intensif ICU, HCU, dll)
    vKamarIntensif := AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Kamar'' AND (nm_perawatan LIKE ''%ICU%'' OR nm_perawatan LIKE ''%CVCU%'' OR nm_perawatan LIKE ''%HCU%'' OR nm_perawatan LIKE ''%NICU%'' OR nm_perawatan LIKE ''%PICU%'')');
    JSONBiaya.Add('rawat_intensif', FormatFloat('0.00', vKamarIntensif));

    // g. Obat / Farmasi (Akumulasi penjualan obat, retur dan resep pulang)
    vObat := AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Obat''') +
             AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Retur Obat''') +
             AmbilTotalBiaya(uhandlerapi.gZConn, vNoRawat, 'SELECT IFNULL(SUM(totalbiaya),0) FROM billing WHERE no_rawat=:norawat AND status=''Resep Pulang''');
    JSONBiaya.Add('obat', FormatFloat('0.00', vObat));

    // Tambahkan gabungan struktur rincian biaya ke output utama
    JSONRes.Add('rincian_biaya_riil', JSONBiaya);

    // =================================================================
    // KOMPRESI GZIP RESPONSE OUTPUT
    // =================================================================
    vJSONMentah := JSONRes.AsJSON;
    if Pos('gzip', LowerCase(ARequest.Headers.Values['Accept-Encoding'])) > 0 then
    begin
      vJSONKompres := uhandlerapi.KompresStringKeGZip(vJSONMentah);
      AResponse.Headers.Add('Content-Encoding', 'deflate');
      AResponse.Headers.Add('X-Compression', 'GZip-Active');
      AResponse.Send(vJSONKompres, 'application/json; charset=utf-8', 200);
    end
    else
    begin
      AResponse.Send(vJSONMentah, 'application/json; charset=utf-8', 200);
    end;

  except
    on E: Exception do
    begin
      AResponse.SendFmt('{"status": "error", "message": "Gagal memproses detail INACBG: %s"}', [E.Message], 'application/json', 500);
    end;
  end;

  vQMain.Free;
  vQSub.Free;
  JSONRes.Free;
end;

end.
