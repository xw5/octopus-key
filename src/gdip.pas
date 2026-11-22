unit gdip;

{ Minimal flat-API binding for gdiplus.dll - only what OctopusKey needs.
  Windows ships gdiplus.dll since XP, so no extra dependency. }

{$mode objfpc}{$H+}

interface

uses
  Windows;

const
  // pixel formats
  PixelFormat32bppARGB  = $0026200A;
  PixelFormat32bppPARGB = $000E200B;

  // enums (values from GdiplusEnums.h)
  UnitPixel                         = 2;
  FillModeWinding                   = 1;
  SmoothingModeAntiAlias            = 4;
  TextRenderingHintAntiAliasGridFit = 3;
  StringAlignmentCenter             = 1;
  StringFormatFlagsNoWrap           = $00001000;
  StringFormatFlagsNoClip           = $00004000;
  FontStyleRegular                  = 0;
  FontStyleBold                     = 1;
  HotkeyPrefixNone                  = 1;
  AC_SRC_OVER                       = 0;
  AC_SRC_ALPHA                      = 1;
  ULW_ALPHA                         = $00000002;

type
  GpStatus       = DWORD;
  PGpBitmap      = Pointer;
  PGpGraphics    = Pointer;
  PGpBrush       = Pointer;
  PGpPen         = Pointer;
  PGpPath        = Pointer;
  PGpFontFamily  = Pointer;
  PGpFont        = Pointer;
  PGpStringFormat = Pointer;

  PGPRectF = ^TGPRectF;
  TGPRectF = record
    X, Y, Width, Height: Single;
  end;

  PGdiplusBitmapData = ^TGdiplusBitmapData;
  TGdiplusBitmapData = record
    Width: UINT;
    Height: UINT;
    Stride: Integer;
    PixelFormat: Integer;
    Scan0: Pointer;
    Reserved: Pointer;
  end;

  PGdiplusStartupInput = ^TGdiplusStartupInput;
  TGdiplusStartupInput = record
    GdiplusVersion: UINT;
    DebugEventCallback: Pointer;
    SuppressBackgroundThread: BOOL;
    SuppressExternalCodecs: BOOL;
  end;

  PBlendFunction = ^TBlendFunction;
  TBlendFunction = record
    BlendOp: Byte;
    BlendFlags: Byte;
    SourceConstantAlpha: Byte;
    AlphaFormat: Byte;
  end;

  PSizeRec = ^TSizeRec;
  TSizeRec = packed record
    cx, cy: LongInt;
  end;

function  GDIPlusAvailable: Boolean;
procedure GDIPlusInit;
procedure GDIPlusDone;

// helpers
function  Argb(a, r, g, b: Byte): DWORD;
function  MulAlpha(color: DWORD; alphaMul: Byte): DWORD;

// flat API
function GdipCreateBitmapFromScan0(width, height, stride, format: LongInt;
  scan0: PBYTE; var bitmap: PGpBitmap): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipDisposeImage(image: PGpBitmap): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipGetImageGraphicsContext(image: PGpBitmap;
  var graphics: PGpGraphics): GpStatus; stdcall; external 'gdiplus.dll';
function GdipDeleteGraphics(graphics: PGpGraphics): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipCreateSolidFill(color: DWORD; var brush: PGpBrush): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipDeleteBrush(brush: PGpBrush): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipCreatePen1(color: DWORD; width: Single; unit_: LongInt;
  var pen: PGpPen): GpStatus; stdcall; external 'gdiplus.dll';
function GdipDeletePen(pen: PGpPen): GpStatus; stdcall; external 'gdiplus.dll';
function GdipCreatePath(fillMode: LongInt; var path: PGpPath): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipDeletePath(path: PGpPath): GpStatus; stdcall; external 'gdiplus.dll';
function GdipAddPathArc(path: PGpPath; x, y, width, height, startAngle,
  sweepAngle: Single): GpStatus; stdcall; external 'gdiplus.dll';
function GdipAddPathEllipse(path: PGpPath; x, y, width, height: Single): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipClosePathFigure(path: PGpPath): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipDrawPath(graphics: PGpGraphics; pen: PGpPen;
  path: PGpPath): GpStatus; stdcall; external 'gdiplus.dll';
function GdipFillPath(graphics: PGpGraphics; brush: PGpBrush;
  path: PGpPath): GpStatus; stdcall; external 'gdiplus.dll';
function GdipCreateFontFamilyFromName(name: PWideChar; fontCollection: Pointer;
  var family: PGpFontFamily): GpStatus; stdcall; external 'gdiplus.dll';
function GdipDeleteFontFamily(family: PGpFontFamily): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipCreateFont(family: PGpFontFamily; emSize: Single; style: LongInt;
  unit_: LongInt; var font: PGpFont): GpStatus; stdcall; external 'gdiplus.dll';
function GdipDeleteFont(font: PGpFont): GpStatus; stdcall; external 'gdiplus.dll';
function GdipCreateStringFormat(flags: UINT; language: Word;
  var format: PGpStringFormat): GpStatus; stdcall; external 'gdiplus.dll';
function GdipDeleteStringFormat(format: PGpStringFormat): GpStatus; stdcall;
  external 'gdiplus.dll';
function GdipSetStringFormatAlign(format: PGpStringFormat;
  align: LongInt): GpStatus; stdcall; external 'gdiplus.dll';
function GdipSetStringFormatLineAlign(format: PGpStringFormat;
  align: LongInt): GpStatus; stdcall; external 'gdiplus.dll';
function GdipSetStringFormatHotkeyPrefix(format: PGpStringFormat;
  hotkeyPrefix: LongInt): GpStatus; stdcall; external 'gdiplus.dll';
function GdipSetSmoothingMode(graphics: PGpGraphics;
  smoothingMode: LongInt): GpStatus; stdcall; external 'gdiplus.dll';
function GdipSetTextRenderingHint(graphics: PGpGraphics;
  textRenderingHint: LongInt): GpStatus; stdcall; external 'gdiplus.dll';
function GdipDrawString(graphics: PGpGraphics; text: PWideChar; length: LongInt;
  font: PGpFont; layoutRect: PGPRectF; format: PGpStringFormat;
  brush: PGpBrush): GpStatus; stdcall; external 'gdiplus.dll';
function GdipMeasureString(graphics: PGpGraphics; text: PWideChar;
  length: LongInt; font: PGpFont; layoutRect: PGPRectF;
  format: PGpStringFormat; boundingRect: PGPRectF; codepointsFitted: PLongInt;
  stringsFilled: PLongInt): GpStatus; stdcall; external 'gdiplus.dll';
function GdipCreateHBITMAPFromBitmap(bitmap: PGpBitmap; var hbmReturn: HBITMAP;
  background: DWORD): GpStatus; stdcall; external 'gdiplus.dll';
function GdipBitmapGetPixel(bitmap: PGpBitmap; x, y: LongInt;
  var color: DWORD): GpStatus; stdcall; external 'gdiplus.dll';
function GdipGraphicsClear(graphics: PGpGraphics; color: DWORD): GpStatus; stdcall;
  external 'gdiplus.dll';
function UpdateLayeredWindow(hWnd: HWND; hdcDst: HDC; pptDst: PPoint;
  psize: PSizeRec; hdcSrc: HDC; pptSrc: PPoint; crKey: COLORREF;
  pblend: PBlendFunction; dwFlags: DWORD): BOOL; stdcall;
  external 'user32.dll';
function GdiplusStartup(var token: PtrUInt; input: PGdiplusStartupInput;
  output: Pointer): GpStatus; stdcall; external 'gdiplus.dll';
procedure GdiplusShutdown(token: PtrUInt); stdcall; external 'gdiplus.dll';

implementation

var
  GDIPToken: PtrUInt = 0;
  GDIPFailed: Boolean = False;

function GDIPlusAvailable: Boolean;
begin
  Result := not GDIPFailed;
end;

procedure GDIPlusInit;
var
  si: TGdiplusStartupInput;
begin
  if GDIPToken <> 0 then
    Exit;
  si.GdiplusVersion := 1;
  si.DebugEventCallback := nil;
  si.SuppressBackgroundThread := False;
  si.SuppressExternalCodecs := False;
  if GdiplusStartup(GDIPToken, @si, nil) <> 0 then
  begin
    GDIPFailed := True;
    GDIPToken := 0;
  end;
end;

procedure GDIPlusDone;
begin
  if GDIPToken <> 0 then
  begin
    GdiplusShutdown(GDIPToken);
    GDIPToken := 0;
  end;
end;

function Argb(a, r, g, b: Byte): DWORD;
begin
  Result := (DWORD(a) shl 24) or (DWORD(r) shl 16) or (DWORD(g) shl 8) or DWORD(b);
end;

function MulAlpha(color: DWORD; alphaMul: Byte): DWORD;
var
  a: DWORD;
begin
  if alphaMul = 255 then
    Exit(color);
  a := ((color shr 24) * alphaMul) div 255;
  Result := (a shl 24) or (color and $00FFFFFF);
end;

end.
