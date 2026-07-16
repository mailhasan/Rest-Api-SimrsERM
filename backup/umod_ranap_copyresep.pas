unit umod_ranap_copyresep;

{$MODE DELPHI} // Menggunakan mode Delphi agar selaras dengan pola uhandlerapi

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, fpjson, jsonparser;

type
  { TRouteRanapCopyResepCRUD }
  TRouteRanapCopyResepCRUD = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TRouteRanapCopyResepCRUD }
uses uhandlerapi, uhelper;

procedure TRouteRanapCopyResepCRUD.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET, rmDELETE];
  Pattern := 'api/v1/farmasi/copyresep'; // Endpoint Terpadu Copy Resep
end;

procedure TRouteRanapCopyResepCRUD.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vNoRM, vTglAwal, vTglAkhir, vKdDokter, vTampilkanDokterLain, vNoResep, vPayloadStr: string;
  vFilterSQL: TStringList;
  vQuery, vQueryObat, vQueryRacik, vQueryBahan: TZQuery;
  vJSONReq: TJSONObject;
  vJSONArray, vArrObatBiasa, vArrRacikan, vArrBahanRacik: TJSONArray;
  vObjResep, vObjObat, vObjRacik, vObjBahan: TJSONObject;
  vJSONData: TJSONData; // FIX: Variabel ini sekarang sudah didaftarkan dengan aman!
begin
  // Proteksi Keamanan: Validasi Token via middleware satpam global uhandlerapi
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  // Inisialisasi Objek Database Zeos
  vQuery      := TZQuery.Create(nil); vQuery.Connection      := uhandlerapi.gZConn;
  vQueryObat  := TZQuery.Create(nil); vQueryObat.Connection  := uhandlerapi.gZConn;
  vQueryRacik := TZQuery.Create(nil); vQueryRacik.Connection := uhandlerapi.gZConn;
  vQueryBahan := TZQuery.Create(nil); vQueryBahan.Connection := uhandlerapi.gZConn;

  vFilterSQL  := TStringList.Create;

  try
    // =================================================================
    // 1. OPERATION: GET (MENAMPILKAN DAFTAR RESEP & DETAIL OBAT)
    // =================================================================
    if ARequest.Method = 'GET' then
    begin
      // Menangkap parameter opsional & wajib via Query URL
      vNoRM                := ARequest.Params.Values['no_rkm_medis'];
      vTglAwal             := PerbaikiFormatTanggal(ARequest.Params.Values['tgl_awal']);
      vTglAkhir            := PerbaikiFormatTanggal(ARequest.Params.Values['tgl_akhir']);
      vKdDokter            := ARequest.Params.Values['kd_dokter'];
      vTampilkanDokterLain := LowerCase(Trim(ARequest.Params.Values['copy_dokter_lain'])); // "yes" atau "no"

      if vNoRM = '' then
      begin
        AResponse.Send('{"status": "error", "message": "Parameter no_rkm_medis wajib disertakan!"}', 'application/json', 400);
        Exit;
      end;

      vJSONArray := TJSONArray.Create;
      try
        // Build Query Utama Daftar Resep Historis Pasien
        vFilterSQL.Clear;
        vFilterSQL.Add('SELECT resep_obat.no_resep, resep_obat.tgl_peresepan, resep_obat.jam_peresepan,');
        vFilterSQL.Add('       resep_obat.no_rawat, pasien.no_rkm_medis, pasien.nm_pasien,');
        vFilterSQL.Add('       resep_obat.kd_dokter, dokter.nm_dokter,');
        vFilterSQL.Add('       IF(resep_obat.tgl_perawatan="0000-00-00" OR resep_obat.tgl_perawatan IS NULL, "Belum Terlayani", "Sudah Terlayani") AS status,');
        vFilterSQL.Add('       resep_obat.status AS status_asal');
        vFilterSQL.Add('FROM resep_obat');
        vFilterSQL.Add('INNER JOIN reg_periksa ON resep_obat.no_rawat = reg_periksa.no_rawat');
        vFilterSQL.Add('INNER JOIN pasien ON reg_periksa.no_rkm_medis = pasien.no_rkm_medis');
        vFilterSQL.Add('INNER JOIN dokter ON resep_obat.kd_dokter = dokter.kd_dokter');
        vFilterSQL.Add('WHERE resep_obat.tgl_peresepan <> "0000-00-00"');
        vFilterSQL.Add('  AND pasien.no_rkm_medis = :no_rm');

        // Filter Rentang Tanggal jika diaktifkan dari Frontend
        if (vTglAwal <> '') and (vTglAkhir <> '') then
          vFilterSQL.Add('  AND resep_obat.tgl_peresepan BETWEEN :tgl_awal AND :tgl_akhir');

        // Filter TAMPILKANCOPYRESEPDOKTERLAIN = "no" -> kunci hanya dokter yang sama
        if (vTampilkanDokterLain = 'no') and (vKdDokter <> '') then
          vFilterSQL.Add('  AND resep_obat.kd_dokter = :kd_dokter');

        vFilterSQL.Add('ORDER BY resep_obat.tgl_peresepan DESC, resep_obat.jam_peresepan DESC');

        vQuery.SQL.Text := vFilterSQL.Text;
        vQuery.ParamByName('no_rm').AsString := vNoRM;
        if (vTglAwal <> '') and (vTglAkhir <> '') then
        begin
          vQuery.ParamByName('tgl_awal').AsString := vTglAwal;
          vQuery.ParamByName('tgl_akhir').AsString := vTglAkhir;
        end;
        if (vTampilkanDokterLain = 'no') and (vKdDokter <> '') then
          vQuery.ParamByName('kd_dokter').AsString := vKdDokter;

        vQuery.Open;

        // Loop Induk Data Resep Pasien
        while not vQuery.EOF do
        begin
          vObjResep := TJSONObject.Create;
          vNoResep  := vQuery.FieldByName('no_resep').AsString;

          vObjResep.Add('no_resep', Trim(vNoResep));
          vObjResep.Add('tgl_peresepan', vQuery.FieldByName('tgl_peresepan').AsString);
          vObjResep.Add('jam_peresepan', vQuery.FieldByName('jam_peresepan').AsString);
          vObjResep.Add('no_rawat', Trim(vQuery.FieldByName('no_rawat').AsString));
          vObjResep.Add('no_rkm_medis', Trim(vQuery.FieldByName('no_rkm_medis').AsString));
          vObjResep.Add('nm_pasien', Trim(vQuery.FieldByName('nm_pasien').AsString));
          vObjResep.Add('kd_dokter', Trim(vQuery.FieldByName('kd_dokter').AsString));
          vObjResep.Add('nm_dokter', Trim(vQuery.FieldByName('nm_dokter').AsString));
          vObjResep.Add('status', vQuery.FieldByName('status').AsString);
          vObjResep.Add('status_asal', vQuery.FieldByName('status_asal').AsString);

          // -----------------------------------------------------------
          // SUB-PROSES 1: Ambil Detail Obat Biasa (Non-Racikan)
          // -----------------------------------------------------------
          vArrObatBiasa := TJSONArray.Create;
          vQueryObat.SQL.Clear;
          vQueryObat.SQL.Add('SELECT databarang.kode_brng, databarang.nama_brng, resep_dokter.jml,');
          vQueryObat.SQL.Add('       databarang.kode_sat, resep_dokter.aturan_pakai ');
          vQueryObat.SQL.Add('FROM resep_dokter ');
          vQueryObat.SQL.Add('INNER JOIN databarang ON resep_dokter.kode_brng = databarang.kode_brng ');
          vQueryObat.SQL.Add('WHERE resep_dokter.no_resep = :no_resep ORDER BY databarang.kode_brng');
          vQueryObat.ParamByName('no_resep').AsString := vNoResep;
          vQueryObat.Open;

          while not vQueryObat.EOF do
          begin
            vObjObat := TJSONObject.Create;
            vObjObat.Add('kode_brng', Trim(vQueryObat.FieldByName('kode_brng').AsString));
            vObjObat.Add('nama_brng', Trim(vQueryObat.FieldByName('nama_brng').AsString));
            //vObjObat.Add('jml', vQueryObat.FieldByName('jml').AsFloat);
            // Menggunakan GetJSON untuk mem-parse string angka murni hasil FormatFloat secara aman sebagai Number asli
            vObjObat.Add('jml', GetJSON(FormatFloat('0.##', vQueryObat.FieldByName('jml').AsFloat)));
            vObjObat.Add('kode_sat', Trim(vQueryObat.FieldByName('kode_sat').AsString));
            vObjObat.Add('aturan_pakai', Trim(vQueryObat.FieldByName('aturan_pakai').AsString));
            vArrObatBiasa.Add(vObjObat);
            vQueryObat.Next;
          end;
          vObjResep.Add('obat_biasa', vArrObatBiasa);

          // -----------------------------------------------------------
          // SUB-PROSES 2: Ambil Detail Obat Racikan (Nested Structure)
          // -----------------------------------------------------------
          vArrRacikan := TJSONArray.Create;
          vQueryRacik.SQL.Clear;
          vQueryRacik.SQL.Add('SELECT resep_dokter_racikan.no_racik, resep_dokter_racikan.nama_racik,');
          vQueryRacik.SQL.Add('       resep_dokter_racikan.kd_racik, metode_racik.nm_racik AS metode,');
          vQueryRacik.SQL.Add('       resep_dokter_racikan.jml_dr, resep_dokter_racikan.aturan_pakai, resep_dokter_racikan.keterangan ');
          vQueryRacik.SQL.Add('FROM resep_dokter_racikan ');
          vQueryRacik.SQL.Add('INNER JOIN metode_racik ON resep_dokter_racikan.kd_racik = metode_racik.kd_racik ');
          vQueryRacik.SQL.Add('WHERE resep_dokter_racikan.no_resep = :no_resep');
          vQueryRacik.ParamByName('no_resep').AsString := vNoResep;
          vQueryRacik.Open;

          while not vQueryRacik.EOF do
          begin
            vObjRacik := TJSONObject.Create;
            vObjRacik.Add('no_racik', vQueryRacik.FieldByName('no_racik').AsInteger);
            vObjRacik.Add('nama_racik', Trim(vQueryRacik.FieldByName('nama_racik').AsString));
            vObjRacik.Add('kd_racik', Trim(vQueryRacik.FieldByName('kd_racik').AsString));
            vObjRacik.Add('metode', Trim(vQueryRacik.FieldByName('metode').AsString));
            //vObjRacik.Add('jml_dr', vQueryRacik.FieldByName('jml_dr').AsInteger);
            //vObjRacik.Add('jml_dr', StrToFloat(FormatFloat('0.##', vQueryRacik.FieldByName('jml').AsFloat)));
            vObjRacik.Add('jml_dr', GetJSON(FormatFloat('0.##', vQueryRacik.FieldByName('jml_dr').AsFloat)));
            vObjRacik.Add('aturan_pakai', Trim(vQueryRacik.FieldByName('aturan_pakai').AsString));
            vObjRacik.Add('keterangan', Trim(vQueryRacik.FieldByName('keterangan').AsString));

            // Nested di dalam racikan: Ambil Detail Bahan Baku Racik
            vArrBahanRacik := TJSONArray.Create;
            vQueryBahan.SQL.Clear;
            vQueryBahan.SQL.Add('SELECT databarang.kode_brng, databarang.nama_brng, resep_dokter_racikan_detail.jml, databarang.kode_sat ');
            vQueryBahan.SQL.Add('FROM resep_dokter_racikan_detail ');
            vQueryBahan.SQL.Add('INNER JOIN databarang ON resep_dokter_racikan_detail.kode_brng = databarang.kode_brng ');
            vQueryBahan.SQL.Add('WHERE resep_dokter_racikan_detail.no_resep = :no_resep AND resep_dokter_racikan_detail.no_racik = :no_racik ');
            vQueryBahan.SQL.Add('ORDER BY databarang.kode_brng');
            vQueryBahan.ParamByName('no_resep').AsString := vNoResep;
            vQueryBahan.ParamByName('no_racik').AsInteger := vQueryRacik.FieldByName('no_racik').AsInteger;
            vQueryBahan.Open;

            while not vQueryBahan.EOF do
            begin
              vObjBahan := TJSONObject.Create;
              vObjBahan.Add('kode_brng', Trim(vQueryBahan.FieldByName('kode_brng').AsString));
              vObjBahan.Add('nama_brng', Trim(vQueryBahan.FieldByName('nama_brng').AsString));
              //vObjBahan.Add('jml', vQueryBahan.FieldByName('jml').AsFloat);
              // Melakukan hal yang sama untuk jumlah bahan baku racikan
              vObjBahan.Add('jml', GetJSON(FormatFloat('0.##', vQueryBahanRacik.FieldByName('jml_dr').AsFloat)));
              vObjBahan.Add('kode_sat', Trim(vQueryBahan.FieldByName('kode_sat').AsString));
              vArrBahanRacik.Add(vObjBahan);
              vQueryBahan.Next;
            end;
            vObjRacik.Add('detail_bahan', vArrBahanRacik);

            vArrRacikan.Add(vObjRacik);
            vQueryRacik.Next;
          end;
          vObjResep.Add('obat_racikan', vArrRacikan);

          vJSONArray.Add(vObjResep);
          vQuery.Next;
        end;

        AResponse.Send(vJSONArray.AsJSON, 'application/json; charset=utf-8', 200);
      finally
        vJSONArray.Free;
      end;
    end

    // =================================================================
    // 2. OPERATION: DELETE (HAPUS RESEP YANG BELUM TERLAYANI)
    // =================================================================
    else if ARequest.Method = 'DELETE' then
    begin
      vJSONData := nil;
      try
        vPayloadStr := ARequest.Payload.ToString;
        vJSONData := GetJSON(vPayloadStr);
        vJSONReq := TJSONObject(vJSONData);

        vNoResep := Trim(vJSONReq.Get('no_resep', ''));

        if vNoResep = '' then
          raise Exception.Create('Parameter no_resep wajib dikirim di dalam body!');

        // Validasi Aturan Bisnis: Cek status layanan (Tidak boleh hapus resep jika sudah dilayani apotek)
        vQuery.SQL.Clear;
        vQuery.SQL.Add('SELECT tgl_perawatan FROM resep_obat WHERE no_resep = :no_resep');
        vQuery.ParamByName('no_resep').AsString := vNoResep;
        vQuery.Open;

        if vQuery.EOF then
        begin
          AResponse.Send('{"status": "error", "message": "Gagal: Nomor resep tidak ditemukan!"}', 'application/json', 404);
          Exit;
        end;

        if (vQuery.FieldByName('tgl_perawatan').AsString <> '0000-00-00') and
           (vQuery.FieldByName('tgl_perawatan').AsString <> '') then
        begin
          AResponse.Send('{"status": "error", "message": "Gagal: Resep tidak boleh dihapus karena sudah berstatus Terlayani di Apotek!"}', 'application/json', 400);
          Exit;
        end;
        vQuery.Close;

        // Eksekusi Hapus Data Terikat (ON DELETE CASCADE SIMRS akan otomatis menghapus detail_dokter & racikan)
        vQuery.SQL.Clear;
        vQuery.SQL.Add('DELETE FROM resep_obat WHERE no_resep = :no_resep');
        vQuery.ParamByName('no_resep').AsString := vNoResep;
        vQuery.ExecSQL;

        AResponse.Send('{"status": "success", "message": "Data resep berhasil dihapus secara permanen"}', 'application/json', 200);
      except
        on E: Exception do AResponse.SendFmt('{"status": "error", "message": "%s"}', [E.Message], 'application/json', 500);
      end;
      if Assigned(vJSONData) then vJSONData.Free;
    end;

  finally
    vFilterSQL.Free;
    vQuery.Free;
    vQueryObat.Free;
    vQueryRacik.Free;
    vQueryBahan.Free;
  end;
end;

{ =====================================================================
  ℹ️ DESKRIPSI FUNGSIONALITAS FITUR & ALUR BISNIS (NON-READABLE COMPILER)
  =====================================================================
  1. KEMAMPUAN GET / SEARCHING:
     - Mengambil riwayat master resep berdasarkan nomor RM pasien secara real-time.
     - Mendukung filter dinamis lintas tanggal peresepan menggunakan helper 'PerbaikiFormatTanggal'.
     - Mengakomodasi konfigurasi 'copy_dokter_lain=no' untuk membatasi hak akses resep lintas dokter.

  2. STRUKTUR DATA NESTED JSON:
     - 'obat_biasa': Array berisi daftar obat reguler non-racik beserta aturan pakainya.
     - 'obat_racikan': Array komposit yang di dalamnya berisi sub-array 'detail_bahan'
       untuk memetakan komposisi racikan (metode, jumlah, dan bahan obat terkait).

  3. VALIDASI HAPUS (DELETE):
     - Membaca status orisinal field 'tgl_perawatan' pada resep_obat.
     - Menghalangi/reject instruksi penghapusan (Error 400) apabila resep tersebut
       sudah diproses oleh farmasi/apotek demi menjaga integritas data penagihan.
  ===================================================================== }

end.
