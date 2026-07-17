unit umod_ranap_resep_counter;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, fpjson;

type
  { TRouteRanapResepCounter }
  TRouteRanapResepCounter = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

uses uhandlerapi;

procedure TRouteRanapResepCounter.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];
  Pattern := 'api/v1/ranap/peresepan/counter'; // Endpoint Generator Nomor Resep
end;

procedure TRouteRanapResepCounter.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vQuery: TZQuery;
  vTglSekaligus, vPrefix, vNoResepBaru: string;
  vLastNum, vNextNum: Integer;
begin
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  vQuery := TZQuery.Create(nil);
  vQuery.Connection := uhandlerapi.gZConn;

  try
    // Format prefix berdasarkan tanggal hari ini: YYYYMMDD (Contoh: 20260717)
    vTglSekaligus := FormatDateTime('yyyymmdd', Now);
    vPrefix := vTglSekaligus;

    uhandlerapi.gZConn.StartTransaction;
    try
      vQuery.SQL.Clear;
      // LOCK ROW MECHANISM: Mengunci baris nomor terakhir di hari ini agar tidak bisa dibaca thread lain sebelum commit
      vQuery.SQL.Add('SELECT no_resep FROM resep_obat WHERE no_resep LIKE :prefix ');
      vQuery.SQL.Add('ORDER BY no_resep DESC LIMIT 1 FOR UPDATE');
      vQuery.ParamByName('prefix').AsString := vPrefix + '%';
      vQuery.Open;

      if vQuery.EOF then
      begin
        // Jika hari ini belum ada resep sama sekali, mulai dari 0001
        vNoResepBaru := vPrefix + '0001';
      end
      else // FIX CORE: Menambahkan kata kunci 'else' yang tertinggal
      begin
        // Jika sudah ada, ambil 4 digit terakhir, convert ke integer, lalu tambah 1
        vLastNum := StrToIntDef(Copy(vQuery.FieldByName('no_resep').AsString, 9, 4), 0);
        vNextNum := vLastNum + 1;
        vNoResepBaru := vPrefix + FormatFloat('0000', vNextNum);
      end;
      vQuery.Close;

      uhandlerapi.gZConn.Commit;

      AResponse.SendFmt('{"status": "success", "no_resep": "%s"}', [vNoResepBaru], 'application/json', 200);
    except
      on E: Exception do
      begin
        if uhandlerapi.gZConn.InTransaction then uhandlerapi.gZConn.Rollback;
        AResponse.SendFmt('{"status": "error", "message": "Gagal generate nomor resep: %s"}', [E.Message], 'application/json', 500);
      end;
    end;
  finally
    vQuery.Free;
  end;
end;

end.
{
6. OTOMATISASI SINKRONISASI ATURAN PAKAI KHUSUS (SIGNA NORMALIZATION):
     - Sanitasi String Komparatif: Memanfaatkan fungsi internal 'NormalisasiSigna' untuk menyaring teks input bebas.
     - Transformasi Rule: Menghilangkan spasi ganda, membuang spasi di sekitar separator, dan mengonversi 
       notasi string kecil '3 x 1' atau '3x1' secara rigid menjadi format kapital terpadu '3X1'.
     - Manfaat: Menjamin keseragaman visual etiket saat di-render oleh komponen printer thermal farmasi.
  ===================================================================== }
