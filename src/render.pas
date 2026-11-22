unit render;

{ Keycap drawing on GDI+ graphics: rounded caps with border, shadow, centered
  text, '+' separators. Sizing driven by config metrics. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, config, gdip;

type
  TKeyItem = record
    Text: string;
    Glyph: Word;       // when <> 0, draw this codepoint with the symbol font
    Symbol: Boolean;
    IsMod: Boolean;
    X, W: Single;      // horizontal layout inside the row
  end;
  TKeyItemArr = array of TKeyItem;

  TMetrics = record
    s, CapH, RowGap, Gap, PlusW, PadX, MinCapW, FontPx, Radius: Single;
  end;

procedure RenderInit;
procedure RenderDone;
procedure RenderInvalidateCaches;

function  GetMetrics: TMetrics;
function  MeasureRow(var items: TKeyItemArr; const m: TMetrics): Single;
procedure DrawRow(g: PGpGraphics; const items: TKeyItemArr; y: Single;
  alphaMul: Byte; const m: TMetrics);

implementation

var
  MeasBmp: PGpBitmap = nil;
  MeasG: PGpGraphics = nil;
  SFmt: PGpStringFormat = nil;
  FamUI: PGpFontFamily = nil;
  FamSym: PGpFontFamily = nil;
  FontUI: PGpFont = nil;
  FontSym: PGpFont = nil;
  LastFontPx: Single = -1;

procedure RoundedRectPath(out path: PGpPath; x, y, w, h, r: Single);
var
  d: Single;
begin
  path := nil;
  if GdipCreatePath(FillModeWinding, path) <> 0 then
    Exit;
  d := 2 * r;
  if d > w then d := w;
  if d > h then d := h;
  GdipAddPathArc(path, x, y, d, d, 180, 90);
  GdipAddPathArc(path, x + w - d, y, d, d, 270, 90);
  GdipAddPathArc(path, x + w - d, y + h - d, d, d, 0, 90);
  GdipAddPathArc(path, x, y + h - d, d, d, 90, 90);
  GdipClosePathFigure(path);
end;

procedure EnsureFonts(const m: TMetrics);
begin
  if (FontUI <> nil) and (LastFontPx = m.FontPx) then
    Exit;
  if FontUI <> nil then GdipDeleteFont(FontUI);
  if FontSym <> nil then GdipDeleteFont(FontSym);
  FontUI := nil;
  FontSym := nil;
  if FamUI = nil then
    GdipCreateFontFamilyFromName('Segoe UI', nil, FamUI);
  if FamSym = nil then
    GdipCreateFontFamilyFromName('Segoe UI Symbol', nil, FamSym);
  if FamUI <> nil then
    GdipCreateFont(FamUI, m.FontPx, FontStyleBold, UnitPixel, FontUI);
  if FamSym <> nil then
    GdipCreateFont(FamSym, m.FontPx, FontStyleRegular, UnitPixel, FontSym);
  LastFontPx := m.FontPx;
end;

// build a 1-char UnicodeString without any codepage conversion
function WideOf(code: Word): UnicodeString;
begin
  Result := '';
  SetLength(Result, 1);
  Result[1] := WideChar(code);
end;

function TextWidth(const text: string; glyph: Word; const m: TMetrics): Single;
var
  bounds: TGPRectF;
  font: PGpFont;
  rc: TGPRectF;
  us: UnicodeString;
begin
  Result := 0;
  EnsureFonts(m);
  if glyph <> 0 then
    font := FontSym
  else
    font := FontUI;
  if (font = nil) or (MeasG = nil) then
  begin
    Result := Length(text) * m.FontPx * 0.6;   // crude fallback
    Exit;
  end;
  if glyph <> 0 then
    us := WideOf(glyph)
  else
    us := UTF8Decode(text);
  if us = '' then us := ' ';
  rc.X := 0; rc.Y := 0; rc.Width := 10000; rc.Height := 1000;
  if GdipMeasureString(MeasG, PWideChar(us), Length(us), font, @rc,
    SFmt, @bounds, nil, nil) = 0 then
    Result := bounds.Width;
end;

function GetMetrics: TMetrics;
begin
  Result.s := Cfg.ScalePct / 100;
  Result.CapH := 64 * Result.s;
  Result.RowGap := 10 * Result.s;
  Result.Gap := 8 * Result.s;
  Result.PlusW := 18 * Result.s;
  Result.PadX := 13 * Result.s;
  Result.MinCapW := 54 * Result.s;
  Result.FontPx := Cfg.FontPx * Result.s;
  Result.Radius := Cfg.RadiusPx * Result.s;
  if Result.Radius > Result.CapH / 2 - 1 then
    Result.Radius := Result.CapH / 2 - 1;
  if Result.Radius < 0 then
    Result.Radius := 0;
end;

function MeasureRow(var items: TKeyItemArr; const m: TMetrics): Single;
var
  i: Integer;
  x: Single;
begin
  x := 0;
  for i := 0 to High(items) do
  begin
    items[i].X := x;
    items[i].W := TextWidth(items[i].Text, items[i].Glyph, m) + 2 * m.PadX;
    if items[i].W < m.MinCapW then
      items[i].W := m.MinCapW;
    x := items[i].X + items[i].W + m.Gap;
  end;
  if Length(items) = 0 then
    Exit(0);
  Result := items[High(items)].X + items[High(items)].W;
end;

procedure DrawCap(g: PGpGraphics; const it: TKeyItem; y: Single;
  alphaMul: Byte; const m: TMetrics);
var
  path: PGpPath;
  brush: PGpBrush;
  pen: PGpPen;
  color, txtColor: DWORD;
  rc: TGPRectF;
  font: PGpFont;
  us: UnicodeString;
begin
  // shadow
  RoundedRectPath(path, it.X, y + 2 * m.s, it.W, m.CapH, m.Radius);
  if path <> nil then
  begin
    GdipCreateSolidFill(MulAlpha($40000000, alphaMul), brush);
    GdipFillPath(g, brush, path);
    GdipDeleteBrush(brush);
    GdipDeletePath(path);
  end;
  // body
  if it.IsMod then
    color := HexToARGB(Cfg.ColBgMod)
  else
    color := HexToARGB(Cfg.ColBgKey);
  txtColor := HexToARGB(Cfg.ColText);
  RoundedRectPath(path, it.X, y, it.W, m.CapH, m.Radius);
  if path <> nil then
  begin
    GdipCreateSolidFill(MulAlpha(color, alphaMul), brush);
    GdipFillPath(g, brush, path);
    GdipDeleteBrush(brush);
    pen := nil;
    GdipCreatePen1(MulAlpha(HexToARGB(Cfg.ColBorder), alphaMul),
      2 * m.s, UnitPixel, pen);
    if pen <> nil then
    begin
      GdipDrawPath(g, pen, path);
      GdipDeletePen(pen);
    end;
    GdipDeletePath(path);
  end;
  // text
  if (it.Text <> '') or (it.Glyph <> 0) then
  begin
    EnsureFonts(m);
    if it.Glyph <> 0 then
    begin
      font := FontSym;
      us := WideOf(it.Glyph);
    end
    else
    begin
      font := FontUI;
      us := UTF8Decode(it.Text);
      if us = '' then us := ' ';
    end;
    if font <> nil then
    begin
      rc.X := it.X; rc.Y := y - 10000;
      rc.Width := it.W; rc.Height := m.CapH + 20000;
      GdipCreateSolidFill(MulAlpha(txtColor, alphaMul), brush);
      GdipDrawString(g, PWideChar(us), Length(us), font, @rc,
        SFmt, brush);
      GdipDeleteBrush(brush);
    end;
  end;
end;

procedure DrawPlus(g: PGpGraphics; cx, cy: Single; alphaMul: Byte;
  const m: TMetrics);
var
  brush: PGpBrush;
  rc: TGPRectF;
  color: DWORD;
begin
  EnsureFonts(m);
  if FontUI = nil then
    Exit;
  color := HexToARGB(Cfg.ColPlus);
  rc.X := cx - 10000;
  rc.Y := cy - 10000;
  rc.Width := 20000;
  rc.Height := 20000;
  GdipCreateSolidFill(MulAlpha(color, alphaMul), brush);
  GdipDrawString(g, '+', 1, FontUI, @rc, SFmt, brush);
  GdipDeleteBrush(brush);
end;

procedure DrawRow(g: PGpGraphics; const items: TKeyItemArr; y: Single;
  alphaMul: Byte; const m: TMetrics);
var
  i: Integer;
  cx: Single;
begin
  for i := 0 to High(items) do
    DrawCap(g, items[i], y, alphaMul, m);
  for i := 0 to High(items) - 1 do
  begin
    cx := items[i].X + items[i].W + m.Gap / 2;
    DrawPlus(g, cx, y + m.CapH / 2, alphaMul, m);
  end;
end;

procedure RenderInit;
begin
  if MeasBmp = nil then
  begin
    GdipCreateBitmapFromScan0(8, 8, 0, PixelFormat32bppPARGB, nil, MeasBmp);
    if MeasBmp <> nil then
      GdipGetImageGraphicsContext(MeasBmp, MeasG);
    GdipCreateStringFormat(StringFormatFlagsNoWrap or StringFormatFlagsNoClip,
      0, SFmt);
    if SFmt <> nil then
    begin
      GdipSetStringFormatAlign(SFmt, StringAlignmentCenter);
      GdipSetStringFormatLineAlign(SFmt, StringAlignmentCenter);
      GdipSetStringFormatHotkeyPrefix(SFmt, HotkeyPrefixNone);
    end;
  end;
end;

procedure RenderDone;
begin
  if SFmt <> nil then begin GdipDeleteStringFormat(SFmt); SFmt := nil; end;
  if FontUI <> nil then begin GdipDeleteFont(FontUI); FontUI := nil; end;
  if FontSym <> nil then begin GdipDeleteFont(FontSym); FontSym := nil; end;
  if FamUI <> nil then begin GdipDeleteFontFamily(FamUI); FamUI := nil; end;
  if FamSym <> nil then begin GdipDeleteFontFamily(FamSym); FamSym := nil; end;
  if MeasG <> nil then begin GdipDeleteGraphics(MeasG); MeasG := nil; end;
  if MeasBmp <> nil then begin GdipDisposeImage(MeasBmp); MeasBmp := nil; end;
  LastFontPx := -1;
end;

procedure RenderInvalidateCaches;
begin
  RenderDone;
  RenderInit;
end;

end.
