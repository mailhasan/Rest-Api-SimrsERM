unit umod_ranap_pasien;

{$MODE DELPHI} // Menggunakan mode Delphi agar selaras dengan pola uhandlerapi

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest,BrookUtility, BrookHTTPResponse, fpjson, jsonparser;

type
  { TRouteRanapPasienSearch }
  TRouteRanapPasienSearch = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TRouteRanapPasienSearch }
uses uhandlerapi;

procedure TRouteRanapPasienSearch.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];
  Pattern := '/ranap/pasien'; // Endpoint URL: /api/ranap/pasien
end;

procedure TRouteRanapPasienSearch.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vNoRM, vNamaPasien, vNamaDokter, vKodeKamar, vStatusPulang: string;
  vTglMasukAwal, vTglMasukAkhir, vTglKeluarAwal, vTglKeluarAkhir: string;
  vFilterSQL: TStringList;
  vQuery: TZQuery;
  vJSONArray: TJSONArray;
  vJSONItem: TJSONObject;
begin
  // Validasi Token Keamanan via Satpam Global uhandlerapi
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  // =================================================================
  // REVISI CORE: UBAH DARI ARequest.Params MENJADI ARequest.QueryFields
  // =================================================================
  vNoRM          := Trim(ARequest.QueryFields.Values['norm']);
  vNamaPasien    := Trim(ARequest.QueryFields.Values['nama_pasien']);
  vNamaDokter    := Trim(ARequest.QueryFields.Values['nama_dokter']);
  vKodeKamar     := Trim(ARequest.QueryFields.Values['kode_kamar']); 
  vStatusPulang  := Trim(ARequest.QueryFields.Values['status_pulang']);
  
  // Parameter Tanggal Query Fields
  vTglMasukAwal  := Trim(ARequest.QueryFields.Values['tgl_masuk_awal']);
  vTglMasukAkhir := Trim(ARequest.QueryFields.Values['tgl_masuk_akhir']);
  vTglKeluarAwal := Trim(ARequest.QueryFields.Values['tgl_keluar_awal']);
  vTglKeluarAkhir:= Trim(ARequest.QueryFields.Values['tgl_keluar_akhir']);
  // =================================================================

  vQuery := TZQuery.Create(nil);
  vQuery.Connection := uhandlerapi.gZConn;
  vFilterSQL := TStringList.Create;
  vJSONArray := TJSONArray.Create;

  try
    with vFilterSQL do
    begin
      Add('SELECT reg_periksa.no_rawat, pasien.no_rkm_medis, pasien.nm_pasien, pasien.alamat,');
      Add('       reg_periksa.p_jawab, reg_periksa.hubunganpj, penjab.png_jawab, kamar.kd_kamar,');
      Add('       kamar.trf_kamar, bangsal.nm_bangsal, kamar_inap.diagnosa_awal, kamar_inap.diagnosa_akhir,');
      Add('       kamar_inap.tgl_masuk, kamar_inap.jam_masuk, kamar_inap.tgl_keluar, kamar_inap.jam_keluar,');
      Add('       kamar_inap.ttl_biaya, kamar_inap.stts_pulang, kamar_inap.lama, dokter.nm_dokter,');
      Add('       reg_periksa.status_bayar, pasien.agama');
      Add('FROM kamar_inap');
      Add('JOIN reg_periksa ON kamar_inap.no_rawat = reg_periksa.no_rawat');
      Add('JOIN pasien ON reg_periksa.no_rkm_medis = pasien.no_rkm_medis');
      Add('JOIN penjab ON reg_periksa.kd_pj = penjab.kd_pj');
      Add('JOIN kamar ON kamar_inap.kd_kamar = kamar.kd_kamar');
      Add('JOIN bangsal ON kamar.kd_bangsal = bangsal.kd_bangsal');
      Add('JOIN dokter ON reg_periksa.kd_dokter = dokter.kd_dokter');
      Add('WHERE 1=1');

      // Penerapan Kondisi Filter Dinamis
      if vNoRM <> '' then Add('AND pasien.no_rkm_medis LIKE :norm');
      if vNamaPasien <> '' then Add('AND pasien.nm_pasien LIKE :nmpasien');
      if vNamaDokter <> '' then Add('AND dokter.nm_dokter LIKE :nmdokter');
      if vKodeKamar <> '' then Add('AND bangsal.nm_bangsal LIKE :kdkamar');
      if vStatusPulang <> '' then Add('AND kamar_inap.stts_pulang LIKE :stts');

      if (vTglMasukAwal <> '') and (vTglMasukAkhir <> '') then
        Add('AND kamar_inap.tgl_masuk BETWEEN :tglmasuk1 AND :tglmasuk2');

      if (vTglKeluarAwal <> '') and (vTglKeluarAkhir <> '') then
        Add('AND kamar_inap.tgl_keluar BETWEEN :tglkeluar1 AND :tglkeluar2');

      // Default filter jika semua parameter kosong: Tampilkan pasien aktif (belum pulang)
      if (vNoRM = '') and (vNamaPasien = '') and (vNamaDokter = '') and
         (vKodeKamar = '') and (vStatusPulang = '') and
         (vTglMasukAwal = '') and (vTglKeluarAwal = '') then
      begin
        Add('AND (kamar_inap.stts_pulang = "")');
      end;

      Add('ORDER BY dokter.nm_dokter, pasien.nm_pasien');
    end;

    vQuery.SQL.Text := vFilterSQL.Text;

    // Binding Parameter ke SQL Engine Zeos
    if vNoRM <> '' then vQuery.ParamByName('norm').AsString := '%' + vNoRM + '%';
    if vNamaPasien <> '' then vQuery.ParamByName('nmpasien').AsString := '%' + vNamaPasien + '%';
    if vNamaDokter <> '' then vQuery.ParamByName('nmdokter').AsString := '%' + vNamaDokter + '%';
    if vKodeKamar <> '' then vQuery.ParamByName('kdkamar').AsString := '%' + vKodeKamar + '%';
    if vStatusPulang <> '' then vQuery.ParamByName('stts').AsString := '%' + vStatusPulang + '%';

    if (vTglMasukAwal <> '') and (vTglMasukAkhir <> '') then
    begin
      vQuery.ParamByName('tglmasuk1').AsString := vTglMasukAwal;
      vQuery.ParamByName('tglmasuk2').AsString := vTglMasukAkhir;
    end;

    if (vTglKeluarAwal <> '') and (vTglKeluarAkhir <> '') then
    begin
      vQuery.ParamByName('tglkeluar1').AsString := vTglKeluarAwal;
      vQuery.ParamByName('tglkeluar2').AsString := vTglKeluarAkhir;
    end;

    vQuery.Open;

    // Transformasi baris data MySQL ke format JSON Array
    while not vQuery.EOF do
    begin
      vJSONItem := TJSONObject.Create;
      vJSONItem.Add('no_rawat', Trim(vQuery.FieldByName('no_rawat').AsString));
      vJSONItem.Add('no_rkm_medis', Trim(vQuery.FieldByName('no_rkm_medis').AsString));
      vJSONItem.Add('nm_pasien', Trim(vQuery.FieldByName('nm_pasien').AsString));
      vJSONItem.Add('alamat', Trim(vQuery.FieldByName('alamat').AsString));
      vJSONItem.Add('p_jawab', Trim(vQuery.FieldByName('p_jawab').AsString));
      vJSONItem.Add('hubunganpj', Trim(vQuery.FieldByName('hubunganpj').AsString));
      vJSONItem.Add('png_jawab', Trim(vQuery.FieldByName('png_jawab').AsString));
      vJSONItem.Add('kd_kamar', Trim(vQuery.FieldByName('kd_kamar').AsString));
      vJSONItem.Add('trf_kamar', FormatFloat('0.00', vQuery.FieldByName('trf_kamar').AsFloat));
      vJSONItem.Add('nm_bangsal', Trim(vQuery.FieldByName('nm_bangsal').AsString));
      vJSONItem.Add('diagnosa_awal', Trim(vQuery.FieldByName('diagnosa_awal').AsString));
      vJSONItem.Add('diagnosa_akhir', Trim(vQuery.FieldByName('diagnosa_akhir').AsString));
      vJSONItem.Add('tgl_masuk', vQuery.FieldByName('tgl_masuk').AsString);
      vJSONItem.Add('jam_masuk', vQuery.FieldByName('jam_masuk').AsString);

      if vQuery.FieldByName('tgl_keluar').IsNull then
        vJSONItem.Add('tgl_keluar', '-')
      else
        vJSONItem.Add('tgl_keluar', vQuery.FieldByName('tgl_keluar').AsString);

      if vQuery.FieldByName('jam_keluar').IsNull then
        vJSONItem.Add('jam_keluar', '-')
      else
        vJSONItem.Add('jam_keluar', vQuery.FieldByName('jam_keluar').AsString);

      vJSONItem.Add('ttl_biaya', FormatFloat('0.00', vQuery.FieldByName('ttl_biaya').AsFloat));
      vJSONItem.Add('stts_pulang', Trim(vQuery.FieldByName('stts_pulang').AsString));
      vJSONItem.Add('lama_hari', vQuery.FieldByName('lama').AsInteger);
      vJSONItem.Add('nm_dokter_dpjp', Trim(vQuery.FieldByName('nm_dokter').AsString));
      vJSONItem.Add('status_bayar', Trim(vQuery.FieldByName('status_bayar').AsString));
      vJSONItem.Add('agama', Trim(vQuery.FieldByName('agama').AsString));

      vJSONArray.Add(vJSONItem);
      vQuery.Next;
    end;

    AResponse.Send(vJSONArray.AsJSON, 'application/json; charset=utf-8', 200);

  except
    on E: Exception do
    begin
      AResponse.SendFmt('{"status": "error", "message": "Gagal mencari data ranap: %s"}', [E.Message], 'application/json', 500);
    end;
  end;

  vJSONArray.Free;
  vFilterSQL.Free;
  vQuery.Free;
end;

end.
