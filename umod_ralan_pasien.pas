unit umod_ralan_pasien;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, ZDataset, ZConnection, BrookURLRouter,
  BrookHTTPRequest, BrookHTTPResponse, BrookUtility, fpjson, jsonparser;

type
  { TRouteRalanPasienCRUD }
  TRouteRalanPasienCRUD = class(TBrookURLRoute)
  protected
    procedure DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse) override;
  public
    procedure AfterConstruction; override;
  end;

implementation

uses uhandlerapi, uhelper;

procedure TRouteRalanPasienCRUD.AfterConstruction;
begin
  inherited AfterConstruction;
  Methods := [rmGET];
  Pattern := 'api/v1/ralan/pasien'; // Endpoint Daftar Pasien Rawat Jalan
end;

procedure TRouteRalanPasienCRUD.DoRequest(ASender: TObject; ARoute: TBrookURLRoute; ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vTgl, vKdPoli, vKdDokter, vKeyword: string;
  vQuery: TZQuery;
  vSQL: TStringList;
  vJSONArr: TJSONArray;
  vJSONObj: TJSONObject;
begin
  if not IsAuthenticatedtoken(ARequest, AResponse) then Exit;

  // 1. Ambil Parameter dari Request Query Parameters
  vTgl      := Trim(ARequest.Params.Values['tgl']);
  vKdPoli   := Trim(ARequest.Params.Values['kd_poli']);
  vKdDokter := Trim(ARequest.Params.Values['kd_dokter']);
  vKeyword  := Trim(ARequest.Params.Values['keyword']);

  // Set default tanggal hari ini jika parameter 'tgl' kosong
  if vTgl = '' then
    vTgl := FormatDateTime('yyyy-mm-dd', Now)
  else
    vTgl := PerbaikiFormatTanggal(vTgl);

  vQuery := TZQuery.Create(nil);
  vQuery.Connection := uhandlerapi.gZConn;
  vSQL := TStringList.Create;

  try
    // 2. Susun Query SQL SIMRS Khanza Secara Dinamis
    vSQL.Add('SELECT r.no_rawat, r.no_rkm_medis, p.nm_pasien, p.jk, p.tgl_lahir,');
    vSQL.Add('       r.tgl_registrasi, r.jam_reg, pl.nm_poli, d.nm_dokter, pj.png_jawab, r.stts');
    vSQL.Add('FROM reg_periksa r');
    vSQL.Add('INNER JOIN pasien p ON r.no_rkm_medis = p.no_rkm_medis');
    vSQL.Add('INNER JOIN poliklinik pl ON r.kd_poli = pl.kd_poli');
    vSQL.Add('INNER JOIN dokter d ON r.kd_dokter = d.kd_dokter');
    vSQL.Add('INNER JOIN penjab pj ON r.kd_pj = pj.kd_pj');
    vSQL.Add('WHERE r.status_lanjut = "Ralan"');
    vSQL.Add('  AND r.tgl_registrasi = :tgl');

    if vKdPoli <> '' then
      vSQL.Add('  AND r.kd_poli = :kd_poli');

    if vKdDokter <> '' then
      vSQL.Add('  AND r.kd_dokter = :kd_dokter');

    if vKeyword <> '' then
      vSQL.Add('  AND (p.nm_pasien LIKE :keyword OR r.no_rkm_medis LIKE :keyword)');

    vSQL.Add('ORDER BY r.jam_reg ASC');

    // 3. Inject Parameters ke Engine Query
    vQuery.SQL.Text := vSQL.Text;
    vQuery.ParamByName('tgl').AsString := vTgl;

    if vKdPoli <> '' then
      vQuery.ParamByName('kd_poli').AsString := vKdPoli;

    if vKdDokter <> '' then
      vQuery.ParamByName('kd_dokter').AsString := vKdDokter;

    if vKeyword <> '' then
      vQuery.ParamByName('keyword').AsString := '%' + vKeyword + '%';

    vQuery.Open;

    // 4. Construct Payload JSON Array Output
    vJSONArr := TJSONArray.Create;
    try
      while not vQuery.EOF do
      begin
        vJSONObj := TJSONObject.Create;
        vJSONObj.Add('no_rawat', Trim(vQuery.FieldByName('no_rawat').AsString));
        vJSONObj.Add('no_rkm_medis', Trim(vQuery.FieldByName('no_rkm_medis').AsString));
        vJSONObj.Add('nm_pasien', Trim(vQuery.FieldByName('nm_pasien').AsString));
        vJSONObj.Add('jk', Trim(vQuery.FieldByName('jk').AsString));
        vJSONObj.Add('tgl_lahir', Trim(vQuery.FieldByName('tgl_lahir').AsString));
        vJSONObj.Add('tgl_registrasi', Trim(vQuery.FieldByName('tgl_registrasi').AsString));
        vJSONObj.Add('jam_reg', Trim(vQuery.FieldByName('jam_reg').AsString));
        vJSONObj.Add('nm_poli', Trim(vQuery.FieldByName('nm_poli').AsString));
        vJSONObj.Add('nm_dokter', Trim(vQuery.FieldByName('nm_dokter').AsString));
        vJSONObj.Add('png_jawab', Trim(vQuery.FieldByName('png_jawab').AsString));
        vJSONObj.Add('stts', Trim(vQuery.FieldByName('stts').AsString));

        vJSONArr.Add(vJSONObj);
        vQuery.Next;
      end;

      AResponse.Send(vJSONArr.AsJSON, 'application/json; charset=utf-8', 200);
    finally
      vJSONArr.Free;
    end;

  finally
    vSQL.Free;
    vQuery.Free;
  end;
end;

end.
