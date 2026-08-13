unit umod_ralan_pasien;

{$MODE DELPHI}

interface

uses
  SysUtils, Classes, BrookHTTPRequest, BrookHTTPResponse, BrookURLRouter,BrookUtility,
  ZDataset, fpjson, jsonparser;

type
  TRouteRalanPasienCRUD = class(TBrookRoute)
  public
    constructor Create(ACollection: TCollection); override;
    procedure Request(ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse); override;
  end;

implementation

uses uhandlerapi;

constructor TRouteRalanPasienCRUD.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  Pattern := '/api/v1/ralan/pasien';
end;

procedure TRouteRalanPasienCRUD.Request(ARequest: TBrookHTTPRequest; AResponse: TBrookHTTPResponse);
var
  vQuery: TZQuery;
  vTgl, vKdPoli, vKdDokter, vKeyword, vSQL: string;
  vJSONArr: TJSONArray;
  vJSONObj, vRespObj: TJSONObject;
begin
  // 1. Proteksi Rate Limiting (Menggunakan RemoteAddr)
  if not CheckRateLimit(ARequest.RemoteAddr) then
  begin
    AResponse.Send('{"status": "error", "message": "Terlalu banyak request (Rate Limit)."}', 'application/json', 429);
    Exit;
  end;

  // 2. Proteksi Autentikasi Token
  if not IsAuthenticatedtoken(ARequest, AResponse) then
    Exit;

  // Hanya izinkan HTTP Method GET
  if SameText(ARequest.Method, 'GET') = False then
  begin
    AResponse.Send('{"status": "error", "message": "Method Not Allowed. Gunakan GET."}', 'application/json', 405);
    Exit;
  end;

  // 3. Tangkap Query Parameters (Menggunakan ARequest.Params.Values)
  vTgl := ARequest.Params.Values['tanggal'];
  if vTgl = '' then
    vTgl := FormatDateTime('yyyy-mm-dd', Now);

  vKdPoli := ARequest.Params.Values['kd_poli'];
  vKdDokter := ARequest.Params.Values['kd_dokter'];
  vKeyword := ARequest.Params.Values['keyword'];

  vQuery := TZQuery.Create(nil);
  vRespObj := TJSONObject.Create;
  vJSONArr := TJSONArray.Create;

  try
    vQuery.Connection := gZConn;

    // 4. Query SIMRS Khanza (reg_periksa JOIN pasien, poliklinik, dokter, penjab)
    vSQL := 'SELECT r.no_rawat, r.no_rkm_medis, p.nm_pasien, p.jk, p.tgl_lahir, ' +
            'r.tgl_registrasi, r.jam_reg, pl.nm_poli, d.nm_dokter, pj.png_jawab, r.stts ' +
            'FROM reg_periksa r ' +
            'INNER JOIN pasien p ON r.no_rkm_medis = p.no_rkm_medis ' +
            'INNER JOIN poliklinik pl ON r.kd_poli = pl.kd_poli ' +
            'INNER JOIN dokter d ON r.kd_dokter = d.kd_dokter ' +
            'INNER JOIN penjab pj ON r.kd_pj = pj.kd_pj ' +
            'WHERE r.status_lanjut = ''Ralan'' ' +
            'AND r.tgl_registrasi = :tgl ';

    if vKdPoli <> '' then vSQL := vSQL + ' AND r.kd_poli = :kd_poli ';
    if vKdDokter <> '' then vSQL := vSQL + ' AND r.kd_dokter = :kd_dokter ';
    if vKeyword <> '' then vSQL := vSQL + ' AND (p.nm_pasien LIKE :keyword OR r.no_rkm_medis LIKE :keyword) ';

    vSQL := vSQL + ' ORDER BY r.jam_reg ASC';

    vQuery.SQL.Text := vSQL;
    vQuery.ParamByName('tgl').AsString := vTgl;

    if vKdPoli <> '' then vQuery.ParamByName('kd_poli').AsString := vKdPoli;
    if vKdDokter <> '' then vQuery.ParamByName('kd_dokter').AsString := vKdDokter;
    if vKeyword <> '' then vQuery.ParamByName('keyword').AsString := '%' + vKeyword + '%';

    vQuery.Open;

    // 5. Construct Payload JSON
    while not vQuery.EOF do
    begin
      vJSONObj := TJSONObject.Create;
      vJSONObj.Add('no_rawat', vQuery.FieldByName('no_rawat').AsString);
      vJSONObj.Add('no_rkm_medis', vQuery.FieldByName('no_rkm_medis').AsString);
      vJSONObj.Add('nm_pasien', vQuery.FieldByName('nm_pasien').AsString);
      vJSONObj.Add('jk', vQuery.FieldByName('jk').AsString);
      vJSONObj.Add('tgl_lahir', vQuery.FieldByName('tgl_lahir').AsString);
      vJSONObj.Add('tgl_registrasi', vQuery.FieldByName('tgl_registrasi').AsString);
      vJSONObj.Add('jam_reg', vQuery.FieldByName('jam_reg').AsString);
      vJSONObj.Add('nm_poli', vQuery.FieldByName('nm_poli').AsString);
      vJSONObj.Add('nm_dokter', vQuery.FieldByName('nm_dokter').AsString);
      vJSONObj.Add('png_jawab', vQuery.FieldByName('png_jawab').AsString);
      vJSONObj.Add('stts', vQuery.FieldByName('stts').AsString);

      vJSONArr.Add(vJSONObj);
      vQuery.Next;
    end;

    vRespObj.Add('status', 'success');
    vRespObj.Add('total_data', vJSONArr.Count);
    vRespObj.Add('data', vJSONArr);

    AResponse.Send(vRespObj.AsJSON, 'application/json', 200);

  except
    on E: Exception do
    begin
      AResponse.Send('{"status": "error", "message": "Terjadi kesalahan server: ' + E.Message + '"}', 'application/json', 500);
    end;
  end;

  vQuery.Free;
  vRespObj.Free;
end;

end.
