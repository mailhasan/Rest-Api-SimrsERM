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
    function AmbilTindakanRawatJalan(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
    function AmbilTindakanRawatInap(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
    function AmbilSOAPRawatJalan(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
    function AmbilSOAPRawatInap(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
    function AmbilRiwayatObat(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
    function AmbilResepPulang(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
	function AmbilRiwayatLaboratorium(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
	function AmbilRiwayatRadiologi(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
	function AmbilRiwayatDiagnosa(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
	function AmbilRiwayatProsedur(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
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
// HELPER DATA TINDAKAN RAJAL (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilTindakanRawatJalan(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
var
  vQ: TZQuery;
  vArrDetail: TJSONArray;
  vObjDetail: TJSONObject;
  vGrandTotal: Double;
  vTotalItem: Integer;
begin
  Result := TJSONObject.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;

  vGrandTotal := 0;
  vTotalItem := 0;
  vArrDetail := TJSONArray.Create;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT r.tgl_perawatan, ');
    vQ.SQL.Add('       DATE_FORMAT(r.tgl_perawatan, "%Y-%m-%d") AS tgl_format, ');
    vQ.SQL.Add('       COALESCE(jp.nm_perawatan, "Tindakan") AS nm_perawatan, ');
    vQ.SQL.Add('       r.biaya_rawat, ');
    vQ.SQL.Add('       COALESCE(r.stts_bayar, "Belum") AS stts_bayar ');
    vQ.SQL.Add('FROM ( ');
    vQ.SQL.Add('    SELECT tgl_perawatan, kd_jenis_prw, biaya_rawat, stts_bayar FROM rawat_jl_dr WHERE TRIM(no_rawat) = :no_rawat ');
    vQ.SQL.Add('    UNION ALL ');
    vQ.SQL.Add('    SELECT tgl_perawatan, kd_jenis_prw, biaya_rawat, stts_bayar FROM rawat_jl_pr WHERE TRIM(no_rawat) = :no_rawat ');
    vQ.SQL.Add('    UNION ALL ');
    vQ.SQL.Add('    SELECT tgl_perawatan, kd_jenis_prw, biaya_rawat, stts_bayar FROM rawat_jl_drpr WHERE TRIM(no_rawat) = :no_rawat ');
    vQ.SQL.Add(') r ');
    vQ.SQL.Add('LEFT JOIN jns_perawatan jp ON r.kd_jenis_prw = jp.kd_jenis_prw ');
    vQ.SQL.Add('ORDER BY r.tgl_perawatan DESC');

    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      Inc(vTotalItem);
      vGrandTotal := vGrandTotal + vQ.FieldByName('biaya_rawat').AsFloat;

      vObjDetail := TJSONObject.Create;
      vObjDetail.Add('tanggal', vQ.FieldByName('tgl_format').AsString);
      vObjDetail.Add('nama_tindakan', Trim(vQ.FieldByName('nm_perawatan').AsString));
      vObjDetail.Add('biaya', FormatFloat('0.00', vQ.FieldByName('biaya_rawat').AsFloat));
      vObjDetail.Add('status_bayar', Trim(vQ.FieldByName('stts_bayar').AsString));

      vArrDetail.Add(vObjDetail);
      vQ.Next;
    end;

    // Masukkan data rangkuman & list detail ke object return utama
    Result.Add('has_data', vTotalItem > 0);
    Result.Add('jumlah_tindakan', vTotalItem);
    Result.Add('grand_total_biaya', FormatFloat('0.00', vGrandTotal));
    Result.Add('detail_tindakan', vArrDetail);

  finally
    vQ.Free;
  end;
end;

// =================================================================
// PERBAIKAN: HELPER DATA TINDAKAN RANAP (NAMA TINDAKAN SESUAI)
// =================================================================
function TRouteRiwayatPasien.AmbilTindakanRawatInap(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
var
  vQ: TZQuery;
  vArrDetail: TJSONArray;
  vObjDetail: TJSONObject;
  vGrandTotal: Double;
  vTotalItem: Integer;
begin
  Result := TJSONObject.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;

  vGrandTotal := 0;
  vTotalItem := 0;
  vArrDetail := TJSONArray.Create;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT r.tgl_perawatan, ');
    vQ.SQL.Add('       DATE_FORMAT(r.tgl_perawatan, "%Y-%m-%d") AS tgl_format, ');
    // Jika nm_perawatan kosong, gunakan fallback kategori teks agar tidak null
    vQ.SQL.Add('       COALESCE(jp.nm_perawatan, r.kategori_tindakan) AS nm_perawatan, ');
    vQ.SQL.Add('       r.biaya_rawat, ');
    vQ.SQL.Add('       r.kategori_tindakan ');
    vQ.SQL.Add('FROM ( ');
    // PASTIKAN kd_jenis_prw IKUT DIAMBIL PADA MASING-MASING SELEKSI UNTUK RELASI JOIN
    vQ.SQL.Add('    SELECT tgl_perawatan, kd_jenis_prw, biaya_rawat, "Tindakan Dokter" AS kategori_tindakan FROM rawat_inap_dr WHERE TRIM(no_rawat) = :no_rawat ');
    vQ.SQL.Add('    UNION ALL ');
    vQ.SQL.Add('    SELECT tgl_perawatan, kd_jenis_prw, biaya_rawat, "Tindakan Perawat" AS kategori_tindakan FROM rawat_inap_pr WHERE TRIM(no_rawat) = :no_rawat ');
    vQ.SQL.Add('    UNION ALL ');
    vQ.SQL.Add('    SELECT tgl_perawatan, kd_jenis_prw, biaya_rawat, "Tindakan Dokter & Perawat" AS kategori_tindakan FROM rawat_inap_drpr WHERE TRIM(no_rawat) = :no_rawat ');
    vQ.SQL.Add(') r '); // Catatan: pastikan saat copy ke IDE, karakter '重' ini dibersihkan menjadi ') r '
    vQ.SQL.Add('LEFT JOIN jns_perawatan_inap jp ON r.kd_jenis_prw = jp.kd_jenis_prw ');
    vQ.SQL.Add('ORDER BY r.tgl_perawatan DESC');

    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      Inc(vTotalItem);
      vGrandTotal := vGrandTotal + vQ.FieldByName('biaya_rawat').AsFloat;

      vObjDetail := TJSONObject.Create;
      vObjDetail.Add('tanggal', vQ.FieldByName('tgl_format').AsString);
      vObjDetail.Add('nama_tindakan', Trim(vQ.FieldByName('nm_perawatan').AsString));
      vObjDetail.Add('kategori', vQ.FieldByName('kategori_tindakan').AsString);
      vObjDetail.Add('biaya', FormatFloat('0.00', vQ.FieldByName('biaya_rawat').AsFloat));

      vArrDetail.Add(vObjDetail);
      vQ.Next;
    end;

    Result.Add('has_data', vTotalItem > 0);
    Result.Add('jumlah_tindakan', vTotalItem);
    Result.Add('grand_total_biaya', FormatFloat('0.00', vGrandTotal));
    Result.Add('detail_tindakan', vArrDetail);

  finally
    vQ.Free;
  end;
end;

// =================================================================
// HELPER DATA PEMBERIAN OBAT (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilRiwayatObat(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
var
  vQ: TZQuery;
  vArrDetail: TJSONArray;
  vObjDetail: TJSONObject;
  vGrandTotalObat: Double;
  vTotalItem: Integer;
begin
  Result := TJSONObject.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;
  
  vGrandTotalObat := 0;
  vTotalItem := 0;
  vArrDetail := TJSONArray.Create;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT dpo.tgl_perawatan, dpo.jam, ');
    vQ.SQL.Add('       db.nama_brng AS nama_obat, dpo.kode_brng, ');
    vQ.SQL.Add('       dpo.jml AS jumlah, dpo.biaya_obat, dpo.embalase, ');
    vQ.SQL.Add('       dpo.tuslah, dpo.total, dpo.status AS status_perawatan, ');
    vQ.SQL.Add('       b.nm_bangsal AS nama_bangsal, dpo.no_batch, dpo.no_faktur ');
    vQ.SQL.Add('FROM detail_pemberian_obat dpo ');
    vQ.SQL.Add('LEFT JOIN databarang db ON dpo.kode_brng = db.kode_brng ');
    vQ.SQL.Add('LEFT JOIN bangsal b ON dpo.kd_bangsal = b.kd_bangsal ');
    vQ.SQL.Add('WHERE TRIM(dpo.no_rawat) = :no_rawat ');
    vQ.SQL.Add('ORDER BY dpo.tgl_perawatan DESC, dpo.jam DESC');
    
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      Inc(vTotalItem);
      vGrandTotalObat := vGrandTotalObat + vQ.FieldByName('total').AsFloat;

      vObjDetail := TJSONObject.Create;
      vObjDetail.Add('tanggal', vQ.FieldByName('tgl_perawatan').AsString);
      vObjDetail.Add('jam', vQ.FieldByName('jam').AsString);
      vObjDetail.Add('kode_obat', vQ.FieldByName('kode_brng').AsString);
      vObjDetail.Add('nama_obat', Trim(vQ.FieldByName('nama_obat').AsString));
      vObjDetail.Add('jumlah', vQ.FieldByName('jumlah').AsInteger);
      vObjDetail.Add('biaya_satuan', FormatFloat('0.00', vQ.FieldByName('biaya_obat').AsFloat));
      vObjDetail.Add('embalase', FormatFloat('0.00', vQ.FieldByName('embalase').AsFloat));
      vObjDetail.Add('tuslah', FormatFloat('0.00', vQ.FieldByName('tuslah').AsFloat));
      vObjDetail.Add('total_harga_item', FormatFloat('0.00', vQ.FieldByName('total').AsFloat));
      vObjDetail.Add('status_perawatan', vQ.FieldByName('status_perawatan').AsString);
      vObjDetail.Add('depo_bangsal', Trim(vQ.FieldByName('nama_bangsal').AsString));
      vObjDetail.Add('no_batch', vQ.FieldByName('no_batch').AsString);
      vObjDetail.Add('no_faktur', vQ.FieldByName('no_faktur').AsString);
      
      vArrDetail.Add(vObjDetail);
      vQ.Next;
    end;

    // Rangkuman utama pemberian obat
    Result.Add('has_data', vTotalItem > 0);
    Result.Add('total_item_obat', vTotalItem);
    Result.Add('grand_total_biaya_obat', FormatFloat('0.00', vGrandTotalObat));
    Result.Add('detail_obat', vArrDetail);

  finally
    vQ.Free;
  end;
end;

// =================================================================
// HELPER DATA RESEP PULANG (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilResepPulang(gZConn: TZConnection; const ANoRawat: string): TJSONObject;
var
  vQ: TZQuery;
  vArrDetail: TJSONArray;
  vObjDetail: TJSONObject;
  vGrandTotalResep: Double;
  vTotalItem: Integer;
begin
  Result := TJSONObject.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;
  
  vGrandTotalResep := 0;
  vTotalItem := 0;
  vArrDetail := TJSONArray.Create;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT rp.tanggal, rp.jam, rp.kode_brng, ');
    vQ.SQL.Add('       db.nama_brng AS nama_obat, rp.jml_barang AS jumlah, ');
    vQ.SQL.Add('       rp.harga AS harga_satuan, rp.total, rp.dosis AS aturan_pakai, ');
    vQ.SQL.Add('       b.nm_bangsal AS nama_bangsal, rp.no_batch, rp.no_faktur ');
    vQ.SQL.Add('FROM resep_pulang rp ');
    vQ.SQL.Add('LEFT JOIN databarang db ON rp.kode_brng = db.kode_brng ');
    vQ.SQL.Add('LEFT JOIN bangsal b ON rp.kd_bangsal = b.kd_bangsal ');
    vQ.SQL.Add('WHERE TRIM(rp.no_rawat) = :no_rawat ');
    vQ.SQL.Add('ORDER BY rp.tanggal DESC, rp.jam DESC');
    
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      Inc(vTotalItem);
      vGrandTotalResep := vGrandTotalResep + vQ.FieldByName('total').AsFloat;

      vObjDetail := TJSONObject.Create;
      vObjDetail.Add('tanggal', vQ.FieldByName('tanggal').AsString);
      vObjDetail.Add('jam', vQ.FieldByName('jam').AsString);
      vObjDetail.Add('kode_obat', vQ.FieldByName('kode_brng').AsString);
      vObjDetail.Add('nama_obat', Trim(vQ.FieldByName('nama_obat').AsString));
      vObjDetail.Add('jumlah', vQ.FieldByName('jumlah').AsInteger);
      vObjDetail.Add('harga_satuan', FormatFloat('0.00', vQ.FieldByName('harga_satuan').AsFloat));
      vObjDetail.Add('total_harga_item', FormatFloat('0.00', vQ.FieldByName('total').AsFloat));
      vObjDetail.Add('aturan_pakai', Trim(vQ.FieldByName('aturan_pakai').AsString));
      vObjDetail.Add('depo_bangsal', Trim(vQ.FieldByName('nama_bangsal').AsString));
      vObjDetail.Add('no_batch', vQ.FieldByName('no_batch').AsString);
      vObjDetail.Add('no_faktur', vQ.FieldByName('no_faktur').AsString);
      
      vArrDetail.Add(vObjDetail);
      vQ.Next;
    end;

    // Masukkan data rangkuman ke object return utama
    Result.Add('has_data', vTotalItem > 0);
    Result.Add('total_item_resep', vTotalItem);
    Result.Add('grand_total_biaya_resep', FormatFloat('0.00', vGrandTotalResep));
    Result.Add('detail_resep', vArrDetail);

  finally
    vQ.Free;
  end;
end;

// =================================================================
// PERBAIKAN: HELPER DATA PEMERIKSAAN LAB (FIX PARAMETER HASIL KOSONG)
// =================================================================
function TRouteRiwayatPasien.AmbilRiwayatLaboratorium(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var
  vQHeader, vQDetail: TZQuery;
  vObjHeader, vObjDetail: TJSONObject;
  vArrDetail: TJSONArray;
  vKdJenisPrw: string;
  vTgl: TDateTime;
  vJam: TDateTime;
begin
  Result := TJSONArray.Create;
  
  vQHeader := TZQuery.Create(nil);
  vQHeader.Connection := gZConn;
  
  vQDetail := TZQuery.Create(nil);
  vQDetail.Connection := gZConn;

  try
    // 1. Ambil Semua Paket Pemeriksaan Lab Pasien (Header)
    vQHeader.SQL.Clear;
    vQHeader.SQL.Add('SELECT pl.tgl_periksa, pl.jam, jpl.nm_perawatan AS nama_pemeriksaan, ');
    vQHeader.SQL.Add('       pl.kd_jenis_prw, pl.biaya AS total_biaya, pl.status AS status_rawat, ');
    vQHeader.SQL.Add('       pl.kategori AS kategori_lab, dk.nm_dokter AS dokter_pemeriksa, ');
    vQHeader.SQL.Add('       dk_perujuk.nm_dokter AS dokter_perujuk ');
    vQHeader.SQL.Add('FROM periksa_lab pl ');
    vQHeader.SQL.Add('LEFT JOIN jns_perawatan_lab jpl ON pl.kd_jenis_prw = jpl.kd_jenis_prw ');
    vQHeader.SQL.Add('LEFT JOIN dokter dk ON pl.kd_dokter = dk.kd_dokter ');
    vQHeader.SQL.Add('LEFT JOIN dokter dk_perujuk ON pl.dokter_perujuk = dk_perujuk.kd_dokter ');
    vQHeader.SQL.Add('WHERE TRIM(pl.no_rawat) = :no_rawat ');
    vQHeader.SQL.Add('ORDER BY pl.tgl_periksa DESC, pl.jam DESC');
    
    vQHeader.ParamByName('no_rawat').AsString := ANoRawat;
    vQHeader.Open;

    while not vQHeader.EOF do
    begin
      // Ambil nilai asli tipe TDateTime untuk parameter query detail
      vKdJenisPrw := vQHeader.FieldByName('kd_jenis_prw').AsString;
      vTgl        := vQHeader.FieldByName('tgl_periksa').AsDateTime;
      vJam        := vQHeader.FieldByName('jam').AsDateTime;

      vObjHeader := TJSONObject.Create;
      vObjHeader.Add('tanggal', FormatDateTime('yyyy-MM-dd', vTgl));
      vObjHeader.Add('jam', FormatDateTime('hh:nn:ss', vJam));
      vObjHeader.Add('kode_pemeriksaan', Trim(vKdJenisPrw));
      vObjHeader.Add('nama_pemeriksaan', Trim(vQHeader.FieldByName('nama_pemeriksaan').AsString));
      vObjHeader.Add('kategori_lab', vQHeader.FieldByName('kategori_lab').AsString);
      vObjHeader.Add('status_rawat', vQHeader.FieldByName('status_rawat').AsString);
      vObjHeader.Add('dokter_pemeriksa', Trim(vQHeader.FieldByName('dokter_pemeriksa').AsString));
      vObjHeader.Add('dokter_perujuk', Trim(vQHeader.FieldByName('dokter_perujuk').AsString));
      vObjHeader.Add('total_biaya_paket', FormatFloat('0.00', vQHeader.FieldByName('total_biaya').AsFloat));

      // 2. Sub-Query Detail menggunakan tipe data aslinya & TRIM pada kd_jenis_prw
      vArrDetail := TJSONArray.Create;
      vQDetail.SQL.Clear;
      vQDetail.SQL.Add('SELECT tl.Pemeriksaan AS nama_template, tl.satuan, dpl.nilai AS hasil, ');
      vQDetail.SQL.Add('       dpl.nilai_rujukan, dpl.keterangan AS status_hasil ');
      vQDetail.SQL.Add('FROM detail_periksa_lab dpl ');
      vQDetail.SQL.Add('LEFT JOIN template_laboratorium tl ON dpl.id_template = tl.id_template ');
      vQDetail.SQL.Add('WHERE TRIM(dpl.no_rawat) = :no_rawat ');
      vQDetail.SQL.Add('  AND TRIM(dpl.kd_jenis_prw) = :kd_jenis_prw ');
      vQDetail.SQL.Add('  AND dpl.tgl_periksa = :tgl_periksa ');
      vQDetail.SQL.Add('  AND dpl.jam = :jam ');
      vQDetail.SQL.Add('ORDER BY tl.urut ASC');
      
      vQDetail.ParamByName('no_rawat').AsString := ANoRawat;
      vQDetail.ParamByName('kd_jenis_prw').AsString := Trim(vKdJenisPrw);
      vQDetail.ParamByName('tgl_periksa').AsDate := vTgl;  // Menggunakan AsDate
      vQDetail.ParamByName('jam').AsTime := vJam;          // Menggunakan AsTime
      vQDetail.Open;

      while not vQDetail.EOF do
      begin
        vObjDetail := TJSONObject.Create;
        vObjDetail.Add('parameter_uji', Trim(vQDetail.FieldByName('nama_template').AsString));
        vObjDetail.Add('hasil', Trim(vQDetail.FieldByName('hasil').AsString));
        vObjDetail.Add('satuan', Trim(vQDetail.FieldByName('satuan').AsString));
        vObjDetail.Add('nilai_rujukan', Trim(vQDetail.FieldByName('nilai_rujukan').AsString));
        vObjDetail.Add('status_kondisi', Trim(vQDetail.FieldByName('status_hasil').AsString));
        
        vArrDetail.Add(vObjDetail);
        vQDetail.Next;
      end;
      vQDetail.Close;

      vObjHeader.Add('parameter_hasil', vArrDetail);
      Result.Add(vObjHeader);
      
      vQHeader.Next;
    end;

  finally
    vQHeader.Free;
    vQDetail.Free;
  end;
end;

// =================================================================
// HELPER DATA RADIOLOGI (HEADER BILLING + EKSPERTISE + PACS IMAGES)
// =================================================================
function TRouteRiwayatPasien.AmbilRiwayatRadiologi(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var
  vQHeader, vQHasil, vQPacs: TZQuery;
  vObjHeader, vObjPacs: TJSONObject;
  vArrPacs: TJSONArray;
  vKdJenisPrw: string;
  vTgl, vJam: TDateTime;
  vNarasiHasil: string;
begin
  Result := TJSONArray.Create;
  
  vQHeader := TZQuery.Create(nil); vQHeader.Connection := gZConn;
  vQHasil  := TZQuery.Create(nil); vQHasil.Connection := gZConn;
  vQPacs   := TZQuery.Create(nil); vQPacs.Connection := gZConn;

  try
    // 1. Ambil Pemeriksaan Radiologi Utama (Header Billing & Faktor Eksposure)
    vQHeader.SQL.Clear;
    vQHeader.SQL.Add('SELECT pr.tgl_periksa, pr.jam, jpr.nm_perawatan AS nama_pemeriksaan, ');
    vQHeader.SQL.Add('       pr.kd_jenis_prw, pr.biaya AS total_biaya, pr.status AS status_rawat, ');
    vQHeader.SQL.Add('       pr.proyeksi, pr.kV, pr.mAS, pr.FFD, pr.BSF, pr.inak, ');
    vQHeader.SQL.Add('       pr.jml_penyinaran, pr.dosis, dk.nm_dokter AS dokter_pemeriksa, ');
    vQHeader.SQL.Add('       dk_perujuk.nm_dokter AS dokter_perujuk ');
    vQHeader.SQL.Add('FROM periksa_radiologi pr ');
    vQHeader.SQL.Add('LEFT JOIN jns_perawatan_radiologi jpr ON pr.kd_jenis_prw = jpr.kd_jenis_prw ');
    vQHeader.SQL.Add('LEFT JOIN dokter dk ON pr.kd_dokter = dk.kd_dokter ');
    vQHeader.SQL.Add('LEFT JOIN dokter dk_perujuk ON pr.dokter_perujuk = dk_perujuk.kd_dokter ');
    vQHeader.SQL.Add('WHERE TRIM(pr.no_rawat) = :no_rawat ');
    vQHeader.SQL.Add('ORDER BY pr.tgl_periksa DESC, pr.jam DESC');
    
    vQHeader.ParamByName('no_rawat').AsString := ANoRawat;
    vQHeader.Open;

    while not vQHeader.EOF do
    begin
      vKdJenisPrw := vQHeader.FieldByName('kd_jenis_prw').AsString;
      vTgl        := vQHeader.FieldByName('tgl_periksa').AsDateTime;
      vJam        := vQHeader.FieldByName('jam').AsDateTime;

      vObjHeader := TJSONObject.Create;
      vObjHeader.Add('tanggal', FormatDateTime('yyyy-MM-dd', vTgl));
      vObjHeader.Add('jam', FormatDateTime('hh:nn:ss', vJam));
      vObjHeader.Add('kode_pemeriksaan', Trim(vKdJenisPrw));
      vObjHeader.Add('nama_pemeriksaan', Trim(vQHeader.FieldByName('nama_pemeriksaan').AsString));
      vObjHeader.Add('status_rawat', vQHeader.FieldByName('status_rawat').AsString);
      vObjHeader.Add('dokter_pemeriksa', Trim(vQHeader.FieldByName('dokter_pemeriksa').AsString));
      vObjHeader.Add('dokter_perujuk', Trim(vQHeader.FieldByName('dokter_perujuk').AsString));
      vObjHeader.Add('total_biaya_paket', FormatFloat('0.00', vQHeader.FieldByName('total_biaya').AsFloat));
      
      // Teknis Alat & Proyeksi
      vObjHeader.Add('proyeksi', Trim(vQHeader.FieldByName('proyeksi').AsString));
      vObjHeader.Add('kv', Trim(vQHeader.FieldByName('kV').AsString));
      vObjHeader.Add('mas', Trim(vQHeader.FieldByName('mAS').AsString));
      vObjHeader.Add('ffd', Trim(vQHeader.FieldByName('FFD').AsString));
      vObjHeader.Add('dosis_radiasi', Trim(vQHeader.FieldByName('dosis').AsString));

      // 2. Sub-Query Narasi Hasil Ekspertise (Filter: no_rawat, tgl, jam)
      vNarasiHasil := '';
      vQHasil.SQL.Clear;
      vQHasil.SQL.Add('SELECT hr.hasil FROM hasil_radiologi hr ');
      vQHasil.SQL.Add('WHERE TRIM(hr.no_rawat) = :no_rawat ');
      vQHasil.SQL.Add('  AND hr.tgl_periksa = :tgl_periksa ');
      vQHasil.SQL.Add('  AND hr.jam = :jam ');
      
      vQHasil.ParamByName('no_rawat').AsString := ANoRawat;
      vQHasil.ParamByName('tgl_periksa').AsDate := vTgl;
      vQHasil.ParamByName('jam').AsTime := vJam;
      vQHasil.Open;
      
      if not vQHasil.IsEmpty then
        vNarasiHasil := Trim(vQHasil.FieldByName('hasil').AsString);
      vQHasil.Close;
      
      vObjHeader.Add('hasil_ekspertise', vNarasiHasil);

      // 3. Sub-Query Mengambil Daftar Gambar PACS DICOM (Filter: no_rawat, tgl, jam)
      vArrPacs := TJSONArray.Create;
      vQPacs.SQL.Clear;
      vQPacs.SQL.Add('SELECT grp.lokasi_gambar FROM gambar_radiologi_pacs grp ');
      vQPacs.SQL.Add('WHERE TRIM(grp.no_rawat) = :no_rawat ');
      vQPacs.SQL.Add('  AND grp.tgl_periksa = :tgl_periksa ');
      vQPacs.SQL.Add('  AND grp.jam = :jam ');
      
      vQPacs.ParamByName('no_rawat').AsString := ANoRawat;
      vQPacs.ParamByName('tgl_periksa').AsDate := vTgl;
      vQPacs.ParamByName('jam').AsTime := vJam;
      vQPacs.Open;

      while not vQPacs.EOF do
      begin
        vObjPacs := TJSONObject.Create;
        vObjPacs.Add('url_gambar', Trim(vQPacs.FieldByName('lokasi_gambar').AsString));
        vArrPacs.Add(vObjPacs);
        vQPacs.Next;
      end;
      vQPacs.Close;

      vObjHeader.Add('gambar_pacs', vArrPacs);
      Result.Add(vObjHeader);
      
      vQHeader.Next;
    end;

  finally
    vQHeader.Free;
    vQHasil.Free;
    vQPacs.Free;
  end;
end;

// =================================================================
// HELPER DATA SOAP RAWAT JALAN (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilSOAPRawatJalan(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var
  vQ: TZQuery;
  vObjSOAP, vObjTTV: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT pr.tgl_perawatan, pr.jam_rawat, ');
    vQ.SQL.Add('       pr.keluhan, pr.pemeriksaan, pr.penilaian, pr.rtl, ');
    vQ.SQL.Add('       pr.instruksi, pr.evaluasi, ');
    vQ.SQL.Add('       pr.tensi, pr.nadi, pr.respirasi, pr.suhu_tubuh, pr.spo2, ');
    vQ.SQL.Add('       pr.kesadaran, pg.nama ');
    vQ.SQL.Add('FROM pemeriksaan_ralan pr ');
    vQ.SQL.Add('LEFT JOIN pegawai pg ON pr.nip = pg.nik ');
    vQ.SQL.Add('WHERE TRIM(pr.no_rawat) = :no_rawat ');
    vQ.SQL.Add('ORDER BY pr.tgl_perawatan DESC, pr.jam_rawat DESC');

    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      vObjSOAP := TJSONObject.Create;
      vObjSOAP.Add('tanggal_pemeriksaan', vQ.FieldByName('tgl_perawatan').AsString);
      vObjSOAP.Add('jam_pemeriksaan', vQ.FieldByName('jam_rawat').AsString);
      vObjSOAP.Add('petugas_medis', Trim(vQ.FieldByName('nama').AsString));

      // Data Inti SOAP
      vObjSOAP.Add('s_subjektif', Trim(vQ.FieldByName('keluhan').AsString));
      vObjSOAP.Add('o_objektif', Trim(vQ.FieldByName('pemeriksaan').AsString));
      vObjSOAP.Add('a_assessment', Trim(vQ.FieldByName('penilaian').AsString));
      vObjSOAP.Add('p_plan', Trim(vQ.FieldByName('rtl').AsString));
      vObjSOAP.Add('instruksi', Trim(vQ.FieldByName('instruksi').AsString));
      vObjSOAP.Add('evaluasi', Trim(vQ.FieldByName('evaluasi').AsString));

      // Objek Bersarang untuk Tanda Vital (TTV)
      vObjTTV := TJSONObject.Create;
      vObjTTV.Add('tekanan_darah', Trim(vQ.FieldByName('tensi').AsString));
      vObjTTV.Add('nadi', Trim(vQ.FieldByName('nadi').AsString));
      vObjTTV.Add('respirasi', Trim(vQ.FieldByName('respirasi').AsString));
      vObjTTV.Add('suhu_tubuh', Trim(vQ.FieldByName('suhu_tubuh').AsString));
      vObjTTV.Add('spo2', Trim(vQ.FieldByName('spo2').AsString));
      vObjTTV.Add('kesadaran', Trim(vQ.FieldByName('kesadaran').AsString));
      vObjSOAP.Add('tanda_vital', vObjTTV);

      Result.Add(vObjSOAP);
      vQ.Next;
    end;

  finally
    vQ.Free;
  end;
end;

// =================================================================
// HELPER DATA DIAGNOSA / ICD-10 (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilRiwayatDiagnosa(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var
  vQ: TZQuery;
  vObjDetail: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT dp.prioritas, ');
    vQ.SQL.Add('       CASE WHEN dp.prioritas = 1 THEN "DIAGNOSA UTAMA" ELSE "DIAGNOSA SEKUNDER" END AS jenis, ');
    vQ.SQL.Add('       p.nm_penyakit AS diagnosis, p.kd_penyakit AS kode_icd, ');
    vQ.SQL.Add('       dp.status_penyakit AS status_penyakit, ');
    vQ.SQL.Add('       CASE WHEN dp.status_penyakit = "Baru" THEN "Baru terdiagnosis" ');
    vQ.SQL.Add('            WHEN dp.status_penyakit = "Lama" THEN "Sudah pernah terdiagnosis sebelumnya" END AS keterangan_status, ');
    vQ.SQL.Add('       p.status AS klasifikasi_menular, kp.nm_kategori AS kategori_penyakit ');
    vQ.SQL.Add('FROM diagnosa_pasien dp ');
    vQ.SQL.Add('LEFT JOIN penyakit p ON dp.kd_penyakit = p.kd_penyakit ');
    vQ.SQL.Add('LEFT JOIN kategori_penyakit kp ON p.kd_ktg = kp.kd_ktg ');
    vQ.SQL.Add('WHERE TRIM(dp.no_rawat) = :no_rawat ');
    vQ.SQL.Add('ORDER BY dp.prioritas ASC');
    
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      vObjDetail := TJSONObject.Create;
      vObjDetail.Add('prioritas', vQ.FieldByName('prioritas').AsInteger);
      vObjDetail.Add('jenis_diagnosa', vQ.FieldByName('jenis').AsString);
      vObjDetail.Add('kode_icd10', Trim(vQ.FieldByName('kode_icd').AsString));
      vObjDetail.Add('nama_penyakit', Trim(vQ.FieldByName('diagnosis').AsString));
      vObjDetail.Add('status_kasus', vQ.FieldByName('status_penyakit').AsString); // Baru / Lama
      vObjDetail.Add('keterangan_status', vQ.FieldByName('keterangan_status').AsString);
      vObjDetail.Add('klasifikasi_menular', Trim(vQ.FieldByName('klasifikasi_menular').AsString));
      vObjDetail.Add('kategori_penyakit', Trim(vQ.FieldByName('kategori_penyakit').AsString));
      
      Result.Add(vObjDetail);
      vQ.Next;
    end;

  finally
    vQ.Free;
  end;
end;

// =================================================================
// HELPER DATA SOAP RAWAT INAP (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilSOAPRawatInap(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var
  vQ: TZQuery;
  vObjSOAP, vObjTTV: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT pr.tgl_perawatan, pr.jam_rawat, ');
    vQ.SQL.Add('       pr.keluhan, pr.pemeriksaan, pr.penilaian, pr.rtl, ');
    vQ.SQL.Add('       pr.instruksi, pr.evaluasi, ');
    vQ.SQL.Add('       pr.tensi, pr.nadi, pr.respirasi, pr.suhu_tubuh, pr.spo2, ');
    vQ.SQL.Add('       pr.kesadaran, pg.nama ');
    vQ.SQL.Add('FROM pemeriksaan_ranap pr ');
    vQ.SQL.Add('LEFT JOIN pegawai pg ON pr.nip = pg.nik ');
    vQ.SQL.Add('WHERE TRIM(pr.no_rawat) = :no_rawat ');
    vQ.SQL.Add('ORDER BY pr.tgl_perawatan DESC, pr.jam_rawat DESC');

    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      vObjSOAP := TJSONObject.Create;
      vObjSOAP.Add('tanggal_pemeriksaan', vQ.FieldByName('tgl_perawatan').AsString);
      vObjSOAP.Add('jam_pemeriksaan', vQ.FieldByName('jam_rawat').AsString);
      vObjSOAP.Add('petugas_medis', Trim(vQ.FieldByName('nama').AsString));

      // Data Inti SOAPE Ranap
      vObjSOAP.Add('s_subjektif', Trim(vQ.FieldByName('keluhan').AsString));
      vObjSOAP.Add('o_objektif', Trim(vQ.FieldByName('pemeriksaan').AsString));
      vObjSOAP.Add('a_assessment', Trim(vQ.FieldByName('penilaian').AsString));
      vObjSOAP.Add('p_plan', Trim(vQ.FieldByName('rtl').AsString));
      vObjSOAP.Add('instruksi', Trim(vQ.FieldByName('instruksi').AsString));
      vObjSOAP.Add('evaluasi', Trim(vQ.FieldByName('evaluasi').AsString));

      // Sub-Object Tanda-Tanda Vital (TTV)
      vObjTTV := TJSONObject.Create;
      vObjTTV.Add('tekanan_darah', Trim(vQ.FieldByName('tensi').AsString));
      vObjTTV.Add('nadi', Trim(vQ.FieldByName('nadi').AsString));
      vObjTTV.Add('respirasi', Trim(vQ.FieldByName('respirasi').AsString));
      vObjTTV.Add('suhu_tubuh', Trim(vQ.FieldByName('suhu_tubuh').AsString));
      vObjTTV.Add('spo2', Trim(vQ.FieldByName('spo2').AsString));
      vObjTTV.Add('kesadaran', Trim(vQ.FieldByName('kesadaran').AsString));
      vObjSOAP.Add('tanda_vital', vObjTTV);

      Result.Add(vObjSOAP);
      vQ.Next;
    end;

  finally
    vQ.Free;
  end;
end;

// =================================================================
// HELPER DATA PROSEDUR / ICD-9 CM (KONVERSI LOGIKA LAZARUS KE JSON)
// =================================================================
function TRouteRiwayatPasien.AmbilRiwayatProsedur(gZConn: TZConnection; const ANoRawat: string): TJSONArray;
var
  vQ: TZQuery;
  vObjDetail: TJSONObject;
begin
  Result := TJSONArray.Create;
  vQ := TZQuery.Create(nil);
  vQ.Connection := gZConn;

  try
    vQ.SQL.Clear;
    vQ.SQL.Add('SELECT pp.kode, i.deskripsi_panjang AS nama_prosedur, ');
    vQ.SQL.Add('       i.deskripsi_pendek AS prosedur_singkat, pp.status AS status_rawat, ');
    vQ.SQL.Add('       pp.prioritas, ');
    vQ.SQL.Add('       CASE WHEN pp.prioritas = 1 THEN "Prosedur Utama" ELSE "Prosedur Tambahan" END AS jenis_prosedur ');
    vQ.SQL.Add('FROM prosedur_pasien pp ');
    vQ.SQL.Add('LEFT JOIN icd9 i ON pp.kode = i.kode ');
    vQ.SQL.Add('WHERE TRIM(pp.no_rawat) = :no_rawat ');
    vQ.SQL.Add('ORDER BY pp.prioritas ASC');
    
    vQ.ParamByName('no_rawat').AsString := ANoRawat;
    vQ.Open;

    while not vQ.EOF do
    begin
      vObjDetail := TJSONObject.Create;
      vObjDetail.Add('prioritas', vQ.FieldByName('prioritas').AsInteger);
      vObjDetail.Add('jenis_prosedur', vQ.FieldByName('jenis_prosedur').AsString);
      vObjDetail.Add('kode_icd9', Trim(vQ.FieldByName('kode').AsString));
      vObjDetail.Add('nama_prosedur', Trim(vQ.FieldByName('nama_prosedur').AsString));
      vObjDetail.Add('prosedur_singkat', Trim(vQ.FieldByName('prosedur_singkat').AsString));
      vObjDetail.Add('status_rawat', vQ.FieldByName('status_rawat').AsString); // Ralan / Ranap
      
      Result.Add(vObjDetail);
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
	
	// SUNTIK DATA DIAGNOSA / ICD-10 DI SINI (TAMBAHKAN BARIS INI)
    JSONKunjungan.Add('diagnosa_icd10', AmbilRiwayatDiagnosa(uhandlerapi.gZConn, vCurrentNoRawat));
	  
	// SUNTIK DATA PROSEDUR / ICD-9 CM DI SINI (TAMBAHKAN BARIS INI)
    JSONKunjungan.Add('prosedur_icd9', AmbilRiwayatProsedur(uhandlerapi.gZConn, vCurrentNoRawat));
	
	 // SUNTIK DATA SOAP RAWAT JALAN & rawat inap DI SINI
    JSONKunjungan.Add('soap_rajal', AmbilSOAPRawatJalan(uhandlerapi.gZConn, vCurrentNoRawat));
    JSONKunjungan.Add('soap_ranap', AmbilSOAPRawatInap(uhandlerapi.gZConn, vCurrentNoRawat));

    // SUNTIK DATA TINDAKAN RAJAL & Ranap DI SINI
    JSONKunjungan.Add('tindakan_rajal', AmbilTindakanRawatJalan(uhandlerapi.gZConn, vCurrentNoRawat));

    JSONKunjungan.Add('tindakan_ranap', AmbilTindakanRawatInap(uhandlerapi.gZConn, vCurrentNoRawat));
	
	// SUNTIK DATA PEMERIKSAAN LABORATORIUM DI SINI (TAMBAHKAN BARIS INI)
      JSONKunjungan.Add('laboratorium', AmbilRiwayatLaboratorium(gZConn, vCurrentNoRawat));
	
	// SUNTIK DATA PEMERIKSAAN RADIOLOGI DI SINI (TAMBAHKAN BARIS INI)
      JSONKunjungan.Add('radiologi', AmbilRiwayatRadiologi(uhandlerapi.gZConn, vCurrentNoRawat));	
	
    // SUNTIK DATA PEMBERIAN OBAT DI SINI (TAMBAHKAN BARIS INI)
    JSONKunjungan.Add('pemberian_obat', AmbilRiwayatObat(uhandlerapi.gZConn, vCurrentNoRawat));
	// SUNTIK DATA RESEP PULANG DI SINI (TAMBAHKAN BARIS INI)
    JSONKunjungan.Add('resep_pulang', AmbilResepPulang(uhandlerapi.gZConn, vCurrentNoRawat));
   

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
