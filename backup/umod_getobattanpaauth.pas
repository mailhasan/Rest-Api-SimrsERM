unit umod_getObatTanpaAuth;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, BrookURLRouter, BrookHTTPRequest, BrookHTTPResponse,BrookUtility,
  fpjson, jsonparser,Math;

type
  { TRouteObatTanpaAuth }
  TRouteObatTanpaAuth = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

// Merujuk ke core handler untuk menggunakan database pool global (gZConn)
uses uhandlerapi;

procedure TRouteObatTanpaAuth.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];                  // Hanya melayani method GET
  Pattern := '/api/v1/publik/obat';    // Endpoint publik tanpa autentikasi
end;

procedure TRouteObatTanpaAuth.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vQuery: TZQuery;
  vNamaCari: string;
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  HargaDasar: Double;
  HargaDasarStr: string;
begin
  // Mengambil parameter opsional dari URL untuk pencarian nama obat (misal: ?nama=Amoxsan)
  vNamaCari := Trim(ARequest.Params.Values['nama']);

  vQuery := TZQuery.Create(nil);
  vQuery.Connection := uhandlerapi.gZConn; // Menggunakan connection pool pusat

  JSONArray := TJSONArray.Create;
  try
    vQuery.SQL.Clear;
    vQuery.SQL.Add('SELECT ');
    vQuery.SQL.Add('  databarang.kode_brng, ');
    vQuery.SQL.Add('  databarang.nama_brng, ');
    vQuery.SQL.Add('  databarang.kode_sat, ');
    vQuery.SQL.Add('  databarang.kode_satbesar, ');
    vQuery.SQL.Add('  jenis.nama AS nama_jenis, ');
    vQuery.SQL.Add('  golongan_barang.nama AS nama_golongan, ');
    vQuery.SQL.Add('  databarang.dasar, ');
    vQuery.SQL.Add('  databarang.expire, ');
    vQuery.SQL.Add('  databarang.status ');
    vQuery.SQL.Add('FROM databarang ');
    vQuery.SQL.Add('INNER JOIN jenis ON (databarang.kdjns = jenis.kdjns) ');
    vQuery.SQL.Add('INNER JOIN golongan_barang ON (databarang.kode_golongan = golongan_barang.kode) ');
    vQuery.SQL.Add('WHERE 1=1 ');

    // Fitur Tambahan: Jika klien mengirimkan parameter pencarian nama obat
    if vNamaCari <> '' then
    begin
      vQuery.SQL.Add('AND databarang.nama_brng LIKE :nama ');
      vQuery.ParamByName('nama').AsString := '%' + vNamaCari + '%';
    end;

    vQuery.SQL.Add('LIMIT 100'); // Batasi 100 data demi menjaga performa server & memori
    vQuery.Open;

    // Loop data dari database Khanza ke format JSON Array
    while not vQuery.EOF do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.Add('kode_barang', vQuery.FieldByName('kode_brng').AsString);
      JSONObject.Add('nama_barang', vQuery.FieldByName('nama_brng').AsString);
      JSONObject.Add('satuan_kecil', vQuery.FieldByName('kode_sat').AsString);
      JSONObject.Add('satuan_besar', vQuery.FieldByName('kode_satbesar').AsString);
      JSONObject.Add('jenis', vQuery.FieldByName('nama_jenis').AsString);
      JSONObject.Add('golongan', vQuery.FieldByName('nama_golongan').AsString);
      //JSONObject.Add('harga_dasar', RoundTo(vQuery.FieldByName('dasar').AsFloat, -2));
      // Ambil nilai dari database
      HargaDasar := vQuery.FieldByName('dasar').AsFloat;

      // Format dengan 2 desimal, misal: "122.10"
      // Ganti koma desimal dengan titik jika perlu
      HargaDasarStr := StringReplace(FormatFloat('0.00', HargaDasar), ',', '.', [rfReplaceAll]);

      // Tambahkan sebagai STRING ke JSON
      JSONObject.Add('harga_dasar', HargaDasarStr);
      JSONObject.Add('expired_date', vQuery.FieldByName('expire').AsString); // Format default MySQL: YYYY-MM-DD
      JSONObject.Add('status', vQuery.FieldByName('status').AsString);

      JSONArray.Add(JSONObject);
      vQuery.Next;
    end;

    // Kirim response sukses ke klien
    AResponse.Send(JSONArray.AsJSON, 'application/json; charset=utf-8', 200);

  except
    on E: Exception do
    begin
      // Penanganan error jika terjadi kegagalan query database
      AResponse.SendFmt('{"status": "error", "message": "Gagal mengambil data obat: %s"}', [E.Message], 'application/json', 500);
    end;
  end;

  // Cleanup alokasi objek lokal (Wajib untuk menjaga thread-safe)
  vQuery.Free;
  JSONArray.Free;
end;


end.
