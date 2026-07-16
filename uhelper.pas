unit uhelper;

{$MODE DELPHI}

interface

uses
  SysUtils;

{ Fungsi global untuk mengubah format DD/MM/YYYY menjadi YYYY-MM-DD }
function PerbaikiFormatTanggal(AStringTanggal: string): string;

implementation

function PerbaikiFormatTanggal(AStringTanggal: string): string;
var
  vTgl, vBln, vThn, vJam: string;
  vStringTanggal: string; // FIX: Variabel dideklarasikan di sini agar tidak error
begin
  Result := AStringTanggal; // Nilai default jika format sudah sesuai YYYY-MM-DD
  
  vStringTanggal := Trim(AStringTanggal);
  // Deteksi jika string menggunakan pemisah garis miring regional (contoh: 03/05/2025)
  if (Pos('/', vStringTanggal) = 3) and (Length(vStringTanggal) >= 10) then
  begin
    vTgl := Copy(vStringTanggal, 1, 2);
    vBln := Copy(vStringTanggal, 4, 2);
    vThn := Copy(vStringTanggal, 7, 4);
    vJam := Copy(vStringTanggal, 11, Length(vStringTanggal)); // Mengambil sisa string jam (HH:NN:SS) jika ada
    
    Result := vThn + '-' + vBln + '-' + vTgl + vJam;
  end;
end;

end.