unit mouseoverlay;

{ Cursor-following mouse indicator: click ripples for L/R/M buttons and a
  scroll direction hint, drawn on a small click-through layered window. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, SysUtils;

procedure InitMouseOverlay;
procedure DoneMouseOverlay;
function  MouseOverlayWnd: HWND;
procedure MouseOverlayApplyConfig;

implementation

uses
  config, hooks, gdip;

const
  MO_CLASS = 'OctopusKeyMouseOverlay';
  RIPPLE_MS  = 350;
  WHEEL_MS   = 400;
  WND_SIZE   = 170;

var
  MoFam: PGpFontFamily = nil;
  MoFont: PGpFont = nil;
  MoFontPx: Single = -1;
  MoFmt: PGpStringFormat = nil;

procedure EnsureMouseFont;
var
  px: Single;
begin
  if MoFmt = nil then
  begin
    GdipCreateStringFormat(StringFormatFlagsNoWrap or StringFormatFlagsNoClip,
      0, MoFmt);
    if MoFmt <> nil then
    begin
      GdipSetStringFormatAlign(MoFmt, StringAlignmentCenter);
      GdipSetStringFormatLineAlign(MoFmt, StringAlignmentCenter);
    end;
  end;
  px := 18 * (Cfg.ScalePct / 100);
  if (MoFont = nil) or (MoFontPx <> px) then
  begin
    if MoFont <> nil then
      GdipDeleteFont(MoFont);
    MoFont := nil;
    if MoFam = nil then
      GdipCreateFontFamilyFromName('Segoe UI Symbol', nil, MoFam);
    if MoFam <> nil then
      GdipCreateFont(MoFam, px, FontStyleRegular, UnitPixel, MoFont);
    MoFontPx := px;
  end;
end;

procedure MouseFontDone;
begin
  if MoFont <> nil then begin GdipDeleteFont(MoFont); MoFont := nil; end;
  if MoFam <> nil then begin GdipDeleteFontFamily(MoFam); MoFam := nil; end;
  if MoFmt <> nil then begin GdipDeleteStringFormat(MoFmt); MoFmt := nil; end;
  MoFontPx := -1;
end;

type
  TRipple = record
    Btn: Byte;        // 1 L, 2 R, 3 M
    X, Y: LongInt;    // click position (screen coords)
    Born: Int64;
  end;

  TWheelHint = record
    Up: Boolean;
    X, Y: LongInt;
    Born: Int64;
  end;

var
  MoWnd: HWND = 0;
  Ripples: array of TRipple;
  Wheels: array of TWheelHint;
  MoShown: Boolean = False;

function Tck64: Int64; stdcall; external 'kernel32.dll' name 'GetTickCount64';

procedure RippleColor(btn: Byte; out color: DWORD);
begin
  case btn of
    1: color := $FF347CF6;   // LMB - accent blue
    2: color := $FF2DD4BF;   // RMB - teal
    3: color := $FFA78BFA;   // MMB - purple
  else
    color := $FF347CF6;
  end;
end;

procedure DrainMouse;
var
  buf: TMouseEvtBuf;
  n, i: Integer;
begin
  n := DrainMouseEvents(buf);
  for i := 0 to n - 1 do
  begin
    case buf[i].Kind of
      1:  // down
        begin
          SetLength(Ripples, Length(Ripples) + 1);
          with Ripples[High(Ripples)] do
          begin
            Btn := buf[i].Btn;
            X := buf[i].X;
            Y := buf[i].Y;
            Born := Tck64;
          end;
        end;
      3:  // wheel
        begin
          SetLength(Wheels, Length(Wheels) + 1);
          with Wheels[High(Wheels)] do
          begin
            Up := buf[i].Delta > 0;
            X := buf[i].X;
            Y := buf[i].Y;
            Born := Tck64;
          end;
        end;
    end;
  end;
  if n > 0 then
  begin
    // prune immediately if lists get long
    while Length(Ripples) > 12 do
    begin
      for i := 0 to High(Ripples) - 1 do
        Ripples[i] := Ripples[i + 1];
      SetLength(Ripples, Length(Ripples) - 1);
    end;
    while Length(Wheels) > 6 do
    begin
      for i := 0 to High(Wheels) - 1 do
        Wheels[i] := Wheels[i + 1];
      SetLength(Wheels, Length(Wheels) - 1);
    end;
  end;
end;

procedure RenderMouseTick;
var
  now: Int64;
  i, j: Integer;
  c: TPoint;
  half: Integer;
  bmp: PGpBitmap;
  g: PGpGraphics;
  hbm: HBITMAP;
  dcS, dcM: HDC;
  oldObj: HGDIOBJ;
  blend: TBlendFunction;
  pt, psrc: TPoint;
  sz: TSizeRec;
  p, alpha: Double;
  color: DWORD;
  brush: PGpBrush;
  pen: PGpPen;
  path: PGpPath;
  r, offX, offY: Single;
  s: Single;
  rc: TGPRectF;
  keep: Boolean;
  us: UnicodeString;
begin
  if MoWnd = 0 then
    Exit;
  now := Tck64;

  // prune expired
  j := 0;
  for i := 0 to High(Ripples) do
  begin
    keep := now - Ripples[i].Born < RIPPLE_MS;
    if keep then
    begin
      if j <> i then Ripples[j] := Ripples[i];
      Inc(j);
    end;
  end;
  SetLength(Ripples, j);
  j := 0;
  for i := 0 to High(Wheels) do
  begin
    keep := now - Wheels[i].Born < WHEEL_MS;
    if keep then
    begin
      if j <> i then Wheels[j] := Wheels[i];
      Inc(j);
    end;
  end;
  SetLength(Wheels, j);

  if (Length(Ripples) = 0) and (Length(Wheels) = 0) then
  begin
    if MoShown then
    begin
      ShowWindow(MoWnd, SW_HIDE);
      MoShown := False;
    end;
    Exit;
  end;

  if not Cfg.MouseEnabled then
  begin
    if MoShown then
    begin
      ShowWindow(MoWnd, SW_HIDE);
      MoShown := False;
    end;
    Exit;
  end;

  GetCursorPos(c);
  half := WND_SIZE div 2;
  pt.X := c.X - half;
  pt.Y := c.Y - half;
  // keep inside primary screen
  if pt.X < 0 then pt.X := 0;
  if pt.Y < 0 then pt.Y := 0;
  if pt.X + WND_SIZE > GetSystemMetrics(SM_CXSCREEN) then
    pt.X := GetSystemMetrics(SM_CXSCREEN) - WND_SIZE;
  if pt.Y + WND_SIZE > GetSystemMetrics(SM_CYSCREEN) then
    pt.Y := GetSystemMetrics(SM_CYSCREEN) - WND_SIZE;

  s := Cfg.ScalePct / 100;
  bmp := nil;
  if GdipCreateBitmapFromScan0(WND_SIZE, WND_SIZE, 0, PixelFormat32bppPARGB,
    nil, bmp) <> 0 then
    Exit;
  g := nil;
  GdipGetImageGraphicsContext(bmp, g);
  if g <> nil then
  begin
    GdipSetSmoothingMode(g, SmoothingModeAntiAlias);
    for i := 0 to High(Ripples) do
    begin
      p := (now - Ripples[i].Born) / RIPPLE_MS;
      alpha := (1 - p) * 0.75;
      RippleColor(Ripples[i].Btn, color);
      offX := Ripples[i].X - c.X;
      offY := Ripples[i].Y - c.Y;
      if offX < -60 then offX := -60;
      if offX > 60 then offX := 60;
      if offY < -60 then offY := -60;
      if offY > 60 then offY := 60;
      r := (7 + 26 * p) * s;
      path := nil;
      if GdipCreatePath(FillModeWinding, path) = 0 then
      begin
        GdipAddPathEllipse(path, half + offX - r, half + offY - r, 2 * r, 2 * r);
        pen := nil;
        if GdipCreatePen1(MulAlpha(color, Round(alpha * 255)), 3 * s,
          UnitPixel, pen) = 0 then
        begin
          GdipDrawPath(g, pen, path);
          GdipDeletePen(pen);
        end;
        GdipDeletePath(path);
      end;
      // solid dot at the very center of a fresh click
      if p < 0.35 then
      begin
        r := 5 * s;
        path := nil;
        if GdipCreatePath(FillModeWinding, path) = 0 then
        begin
          GdipAddPathEllipse(path, half + offX - r, half + offY - r, 2 * r, 2 * r);
          GdipCreateSolidFill(MulAlpha(color, Round(alpha * 255)), brush);
          GdipFillPath(g, brush, path);
          GdipDeleteBrush(brush);
          GdipDeletePath(path);
        end;
      end;
    end;
    for i := 0 to High(Wheels) do
    begin
      p := (now - Wheels[i].Born) / WHEEL_MS;
      alpha := (1 - p) * 0.8;
      offX := Wheels[i].X - c.X;
      offY := Wheels[i].Y - c.Y;
      if offX < -60 then offX := -60;
      if offX > 60 then offX := 60;
      if offY < -60 then offY := -60;
      if offY > 60 then offY := 60;
      EnsureMouseFont;
      if MoFont <> nil then
      begin
        rc.X := half + offX - 1000;
        rc.Y := half + offY - 1000;
        rc.Width := 2000;
        rc.Height := 2000;
        if Wheels[i].Up then
          us := WideChar($2191)
        else
          us := WideChar($2193);
        GdipCreateSolidFill(MulAlpha($FFEAEAF2, Round(alpha * 255)), brush);
        GdipDrawString(g, PWideChar(us), Length(us), MoFont, @rc, MoFmt, brush);
        GdipDeleteBrush(brush);
      end;
    end;
    GdipDeleteGraphics(g);
  end;
  hbm := 0;
  GdipCreateHBITMAPFromBitmap(bmp, hbm, 0);
  GdipDisposeImage(bmp);
  if hbm <> 0 then
  begin
    if not MoShown then
    begin
      ShowWindow(MoWnd, SW_SHOWNA);
      MoShown := True;
    end;
    dcS := GetDC(0);
    dcM := CreateCompatibleDC(dcS);
    oldObj := SelectObject(dcM, hbm);
    blend.BlendOp := AC_SRC_OVER;
    blend.BlendFlags := 0;
    blend.SourceConstantAlpha := 255;
    blend.AlphaFormat := AC_SRC_ALPHA;
    psrc.X := 0; psrc.Y := 0;
    sz.cx := WND_SIZE; sz.cy := WND_SIZE;
    UpdateLayeredWindow(MoWnd, dcS, @pt, @sz, dcM, @psrc, 0, @blend, ULW_ALPHA);
    SelectObject(dcM, oldObj);
    DeleteDC(dcM);
    ReleaseDC(0, dcS);
    DeleteObject(hbm);
  end;
end;

function MouseWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  ps: TPaintStruct;
begin
  case Msg of
    WM_TIMER: begin RenderMouseTick; Result := 0; end;
    HOOK_MSG_MOUSE: begin DrainMouse; Result := 0; end;
    WM_ERASEBKGND: Result := 1;
    WM_PAINT:
      begin
        BeginPaint(hWnd, ps);
        EndPaint(hWnd, ps);
        Result := 0;
      end;
    WM_DESTROY:
      begin
        KillTimer(hWnd, 1);
        Result := 0;
      end;
  else
    Result := DefWindowProc(hWnd, Msg, wParam, lParam);
  end;
end;

procedure InitMouseOverlay;
type
  TMouseWndProc = function(hWnd: HWND; Msg: UINT; wParam: WPARAM;
    lParam: LPARAM): LRESULT; stdcall;
var
  wc: TWndClass;
begin
  FillChar(wc, SizeOf(wc), 0);
  wc.lpfnWndProc := TMouseWndProc(@MouseWndProc);
  wc.hInstance := HInstance;
  wc.lpszClassName := MO_CLASS;
  RegisterClass(wc);
  MoWnd := CreateWindowEx(
    WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_TOPMOST or
    WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE,
    MO_CLASS, '', WS_POPUP, 0, 0, WND_SIZE, WND_SIZE, 0, 0, HInstance, nil);
  SetTimer(MoWnd, 1, 16, nil);
end;

procedure DoneMouseOverlay;
begin
  if MoWnd <> 0 then
  begin
    KillTimer(MoWnd, 1);
    DestroyWindow(MoWnd);
    MoWnd := 0;
  end;
  MouseFontDone;
end;

function MouseOverlayWnd: HWND;
begin
  Result := MoWnd;
end;

procedure MouseOverlayApplyConfig;
begin
  // nothing cached; next tick picks up new settings
end;

end.
