unit overlay;

{ Keyboard visualization overlay: a per-pixel-alpha layered window rendering
  keycap rows. Owns the cluster state machine (press -> cluster -> hold ->
  fade) and the history trail. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, SysUtils, Math, config, keymap, hooks;

const
  OV_MSG_APPLYCFG = WM_APP + 3;

procedure InitOverlay;
procedure DoneOverlay;
function  OverlayWnd: HWND;
procedure OverlayApplyConfig;
procedure ShowDemoCombo(const vks: array of Integer);

implementation

uses
  render, gdip;

const
  OV_CLASS = 'OctopusKeyOverlay';
  MERGE_BACK_MS   = 220;    // key released recently -> next key joins that cluster
  FORCE_RELEASE_MS = 5000;  // stuck-down safety valve

type
  TClusterKey = record
    VK: Integer;
    Text: string;
    Glyph: Word;
    Symbol: Boolean;
    IsMod: Boolean;
  end;

  TCluster = record
    Keys: array of TClusterKey;
    DownCount: Integer;
    BornTick: Int64;
    ReleaseTick: Int64;
  end;

  TRowInfo = record
    Items: TKeyItemArr;
    RowAlpha: Byte;   // entry*exit*opacity, 0..255
    YOff: Single;
  end;

var
  OvWnd: HWND = 0;
  Clusters: array of TCluster;
  HeldVKs: array of Integer;
  HeldDownTick: array of Int64;
  BlackVKs: array of Integer;
  Shown: Boolean = False;
  Dirty: Boolean = False;

function Tck64: Int64; stdcall; external 'kernel32.dll' name 'GetTickCount64';

function VKInList(const list: array of Integer; vk: Integer): Integer;
var
  i: Integer;
begin
  for i := High(list) downto 0 do
    if list[i] = vk then
      Exit(i);
  Result := -1;
end;

procedure ParseBlacklist;
var
  tmp: string;
  parts: TStringArray;
  i, vk: Integer;
begin
  SetLength(BlackVKs, 0);
  tmp := StringReplace(Cfg.Blacklist, ' ', ',', [rfReplaceAll]);
  if Trim(tmp) = '' then
    Exit;
  parts := tmp.Split([',']);
  for i := 0 to High(parts) do
  begin
    vk := VKFromKeyName(Trim(parts[i]));
    if vk <> 0 then
    begin
      vk := NormalizeVK(vk);
      if VKInList(BlackVKs, vk) < 0 then
      begin
        SetLength(BlackVKs, Length(BlackVKs) + 1);
        BlackVKs[High(BlackVKs)] := vk;
      end;
    end;
  end;
end;

function IsBlacklisted(vk: Integer): Boolean;
begin
  Result := VKInList(BlackVKs, vk) >= 0;
end;

procedure HandleKey(const e: TKeyEvt);
var
  nkv, idx, i, j, gi: Integer;
  now: Int64;
  cap: TKeyCap;
begin
  nkv := NormalizeVK(e.VK);
  now := Tck64;
  if e.Kind = 0 then
  begin
    idx := VKInList(HeldVKs, nkv);
    if idx >= 0 then
    begin
      if now - HeldDownTick[idx] > 600 then
      begin
        // missed keyup (hook disabled meanwhile etc.) - reset down state
        for i := 0 to High(Clusters) do
          if Clusters[i].DownCount > 0 then
          begin
            Clusters[i].DownCount := 0;
            Clusters[i].ReleaseTick := now;
          end;
        SetLength(HeldVKs, 0);
        SetLength(HeldDownTick, 0);
        idx := -1;
      end
      else
        Exit;  // auto-repeat or duplicate down
    end;
    SetLength(HeldVKs, Length(HeldVKs) + 1);
    HeldVKs[High(HeldVKs)] := nkv;
    SetLength(HeldDownTick, Length(HeldDownTick) + 1);
    HeldDownTick[High(HeldDownTick)] := now;
    if (not Cfg.Enabled) or IsBlacklisted(nkv) then
      Exit;
    cap := KeyCapFor(e.VK, e.Scan);
    // merge with newest cluster?
    if Length(Clusters) > 0 then
    begin
      i := High(Clusters);
      if (Clusters[i].DownCount > 0) or
         (now - Clusters[i].ReleaseTick < MERGE_BACK_MS) then
      begin
        j := -1;
        for gi := 0 to High(Clusters[i].Keys) do
          if Clusters[i].Keys[gi].VK = nkv then
          begin
            j := gi;
            Break;
          end;
        if j < 0 then
        begin
          SetLength(Clusters[i].Keys, Length(Clusters[i].Keys) + 1);
          with Clusters[i].Keys[High(Clusters[i].Keys)] do
          begin
            VK := nkv;
            Text := cap.Text;
            Glyph := cap.Glyph;
            Symbol := cap.Symbol;
            IsMod := cap.IsMod;
          end;
        end;
        Inc(Clusters[i].DownCount);
        if Clusters[i].ReleaseTick > 0 then
          Clusters[i].ReleaseTick := 0;   // revived
        Dirty := True;
        Exit;
      end;
    end;
    // start a new cluster
    SetLength(Clusters, Length(Clusters) + 1);
    with Clusters[High(Clusters)] do
    begin
      SetLength(Keys, 1);
      Keys[0].VK := nkv;
      Keys[0].Text := cap.Text;
      Keys[0].Glyph := cap.Glyph;
      Keys[0].Symbol := cap.Symbol;
      Keys[0].IsMod := cap.IsMod;
      DownCount := 1;
      BornTick := now;
      ReleaseTick := 0;
    end;
    Dirty := True;
  end
  else
  begin
    idx := VKInList(HeldVKs, nkv);
    if idx >= 0 then
    begin
      for i := idx to High(HeldVKs) - 1 do
      begin
        HeldVKs[i] := HeldVKs[i + 1];
        HeldDownTick[i] := HeldDownTick[i + 1];
      end;
      SetLength(HeldVKs, Length(HeldVKs) - 1);
      SetLength(HeldDownTick, Length(HeldDownTick) - 1);
    end;
    for i := High(Clusters) downto 0 do
      if Clusters[i].DownCount > 0 then
      begin
        j := -1;
        for gi := 0 to High(Clusters[i].Keys) do
          if Clusters[i].Keys[gi].VK = nkv then
          begin
            j := gi;
            Break;
          end;
        if j >= 0 then
        begin
          Dec(Clusters[i].DownCount);
          if Clusters[i].DownCount <= 0 then
          begin
            Clusters[i].DownCount := 0;
            Clusters[i].ReleaseTick := now;
          end;
          Dirty := True;
          Break;
        end;
      end;
  end;
end;

procedure DrainKeys;
var
  buf: TKeyEvtBuf;
  n, i: Integer;
begin
  n := DrainKeyEvents(buf);
  for i := 0 to n - 1 do
    HandleKey(buf[i]);
end;

procedure RenderTick;
var
  now: Int64;
  i, j, gi, k, n, maxKeep, winW, winH, xL, yTop, distFromBottom: Integer;
  entryP, exitP, alpha, t: Double;
  rows: array of TRowInfo;
  m: TMetrics;
  rowW, maxW, yRow: Single;
  wa: TRect;
  bmp: PGpBitmap;
  g: PGpGraphics;
  hbm: HBITMAP;
  dcS, dcM: HDC;
  oldObj: HGDIOBJ;
  blend: TBlendFunction;
  pt, psrc: TPoint;
  sz: TSizeRec;
  cap: TKeyCap;
  finished, needAnim, onlyMods: Boolean;
begin
  if OvWnd = 0 then
    Exit;
  now := Tck64;

  // stuck-down safety valve
  for i := 0 to High(Clusters) do
    if (Clusters[i].DownCount > 0) and (now - Clusters[i].BornTick > FORCE_RELEASE_MS) then
    begin
      Clusters[i].DownCount := 0;
      Clusters[i].ReleaseTick := now;
      Dirty := True;
    end;

  // build visible rows (oldest first)
  SetLength(rows, Length(Clusters));
  n := 0;
  needAnim := False;
  for i := 0 to High(Clusters) do
  begin
    entryP := 1;
    exitP := 0;
    if Cfg.EntryMs > 0 then
    begin
      t := (now - Clusters[i].BornTick) / Cfg.EntryMs;
      if t < 1 then entryP := t;
    end;
    if (Clusters[i].DownCount = 0) and (Cfg.ExitMs > 0) then
    begin
      t := (now - Clusters[i].ReleaseTick - Cfg.HoldMs) / Cfg.ExitMs;
      if t > 0 then exitP := t;
      if exitP > 1 then exitP := 1;
    end;
    if (Clusters[i].DownCount = 0) and (exitP >= 1) then
      Continue;   // finished, drops out
    if Cfg.CombosOnly and (Length(Clusters[i].Keys) < 2) then
      Continue;
    if not Cfg.ShowModsAlone then
    begin
      onlyMods := True;
      for j := 0 to High(Clusters[i].Keys) do
        if not Clusters[i].Keys[j].IsMod then
        begin
          onlyMods := False;
          Break;
        end;
      if onlyMods then
        Continue;
    end;
    alpha := entryP * (1 - exitP);
    if alpha <= 0 then
      Continue;
    with rows[n] do
    begin
      SetLength(Items, Length(Clusters[i].Keys));
      k := 0;
      for gi := MOG_CTRL to MOG_WIN do
        for j := 0 to High(Clusters[i].Keys) do
          if Clusters[i].Keys[j].IsMod and
             (ModGroupOf(Clusters[i].Keys[j].VK) = gi) then
          begin
            Items[k].Text := Clusters[i].Keys[j].Text;
            Items[k].Glyph := Clusters[i].Keys[j].Glyph;
            Items[k].Symbol := Clusters[i].Keys[j].Symbol;
            Items[k].IsMod := True;
            Items[k].X := 0;
            Items[k].W := 0;
            Inc(k);
          end;
      for j := 0 to High(Clusters[i].Keys) do
        if not Clusters[i].Keys[j].IsMod then
        begin
          Items[k].Text := Clusters[i].Keys[j].Text;
          Items[k].Glyph := Clusters[i].Keys[j].Glyph;
          Items[k].Symbol := Clusters[i].Keys[j].Symbol;
          Items[k].IsMod := False;
          Items[k].X := 0;
          Items[k].W := 0;
          Inc(k);
        end;
      RowAlpha := Round(alpha * 255 * Cfg.OpacityPct / 100);
      YOff := (1 - entryP) * 14 * (Cfg.ScalePct / 100);
    end;
    Inc(n);
    if (entryP < 1) or (exitP > 0) then
      needAnim := True;
  end;
  SetLength(rows, n);

  // remove finished clusters, cap trail length
  j := 0;
  for i := 0 to High(Clusters) do
  begin
    finished := (Clusters[i].DownCount = 0) and
      (now - Clusters[i].ReleaseTick >= Cfg.HoldMs + Cfg.ExitMs + 50);
    if not finished then
    begin
      if j <> i then
        Clusters[j] := Clusters[i];
      Inc(j);
    end;
  end;
  SetLength(Clusters, j);
  maxKeep := Cfg.TrailCount + 2;
  if maxKeep < 1 then maxKeep := 1;
  if Length(Clusters) > maxKeep then
  begin
    k := Length(Clusters) - maxKeep;
    for i := k to High(Clusters) do
      Clusters[i - k] := Clusters[i];
    SetLength(Clusters, maxKeep);
  end;

  if (n = 0) or (not Cfg.Enabled) then
  begin
    if Shown then
    begin
      ShowWindow(OvWnd, SW_HIDE);
      Shown := False;
    end;
    Dirty := False;
    Exit;
  end;

  if (not Dirty) and (not needAnim) then
    Exit;  // nothing changed, idle

  m := GetMetrics;

  // measure rows
  maxW := 0;
  for i := 0 to n - 1 do
  begin
    rowW := MeasureRow(rows[i].Items, m);
    if rowW > maxW then
      maxW := rowW;
  end;
  winW := Ceil(maxW) + 8;
  if winW < Ceil(m.CapH) + 8 then
    winW := Ceil(m.CapH) + 8;
  winH := Ceil(n * m.CapH + (n - 1) * m.RowGap) + 8;

  // anchor position within primary work area
  SystemParametersInfo(SPI_GETWORKAREA, 0, @wa, 0);
  case Cfg.AnchorY of
    ANCHOR_BOTTOM: yTop := wa.Bottom - Cfg.MarginPx - winH;
    ANCHOR_MIDDLE: yTop := (wa.Top + wa.Bottom - winH) div 2;
  else
    yTop := wa.Top + Cfg.MarginPx;
  end;
  case Cfg.AnchorX of
    ANCHOR_CENTER: xL := (wa.Left + wa.Right - winW) div 2;
    ANCHOR_LEFT:   xL := wa.Left + Cfg.MarginPx;
  else
    xL := wa.Right - Cfg.MarginPx - winW;
  end;
  if xL < wa.Left then xL := wa.Left;
  if yTop < wa.Top then yTop := wa.Top;
  if xL + winW > wa.Right then xL := wa.Right - winW;
  if yTop + winH > wa.Bottom then yTop := wa.Bottom - winH;

  // draw
  bmp := nil;
  if GdipCreateBitmapFromScan0(winW, winH, 0, PixelFormat32bppPARGB, nil, bmp) <> 0 then
    Exit;
  g := nil;
  GdipGetImageGraphicsContext(bmp, g);
  if g <> nil then
  begin
    GdipSetSmoothingMode(g, SmoothingModeAntiAlias);
    GdipSetTextRenderingHint(g, TextRenderingHintAntiAliasGridFit);
    for i := 0 to n - 1 do
    begin
      distFromBottom := n - 1 - i;
      yRow := winH - 4 - m.CapH - distFromBottom * (m.CapH + m.RowGap);
      DrawRow(g, rows[i].Items, yRow + rows[i].YOff, rows[i].RowAlpha, m);
    end;
    GdipDeleteGraphics(g);
  end;
  hbm := 0;
  GdipCreateHBITMAPFromBitmap(bmp, hbm, 0);
  GdipDisposeImage(bmp);
  if hbm <> 0 then
  begin
    if not Shown then
    begin
      ShowWindow(OvWnd, SW_SHOWNA);
      Shown := True;
    end;
    dcS := GetDC(0);
    dcM := CreateCompatibleDC(dcS);
    oldObj := SelectObject(dcM, hbm);
    blend.BlendOp := AC_SRC_OVER;
    blend.BlendFlags := 0;
    blend.SourceConstantAlpha := 255;
    blend.AlphaFormat := AC_SRC_ALPHA;
    pt.X := xL; pt.Y := yTop;
    psrc.X := 0; psrc.Y := 0;
    sz.cx := winW; sz.cy := winH;
    UpdateLayeredWindow(OvWnd, dcS, @pt, @sz, dcM, @psrc, 0, @blend, ULW_ALPHA);
    SelectObject(dcM, oldObj);
    DeleteDC(dcM);
    ReleaseDC(0, dcS);
    DeleteObject(hbm);
  end;
  Dirty := False;
end;

procedure ShowDemoCombo(const vks: array of Integer);
var
  i: Integer;
  cap: TKeyCap;
begin
  SetLength(Clusters, Length(Clusters) + 1);
  with Clusters[High(Clusters)] do
  begin
    SetLength(Keys, Length(vks));
    for i := 0 to High(vks) do
    begin
      cap := KeyCapFor(vks[i], 0);
      Keys[i].VK := NormalizeVK(vks[i]);
      Keys[i].Text := cap.Text;
      Keys[i].Glyph := cap.Glyph;
      Keys[i].Symbol := cap.Symbol;
      Keys[i].IsMod := cap.IsMod;
    end;
    DownCount := 0;
    BornTick := Tck64;
    ReleaseTick := Tck64;
  end;
  Dirty := True;
end;

function OverlayWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var
  ps: TPaintStruct;
begin
  case Msg of
    WM_TIMER:
      begin
        try
          RenderTick;
        except
          // never let a render glitch kill the timer or the input pipeline
        end;
        Result := 0;
      end;
    HOOK_MSG_KB:
      begin
        try
          DrainKeys;
        except
          // never let a key event kill the overlay
        end;
        Result := 0;
      end;
    OV_MSG_APPLYCFG:
      begin
        ParseBlacklist;
        RenderInvalidateCaches;
        Dirty := True;
        Result := 0;
      end;
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

procedure InitOverlay;
type
  TOvrWndProc = function(hWnd: HWND; Msg: UINT; wParam: WPARAM;
    lParam: LPARAM): LRESULT; stdcall;
var
  wc: TWndClass;
begin
  FillChar(wc, SizeOf(wc), 0);
  wc.lpfnWndProc := TOvrWndProc(@OverlayWndProc);
  wc.hInstance := HInstance;
  wc.lpszClassName := OV_CLASS;
  RegisterClass(wc);
  OvWnd := CreateWindowEx(
    WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_TOPMOST or
    WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE,
    OV_CLASS, '', WS_POPUP, 0, 0, 1, 1, 0, 0, HInstance, nil);
  SetTimer(OvWnd, 1, 16, nil);
  ParseBlacklist;
  RenderInit;
  Dirty := True;
end;

procedure DoneOverlay;
begin
  if OvWnd <> 0 then
  begin
    KillTimer(OvWnd, 1);
    DestroyWindow(OvWnd);
    OvWnd := 0;
  end;
  RenderDone;
end;

function OverlayWnd: HWND;
begin
  Result := OvWnd;
end;

procedure OverlayApplyConfig;
begin
  if OvWnd <> 0 then
    PostMessage(OvWnd, OV_MSG_APPLYCFG, 0, 0);
end;

end.
