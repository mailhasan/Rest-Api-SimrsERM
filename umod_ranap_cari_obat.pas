unit umod_ranap_cari_obat;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, fpjson, jsonparser;

type
  { TRouteRanapCariObat }
  TRouteRanapCariObat = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

uses uhandlerapi, uhelper;

procedure TRouteRanapCariObat.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];
  Pattern := 'api/v1/ranap/peresepan/cari-obat'; // Endpoint Pencarian & Build Cache Obat
end;

procedure TRouteRanapCariObat.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vKdBangsal, vStokKosongResep, vAktifkanBatchObat, vKeyword: string;
  vKenaikanHargaStr: string;
  vKenaikanHargaPersen: Double;
  vQuery: TZQuery;
  vSQL: TStringList;
  vRootArray: TJSONArray;
  vObjObat: TJSONObject;
begin
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  // 1. Ambil Parameter Kontrol Bisnis dari URL Query Params
  vKdBangsal          := ARequest.Params.Values['kd_bangsal'];
  vStokKosongResep    := LowerCase(Trim(ARequest.Params.Values['stok_kosong_resep'])); // "yes" atau "no"
  vAktifkanBatchObat  := LowerCase(Trim(ARequest.Params.Values['aktifkan_batch_obat'])); // "yes" atau "no"
  vKenaikanHargaStr   := ARequest.Params.Values['kenaikan_harga']; // Nilai % asuransi, misal 0.10 untuk 10%
  vKeyword            := Trim(ARequest.Params.Values['keyword']); // Pencarian nama / kode barang

  if vKdBangsal = '' then
  begin
    AResponse.Send('{"status": "error", "message": "Parameter kd_bangsal wajib diisi!"}', 'application/json', 400);
    Exit;
  end;

  vKenaikanHargaPersen := StrToFloatDef(vKenaikanHargaStr, 0.0);

  vQuery := TZQuery.Create(nil);
  vQuery.Connection := uhandlerapi.gZConn;
  vSQL := TStringList.Create;

  try
    // 2. Build Query SQL Secara Dinamis Berdasarkan Konfigurasi Bisnis
    vSQL.Add('SELECT databarang.kode_brng, databarang.nama_brng, jenis.nama AS nama_jenis, databarang.kode_sat,');

    // Kondisi: Jika ada kenaikan harga asuransi, hitung dinamis. Jika tidak, ambil multi-tarif standar
    if vKenaikanHargaPersen > 0 then
    begin
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS karyawan,');
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS ralan,');
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS beliluar,');
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS kelas1,');
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS kelas2,');
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS kelas3,');
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS vip,');
      vSQL.Add('       (databarang.h_beli + (databarang.h_beli * :kenaikan)) AS vvip,');
    end
    else
    begin
      vSQL.Add('       databarang.karyawan, databarang.ralan, databarang.beliluar, databarang.kelas1,');
      vSQL.Add('       databarang.kelas2, databarang.kelas3, databarang.vip, databarang.vvip,');
    end;

    vSQL.Add('       databarang.letak_barang, databarang.utama, industrifarmasi.nama_industri,');
    vSQL.Add('       databarang.h_beli, SUM(gudangbarang.stok) AS stok, databarang.kapasitas');
    vSQL.Add('FROM databarang ');
    vSQL.Add('INNER JOIN jenis ON databarang.kdjns = jenis.kdjns');
    vSQL.Add('INNER JOIN industrifarmasi ON industrifarmasi.kode_industri = databarang.kode_industri');
    vSQL.Add('INNER JOIN gudangbarang ON databarang.kode_brng = gudangbarang.kode_brng');
    vSQL.Add('WHERE databarang.status = "1" AND gudangbarang.kd_bangsal = :kd_bangsal');

    // Filter Aturan Bisnis: STOKKOSONGRESEP = "no"
    if vStokKosongResep = 'no' then
      vSQL.Add('  AND gudangbarang.stok > 0');

    // Filter Aturan Bisnis: AKTIFKANBATCHOBAT = "yes"
    if vAktifkanBatchObat = 'yes' then
      vSQL.Add('  AND gudangbarang.no_batch <> "" AND gudangbarang.no_faktur <> ""');

    // Filter Tambahan: Keyword Pencarian dari Frontend (Kode atau Nama Obat)
    if vKeyword <> '' then
      vSQL.Add('  AND (databarang.kode_brng LIKE :keyword OR databarang.nama_brng LIKE :keyword)');

    vSQL.Add('GROUP BY gudangbarang.kode_brng');
    vSQL.Add('ORDER BY databarang.nama_brng');

    // 3. Inject Parameters ke Engine Zeos
    vQuery.SQL.Text := vSQL.Text;
    vQuery.ParamByName('kd_bangsal').AsString := vKdBangsal;

    if vKenaikanHargaPersen > 0 then
      vQuery.ParamByName('kenaikan').AsFloat := vKenaikanHargaPersen;

    if vKeyword <> '' then
      vQuery.ParamByName('keyword').AsString := '%' + vKeyword + '%';

    vQuery.Open;

    // 4. Parsing Hasil Array Database Menjadi Format Data Cache JSON
    vRootArray := TJSONArray.Create;
    try
      while not vQuery.EOF do
      begin
        vObjObat := TJSONObject.Create;
        vObjObat.Add('kode_brng', Trim(vQuery.FieldByName('kode_brng').AsString));
        vObjObat.Add('nama_brng', Trim(vQuery.FieldByName('nama_brng').AsString));
        vObjObat.Add('jenis', Trim(vQuery.FieldByName('nama_jenis').AsString));
        vObjObat.Add('kode_sat', Trim(vQuery.FieldByName('kode_sat').AsString));
        
        // Amandemen Eksponensial untuk Nilai Stok, Kapasitas, dan Harga Beli
        vObjObat.Add('stok', GetJSON(FormatFloat('0.##', vQuery.FieldByName('stok').AsFloat)));
        vObjObat.Add('kapasitas', vQuery.FieldByName('kapasitas').AsInteger);
        vObjObat.Add('h_beli', GetJSON(FormatFloat('0.##', vQuery.FieldByName('h_beli').AsFloat)));
        
        // Amandemen Eksponensial Pemetaan Jual Multi-Tarif Harga
        vObjObat.Add('karyawan', GetJSON(FormatFloat('0.##', vQuery.FieldByName('karyawan').AsFloat)));
        vObjObat.Add('ralan', GetJSON(FormatFloat('0.##', vQuery.FieldByName('ralan').AsFloat)));
        vObjObat.Add('beliluar', GetJSON(FormatFloat('0.##', vQuery.FieldByName('beliluar').AsFloat)));
        vObjObat.Add('kelas1', GetJSON(FormatFloat('0.##', vQuery.FieldByName('kelas1').AsFloat)));
        vObjObat.Add('kelas2', GetJSON(FormatFloat('0.##', vQuery.FieldByName('kelas2').AsFloat)));
        vObjObat.Add('kelas3', GetJSON(FormatFloat('0.##', vQuery.FieldByName('kelas3').AsFloat)));
        vObjObat.Add('vip', GetJSON(FormatFloat('0.##', vQuery.FieldByName('vip').AsFloat)));
        vObjObat.Add('vvip', GetJSON(FormatFloat('0.##', vQuery.FieldByName('vvip').AsFloat)));
        
        vObjObat.Add('letak_barang', Trim(vQuery.FieldByName('letak_barang').AsString));
        vObjObat.Add('utama', Trim(vQuery.FieldByName('utama').AsString));
        vObjObat.Add('nama_industri', Trim(vQuery.FieldByName('nama_industri').AsString));

        vRootArray.Add(vObjObat);
        vQuery.Next;
      end;

      AResponse.Send(vRootArray.AsJSON, 'application/json; charset=utf-8', 200);
    finally
      vRootArray.Free;
    end;

  finally
    vSQL.Free;
    vQuery.Free;
  end;
end;

end.
