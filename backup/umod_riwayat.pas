unit umod_riwayat;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter, BrookHTTPRequest, BrookHTTPResponse,
  BrookUtility, fpjson, jsonparser;

type
  { TRouteRiwayatPasien }
  TRouteRiwayatPasien = class(TBrookURLRoute)
  private
    function AmbilDataSOAP(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
    function AmbilDataTindakan(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
    function AmbilDataObat(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
    function AmbilDataLab(gZConn: TZConnection; const ANoRawat: string): TJSONArray;

    function AmbilDataTriaseIGD(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
    function AmbilAsesmenKeperawatanIGD(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
    function AmbilPenilaianMedisIGD(gZConn: TZConnection; const ANoRawat: string): TJSONArray;

  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

uses uhandlerapi;

procedure TRouteRiwayatPasien.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];
  Pattern := '/api/v1/riwayat';
end;

// =================================================================
// HELPER SUB-QUERIES (LOGIKA PENGAMBILAN KOMPONEN RME KHANZA)
// =================================================================

function TRouteRiwayatPasien.AmbilDataSOAP(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
var vQ: TZQuery;
begin
  Result := TJSONObject.Create;
  vQ := TZQuery.Create(nil);
  try
    vQ.Connection := gZConn;
    vQ.SQL.Text := 'SELECT keluhan, pemeriksaan, penilaian, tindak_lanjut FROM pemeriksaan_ranap WHERE no_rawat=:norawat ' +
                   'UNION SELECT keluhan, pemeriksaan, penilaian, tindak_lanjut FROM pemeriksaan_ralan WHERE no_rawat=:norawat LIMIT 1';
    vQ.ParamByName('norawat').AsString := ANoRawat;
    vQ.Open;
    if not vQ.IsEmpty then
    begin
      Result.Add('subyektif', vQ.FieldByName('keluhan').AsString);
      Result.Add('obyektif', vQ.FieldByName('pemeriksaan').AsString);
      Result.Add('asesmen', vQ.FieldByName('penilaian').AsString);
      Result.Add('plan', vQ.FieldByName('tindak_lanjut').AsString);
    end;
  finally vQ.Free; end;
end;

function TRouteRiwayatPasien.AmbilDataTindakan(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var vQ: TZQuery; vObj: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  try
    vQ.Connection := gZConn;
    vQ.SQL.Text := 'SELECT t.nama_prw FROM jns_perawatan t INNER JOIN rawat_jl_dr r ON t.kd_perawatan=r.kd_perawatan WHERE r.no_rawat=:norawat ' +
                   'UNION SELECT t.nama_prw FROM jns_perawatan_inap t INNER JOIN rawat_inap_dr r ON t.kd_perawatan=r.kd_perawatan WHERE r.no_rawat=:norawat';
    vQ.ParamByName('norawat').AsString := ANoRawat;
    vQ.Open;
    while not vQ.EOF do
    begin
      vObj := TJSONObject.Create;
      vObj.Add('nama_tindakan', vQ.Fields[0].AsString);
      Result.Add(vObj);
      vQ.Next;
    end;
  finally vQ.Free; end;
end;

function TRouteRiwayatPasien.AmbilDataObat(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var vQ: TZQuery; vObj: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  try
    vQ.Connection := gZConn;
    vQ.SQL.Text := 'SELECT d.nama_brng, d.kode_sat, d.kode_satbesar FROM databarang d INNER JOIN detail_pemberian_obat o ON d.kode_brng=o.kode_brng WHERE o.no_rawat=:norawat';
    vQ.ParamByName('norawat').AsString := ANoRawat;
    vQ.Open;
    while not vQ.EOF do
    begin
      vObj := TJSONObject.Create;
      vObj.Add('nama_obat', vQ.FieldByName('nama_brng').AsString);
      vObj.Add('satuan', vQ.FieldByName('kode_sat').AsString);
      Result.Add(vObj);
      vQ.Next;
    end;
  finally vQ.Free; end;
end;

function TRouteRiwayatPasien.AmbilDataLab(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var vQ: TZQuery; vObj: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  try
    vQ.Connection := gZConn;
    vQ.SQL.Text := 'SELECT p.periksa, d.nilai, d.nilai_rujukan, d.keterangan FROM detail_periksa_lab d INNER JOIN jns_perawatan_lab p ON d.kd_jenis_prw=p.kd_jenis_prw WHERE d.no_rawat=:norawat';
    vQ.ParamByName('norawat').AsString := ANoRawat;
    vQ.Open;
    while not vQ.EOF do
    begin
      vObj := TJSONObject.Create;
      vObj.Add('pemeriksaan', vQ.FieldByName('periksa').AsString);
      vObj.Add('hasil', vQ.FieldByName('nilai').AsString);
      vObj.Add('rujukan', vQ.FieldByName('nilai_rujukan').AsString);
      vObj.Add('keterangan', vQ.FieldByName('keterangan').AsString);
      Result.Add(vObj);
      vQ.Next;
    end;
  finally vQ.Free; end;
end;

// =================================================================
// HELPER TRIASE IGD HANDLER (KONVERSI LOGIKA LAZARUS KE JSON API)
// =================================================================
function TRouteRiwayatPasien.AmbilDataTriaseIGD(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
var
  vQ: TZQuery;
  vObjItem: TJSONObject;
  vArrSkala: TJSONArray;
  vHasData: Boolean;
  vSkalaIdx: Integer;
begin
  Result := TJSONObject.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;
  vHasData := False;

  try
    // 1. HEADER TRIASE & TTV
    vQ.SQL.Text :=
      'SELECT dt.tgl_kunjungan, dt.cara_masuk, dt.alat_transportasi, dt.alasan_kedatangan, ' +
      '       dt.keterangan_kedatangan, dt.tekanan_darah, dt.nadi, dt.pernapasan, dt.suhu, ' +
      '       dt.saturasi_o2, dt.nyeri, mk.macam_kasus ' +
      'FROM data_triase_igd dt ' +
      'LEFT JOIN master_triase_macam_kasus mk ON dt.kode_kasus = mk.kode_kasus ' +
      'WHERE TRIM(dt.no_rawat) = TRIM(:no_rawat)';
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    if not vQ.IsEmpty then
    begin
      vHasData := True;
      Result.Add('tgl_kunjungan', vQ.FieldByName('tgl_kunjungan').AsString);
      Result.Add('cara_masuk', vQ.FieldByName('cara_masuk').AsString);
      Result.Add('alat_transportasi', vQ.FieldByName('alat_transportasi').AsString);
      Result.Add('alasan_kedatangan', vQ.FieldByName('alasan_kedatangan').AsString);
      Result.Add('keterangan_kedatangan', vQ.FieldByName('keterangan_kedatangan').AsString);
      Result.Add('macam_kasus', vQ.FieldByName('macam_kasus').AsString);

      // TTV
      Result.Add('tekanan_darah', vQ.FieldByName('tekanan_darah').AsString);
      Result.Add('nadi', vQ.FieldByName('nadi').AsString);
      Result.Add('pernapasan', vQ.FieldByName('pernapasan').AsString);
      Result.Add('suhu', vQ.FieldByName('suhu').AsString);
      Result.Add('saturasi_o2', vQ.FieldByName('saturasi_o2').AsString);
      Result.Add('skala_nyeri', vQ.FieldByName('nyeri').AsString);
    end;
    vQ.Close;

    // 2. TRIASE PRIMER (ZONA MERAH)
    vQ.SQL.Text :=
      'SELECT p.tanggaltriase, p.keluhan_utama, p.kebutuhan_khusus, p.catatan, p.plan, pg.nama ' +
      'FROM data_triase_igdprimer p LEFT JOIN pegawai pg ON p.nik = pg.nik WHERE p.no_rawat = :no_rawat';
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;
    if not vQ.IsEmpty then
    begin
      vHasData := True;
      vObjItem := TJSONObject.Create;
      vObjItem.Add('tanggal_triase', vQ.FieldByName('tanggaltriase').AsString);
      vObjItem.Add('petugas', vQ.FieldByName('nama').AsString);
      vObjItem.Add('keluhan_utama', vQ.FieldByName('keluhan_utama').AsString);
      vObjItem.Add('kebutuhan_khusus', vQ.FieldByName('kebutuhan_khusus').AsString);
      vObjItem.Add('catatan', vQ.FieldByName('catatan').AsString);
      vObjItem.Add('plan', vQ.FieldByName('plan').AsString);
      Result.Add('triase_primer', vObjItem);
    end else begin
      Result.Add('triase_primer', TJSONNull.Create);
    end;
    vQ.Close;

    // 3. TRIASE SEKUNDER (ZONA KUNING/HIJAU)
    vQ.SQL.Text :=
      'SELECT s.tanggaltriase, s.anamnesa_singkat, s.catatan, s.plan, pg.nama ' +
      'FROM data_triase_igdsekunder s LEFT JOIN pegawai pg ON s.nik = pg.nik WHERE s.no_rawat = :no_rawat';
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;
    if not vQ.IsEmpty then
    begin
      vHasData := True;
      vObjItem := TJSONObject.Create;
      vObjItem.Add('tanggal_triase', vQ.FieldByName('tanggaltriase').AsString);
      vObjItem.Add('petugas', vQ.FieldByName('nama').AsString);
      vObjItem.Add('anamnesa_singkat', vQ.FieldByName('anamnesa_singkat').AsString);
      vObjItem.Add('catatan', vQ.FieldByName('catatan').AsString);
      vObjItem.Add('plan', vQ.FieldByName('plan').AsString);
      Result.Add('triase_sekunder', vObjItem);
    end else begin
      Result.Add('triase_sekunder', TJSONNull.Create);
    end;
    vQ.Close;

    // 4. AKUMULASI PENILAIAN SKALA TRIASE (SKALA 1 - 5)
    vArrSkala := TJSONArray.Create;
    for vSkalaIdx := 1 to 5 do
    begin
      vQ.SQL.Text := Format(
        'SELECT m.pengkajian_skala%d AS penilaian ' +
        'FROM data_triase_igddetail_skala%d d ' +
        'JOIN master_triase_skala%d m ON d.kode_skala%d = m.kode_skala%d ' +
        'WHERE d.no_rawat = :no_rawat', [vSkalaIdx, vSkalaIdx, vSkalaIdx, vSkalaIdx, vSkalaIdx]
      );
      vQ.ParamByName('no_rawat').AsString := ANoRawat;
      vQ.Open;
      while not vQ.EOF do
      begin
        vHasData := True;
        vObjItem := TJSONObject.Create;
        vObjItem.Add('skala_tingkat', vSkalaIdx);
        vObjItem.Add('pengkajian', vQ.FieldByName('penilaian').AsString);
        vArrSkala.Add(vObjItem);
        vQ.Next;
      end;
      vQ.Close;
    end;
    Result.Add('penilaian_skala', vArrSkala);

    // Indikator jika ternyata rekam medis ini tidak melewati IGD/Triase
    Result.Add('has_data', vHasData);

  finally
    vQ.Free;
  end;
end;

// =================================================================
// HELPER ASESMEN KEPERAWATAN IGD (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilAsesmenKeperawatanIGD(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
var
  vQ: TZQuery;
  vArrMasalah, vArrRencana: TJSONArray;
  vObjFisik, vObjNyeri, vObjKehamilan: TJSONObject;
  vHasData: Boolean;
begin
  Result := TJSONObject.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;
  vHasData := False;

  try
    // 1. DATA UTAMA & PEMERIKSAAN FISIK & NYERI PQRST
    vQ.SQL.Text :=
      'SELECT p.*, pg.nama AS perawat FROM penilaian_awal_keperawatan_igd p ' +
      'LEFT JOIN petugas pg ON p.nip = pg.nip WHERE p.no_rawat = :no_rawat LIMIT 1';
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    if not vQ.IsEmpty then
    begin
      vHasData := True;
      Result.Add('tanggal_penilaian', vQ.FieldByName('tanggal').AsString);
      Result.Add('perawat', vQ.FieldByName('perawat').AsString);
      Result.Add('informasi', vQ.FieldByName('informasi').AsString);
      Result.Add('keluhan_utama', vQ.FieldByName('keluhan_utama').AsString);
      Result.Add('rpd', vQ.FieldByName('rpd').AsString);
      Result.Add('rpo', vQ.FieldByName('rpo').AsString);
      Result.Add('intoksikasi', vQ.FieldByName('intoksikasi').AsString);
      Result.Add('hasil_penilaian', vQ.FieldByName('hasil').AsString);
      Result.Add('rencana_umum', vQ.FieldByName('rencana').AsString);

      // Status Kehamilan (Kondisional)
      if vQ.FieldByName('status_kehamilan').AsString <> '' then
      begin
        vObjKehamilan := TJSONObject.Create;
        vObjKehamilan.Add('status_kehamilan', vQ.FieldByName('status_kehamilan').AsString);
        vObjKehamilan.Add('gravida', vQ.FieldByName('gravida').AsString);
        vObjKehamilan.Add('para', vQ.FieldByName('para').AsString);
        vObjKehamilan.Add('abortus', vQ.FieldByName('abortus').AsString);
        vObjKehamilan.Add('hpht', vQ.FieldByName('hpht').AsString);
        Result.Add('status_obgyn', vObjKehamilan);
      end else begin
        Result.Add('status_obgyn', TJSONNull.Create);
      end;

      // Pemeriksaan Fisik Terstruktur
      vObjFisik := TJSONObject.Create;
      vObjFisik.Add('tekanan_darah', vQ.FieldByName('tekanan').AsString);
      vObjFisik.Add('pupil', vQ.FieldByName('pupil').AsString);
      vObjFisik.Add('neurosensorik', vQ.FieldByName('neurosensorik').AsString);
      vObjFisik.Add('integumen', vQ.FieldByName('integumen').AsString);
      vObjFisik.Add('turgor', vQ.FieldByName('turgor').AsString);
      vObjFisik.Add('edema', vQ.FieldByName('edema').AsString);
      vObjFisik.Add('mukosa', vQ.FieldByName('mukosa').AsString);
      vObjFisik.Add('perdarahan', vQ.FieldByName('perdarahan').AsString);
      vObjFisik.Add('jumlah_perdarahan', vQ.FieldByName('jumlah_perdarahan').AsString);
      vObjFisik.Add('warna_perdarahan', vQ.FieldByName('warna_perdarahan').AsString);
      vObjFisik.Add('psikologis', vQ.FieldByName('psikologis').AsString);
      vObjFisik.Add('jiwa', vQ.FieldByName('jiwa').AsString);
      vObjFisik.Add('perilaku', vQ.FieldByName('perilaku').AsString);
      Result.Add('pemeriksaan_fisik', vObjFisik);

      // Asesmen Nyeri PQRST
      vObjNyeri := TJSONObject.Create;
      vObjNyeri.Add('nyeri', vQ.FieldByName('nyeri').AsString);
      vObjNyeri.Add('p_provokes', vQ.FieldByName('provokes').AsString);
      vObjNyeri.Add('p_keterangan', vQ.FieldByName('ket_provokes').AsString);
      vObjNyeri.Add('q_quality', vQ.FieldByName('quality').AsString);
      vObjNyeri.Add('q_keterangan', vQ.FieldByName('ket_quality').AsString);
      vObjNyeri.Add('r_lokasi', vQ.FieldByName('lokasi').AsString);
      vObjNyeri.Add('r_menyebar', vQ.FieldByName('menyebar').AsString);
      vObjNyeri.Add('s_skala', vQ.FieldByName('skala_nyeri').AsString);
      vObjNyeri.Add('t_durasi', vQ.FieldByName('durasi').AsString);
      vObjNyeri.Add('t_nyeri_hilang_jika', vQ.FieldByName('nyeri_hilang').AsString);
      Result.Add('asesmen_nyeri_pqrst', vObjNyeri);
    end;
    vQ.Close;

    // 2. DAFTAR MASALAH KEPERAWATAN
    vArrMasalah := TJSONArray.Create;
    vQ.SQL.Text :=
      'SELECT m.kode_masalah, m.nama_masalah FROM penilaian_awal_keperawatan_igd_masalah pm ' +
      'JOIN master_masalah_keperawatan_igd m ON pm.kode_masalah = m.kode_masalah ' +
      'WHERE pm.no_rawat = :no_rawat ORDER BY m.nama_masalah';
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;
    while not vQ.EOF do
    begin
      vHasData := True;
      vArrMasalah.Add(TJSONObject.Create([
        'kode_masalah', vQ.FieldByName('kode_masalah').AsString,
        'nama_masalah', vQ.FieldByName('nama_masalah').AsString
      ]));
      vQ.Next;
    end;
    Result.Add('daftar_masalah', vArrMasalah);
    vQ.Close;

    // 3. DAFTAR RENCANA KEPERAWATAN
    vArrRencana := TJSONArray.Create;
    vQ.SQL.Text :=
      'SELECT r.kode_rencana, mr.rencana_keperawatan FROM penilaian_awal_keperawatan_ralan_rencana_igd r ' +
      'JOIN master_rencana_keperawatan_igd mr ON r.kode_rencana = mr.kode_rencana ' +
      'WHERE r.no_rawat = :no_rawat ORDER BY r.kode_rencana';
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;
    while not vQ.EOF do
    begin
      vHasData := True;
      vArrRencana.Add(TJSONObject.Create([
        'kode_rencana', vQ.FieldByName('kode_rencana').AsString,
        'rencana_keperawatan', vQ.FieldByName('rencana_keperawatan').AsString
      ]));
      vQ.Next;
    end;
    Result.Add('daftar_rencana', vArrRencana);

    Result.Add('has_data', vHasData);

  finally
    vQ.Free;
  end;
end;

// =================================================================
// HELPER PENILAIAN MEDIS IGD DOKTER (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilPenilaianMedisIGD(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var
  vQ: TZQuery;
  vObjPenilaian, vObjAnamnesis, vObjRiwayat, vObjVital, vObjFisik, vObjPenunjang: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;

  try
    vQ.SQL.Text :=
      'SELECT pmi.*, d.nm_dokter FROM penilaian_medis_igd pmi ' +
      'LEFT JOIN dokter d ON pmi.kd_dokter = d.kd_dokter ' +
      'WHERE TRIM(pmi.no_rawat) = :no_rawat ORDER BY pmi.tanggal DESC';
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      vObjPenilaian := TJSONObject.Create;
      vObjPenilaian.Add('tanggal_penilaian', vQ.FieldByName('tanggal').AsString);
      vObjPenilaian.Add('dokter', vQ.FieldByName('nm_dokter').AsString);
      vObjPenilaian.Add('alergi', Trim(vQ.FieldByName('alergi').AsString));
      vObjPenilaian.Add('diagnosis_teks', Trim(vQ.FieldByName('diagnosis').AsString));
      vObjPenilaian.Add('tata_laksana', Trim(vQ.FieldByName('tata').AsString));

      // 1. BLOCK ANAMNESIS
      vObjAnamnesis := TJSONObject.Create;
      vObjAnamnesis.Add('jenis_anamnesis', Trim(vQ.FieldByName('anamnesis').AsString));
      vObjAnamnesis.Add('hubungan_informan', Trim(vQ.FieldByName('hubungan').AsString));
      vObjAnamnesis.Add('keluhan_utama', Trim(vQ.FieldByName('keluhan_utama').AsString));
      vObjPenilaian.Add('anamnesis', vObjAnamnesis);

      // 2. BLOCK RIWAYAT PENYAKIT
      vObjRiwayat := TJSONObject.Create;
      vObjRiwayat.Add('rps', Trim(vQ.FieldByName('rps').AsString));
      vObjRiwayat.Add('rpd', Trim(vQ.FieldByName('rpd').AsString));
      vObjRiwayat.Add('rpk', Trim(vQ.FieldByName('rpk').AsString));
      vObjRiwayat.Add('rpo', Trim(vQ.FieldByName('rpo').AsString));
      vObjPenilaian.Add('riwayat_penyakit', vObjRiwayat);

      // 3. BLOCK STATUS PRAESENS / TANDA VITAL & ANTROPOMETRI
      vObjVital := TJSONObject.Create;
      vObjVital.Add('keadaan_umum', Trim(vQ.FieldByName('keadaan').AsString));
      vObjVital.Add('kesadaran', Trim(vQ.FieldByName('kesadaran').AsString));
      vObjVital.Add('gcs', Trim(vQ.FieldByName('gcs').AsString));
      vObjVital.Add('tekanan_darah', Trim(vQ.FieldByName('td').AsString));
      vObjVital.Add('nadi', Trim(vQ.FieldByName('nadi').AsString));
      vObjVital.Add('rr', Trim(vQ.FieldByName('rr').AsString));
      vObjVital.Add('suhu', Trim(vQ.FieldByName('suhu').AsString));
      vObjVital.Add('spo2', Trim(vQ.FieldByName('spo').AsString));
      vObjVital.Add('berat_badan', Trim(vQ.FieldByName('bb').AsString));
      vObjVital.Add('tinggi_badan', Trim(vQ.FieldByName('tb').AsString));
      vObjPenilaian.Add('tanda_vital', vObjVital);

      // 4. BLOCK PEMERIKSAAN FISIK SYSTEMIK
      vObjFisik := TJSONObject.Create;
      vObjFisik.Add('kepala', Trim(vQ.FieldByName('kepala').AsString));
      vObjFisik.Add('mata', Trim(vQ.FieldByName('mata').AsString));
      vObjFisik.Add('gigi_mulut', Trim(vQ.FieldByName('gigi').AsString));
      vObjFisik.Add('leher', Trim(vQ.FieldByName('leher').AsString));
      vObjFisik.Add('thoraks', Trim(vQ.FieldByName('thoraks').AsString));
      vObjFisik.Add('abdomen', Trim(vQ.FieldByName('abdomen').AsString));
      vObjFisik.Add('genital', Trim(vQ.FieldByName('genital').AsString));
      vObjFisik.Add('ekstremitas', Trim(vQ.FieldByName('ekstremitas').AsString));
      vObjFisik.Add('keterangan_fisik_lain', Trim(vQ.FieldByName('ket_fisik').AsString));
      vObjFisik.Add('keterangan_lokalis', Trim(vQ.FieldByName('ket_lokalis').AsString));
      vObjPenilaian.Add('pemeriksaan_fisik', vObjFisik);

      // 5. BLOCK ASESMEN PENUNJANG DI IGD
      vObjPenunjang := TJSONObject.Create;
      vObjPenunjang.Add('ekg', Trim(vQ.FieldByName('ekg').AsString));
      vObjPenunjang.Add('radiologi', Trim(vQ.FieldByName('rad').AsString));
      vObjPenunjang.Add('laboratorium', Trim(vQ.FieldByName('lab').AsString));
      vObjPenilaian.Add('pemeriksaan_penunjang_igd', vObjPenunjang);

      Result.Add(vObjPenilaian);
      vQ.Next;
    end;

  finally
    vQ.Free;
  end;
end;


// =================================================================
// MAIN REQUEST HANDLER
// =================================================================

procedure TRouteRiwayatPasien.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vQMain: TZQuery;
  vNoRM, vNoRawat, vTglAwal, vTglAkhir, vJSONMentah, vJSONKompres: string;
  JSONRes, JSONKunjungan: TJSONObject;
  JSONArrayKunjungan: TJSONArray;
  vCurrentNoRawat: string;
begin
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  // Tangkap parameter filter dari query string URL
  vNoRM     := Trim(ARequest.Params.Values['norm']);
  vNoRawat  := Trim(ARequest.Params.Values['no_rawat']);
  vTglAwal  := Trim(ARequest.Params.Values['tgl_awal']);
  vTglAkhir := Trim(ARequest.Params.Values['tgl_akhir']);

  // Validasi input minimal harus ada no_rawat atau norm
  if (vNoRM = '') and (vNoRawat = '') then
  begin
    AResponse.Send('{"status": "error", "message": "Wajib sertakan parameter: norm ATAU no_rawat"}', 'application/json', 400);
    Exit;
  end;

  vQMain := TZQuery.Create(nil);
  vQMain.Connection := uhandlerapi.gZConn;

  JSONRes := TJSONObject.Create;
  JSONArrayKunjungan := TJSONArray.Create;

  try
    vQMain.SQL.Clear;
    vQMain.SQL.Add('SELECT rp.no_rawat, rp.tgl_registrasi, rp.jam_reg, ');
    vQMain.SQL.Add('       rp.no_rkm_medis, ps.nm_pasien, rp.status_lanjut, ');
    vQMain.SQL.Add('       rp.stts, rp.status_bayar, pl.nm_poli, dk.nm_dokter, ');
    vQMain.SQL.Add('       bg.nm_bangsal, kmr.kd_kamar, kmr.kelas ');
    vQMain.SQL.Add('FROM reg_periksa rp ');
    vQMain.SQL.Add('LEFT JOIN pasien ps ON rp.no_rkm_medis = ps.no_rkm_medis ');
    vQMain.SQL.Add('LEFT JOIN poliklinik pl ON rp.kd_poli = pl.kd_poli ');
    vQMain.SQL.Add('LEFT JOIN dokter dk ON rp.kd_dokter = dk.kd_dokter ');
    vQMain.SQL.Add('LEFT JOIN kamar_inap ki ON rp.no_rawat = ki.no_rawat ');
    vQMain.SQL.Add('LEFT JOIN kamar kmr ON ki.kd_kamar = kmr.kd_kamar ');
    vQMain.SQL.Add('LEFT JOIN bangsal bg ON kmr.kd_bangsal = bg.kd_bangsal ');

    // PENYUSUNAN STRUKTUR WHERE SECARA DINAMIS
    if vNoRawat <> '' then
    begin
      vQMain.SQL.Add('WHERE rp.no_rawat = :no_rawat ');
    end
    else
    begin
      vQMain.SQL.Add('WHERE rp.status_lanjut IN (''Ralan'',''Ranap'') ');
      vQMain.SQL.Add('AND rp.no_rkm_medis = :no_rm ');

      // Filter Tanggal Opsional
      if (vTglAwal <> '') and (vTglAkhir <> '') then
        vQMain.SQL.Add('AND rp.tgl_registrasi BETWEEN :tgl_awal AND :tgl_akhir ');
    end;

    vQMain.SQL.Add('ORDER BY rp.tgl_registrasi DESC, rp.jam_reg DESC, rp.no_rawat DESC ');
    vQMain.SQL.Add('LIMIT 10');

    // BINDING PARAMETER KEDALAM SQL
    if vNoRawat <> '' then
    begin
      vQMain.ParamByName('no_rawat').AsString := vNoRawat;
    end
    else
    begin
      vQMain.ParamByName('no_rm').AsString := vNoRM;
      if (vTglAwal <> '') and (vTglAkhir <> '') then
      begin
        vQMain.ParamByName('tgl_awal').AsString := vTglAwal;
        vQMain.ParamByName('tgl_akhir').AsString := vTglAkhir;
      end;
    end;

    vQMain.Open;

    if vQMain.IsEmpty then
    begin
      AResponse.Send('{"status": "success", "message": "Riwayat kunjungan kosong", "data": []}', 'application/json', 200);
      Exit;
    end;

    // Set Manifest Identitas Pasien (Diambil dari baris pertama hasil query)
    JSONRes.Add('status', 'success');
    JSONRes.Add('no_rkm_medis', vQMain.FieldByName('no_rkm_medis').AsString);
    JSONRes.Add('nm_pasien', vQMain.FieldByName('nm_pasien').AsString);

    // Iterasi Data Kunjungan
    while not vQMain.EOF do
    begin
      JSONKunjungan := TJSONObject.Create;
      //JSONKunjungan.Add('no_rawat', vQMain.FieldByName('no_rawat').AsString);
      vCurrentNoRawat := Trim(vQMain.FieldByName('no_rawat').AsString);
      JSONKunjungan.Add('tgl_registrasi', vQMain.FieldByName('tgl_registrasi').AsString);
      JSONKunjungan.Add('jam_reg', vQMain.FieldByName('jam_reg').AsString);
      JSONKunjungan.Add('status_lanjut', vQMain.FieldByName('status_lanjut').AsString);
      JSONKunjungan.Add('status_periksa', vQMain.FieldByName('stts').AsString);
      JSONKunjungan.Add('status_bayar', vQMain.FieldByName('status_bayar').AsString);
      JSONKunjungan.Add('poliklinik', vQMain.FieldByName('nm_poli').AsString);
      JSONKunjungan.Add('dokter', vQMain.FieldByName('nm_dokter').AsString);
      JSONKunjungan.Add('no_rawat', vCurrentNoRawat);

      // Data Kamar Inap (Akan otomatis bernilai null/kosong jika pasien Ralan)
      if vQMain.FieldByName('status_lanjut').AsString = 'Ranap' then
      begin
        JSONKunjungan.Add('bangsal', vQMain.FieldByName('nm_bangsal').AsString);
        JSONKunjungan.Add('kd_kamar', vQMain.FieldByName('kd_kamar').AsString);
        JSONKunjungan.Add('kelas', vQMain.FieldByName('kelas').AsString);
      end
      else
      begin
        JSONKunjungan.Add('bangsal', '-');
        JSONKunjungan.Add('kd_kamar', '-');
        JSONKunjungan.Add('kelas', '-');
      end;

      JSONArrayKunjungan.Add(JSONKunjungan);
      vQMain.Next;
    end;

    // SUNTIK DATA TRIASE IGD DI SINI
    JSONKunjungan.Add('triase_igd', AmbilDataTriaseIGD(uhandlerapi.gZConn, vCurrentNoRawat));
    // SUNTIK DATA ASESMEN KEPERAWATAN IGD DI SINI
    JSONKunjungan.Add('asesmen_keperawatan_igd', AmbilAsesmenKeperawatanIGD(uhandlerapi.gZConn, vCurrentNoRawat));

    // SUNTIK DATA ASESMEN MEDIS IGD DOKTER DI SINI
      JSONKunjungan.Add('penilaian_medis_igd', AmbilPenilaianMedisIGD(uhandlerapi.gZConn, vCurrentNoRawat));

    JSONRes.Add('kunjungan', JSONArrayKunjungan);

    // Bungkus dengan kompresi GZip
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
      AResponse.SendFmt('{"status": "error", "message": "Gagal mengambil data riwayat: %s"}', [E.Message], 'application/json', 500);
  end;

  vQMain.Free;
  JSONRes.Free;
end;

end.
