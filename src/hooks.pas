unit hooks;

{ Global low-level keyboard/mouse hooks.
  The hook callbacks only copy tiny records into ring buffers and PostMessage
  a notification - they never block the input pipeline. The owning window
  drains the buffers when it receives the message. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, SyncObjs;

const
  HOOK_MSG_KB    = WM_APP + 1;  // keyboard events pending in ring buffer
  HOOK_MSG_MOUSE = WM_APP + 2;  // mouse events pending in ring buffer

type
  TKeyEvt = packed record
    Kind: Byte;       // 0 = down, 1 = up
    VK: Word;
    Scan: Word;
  end;
  PKeyEvt = ^TKeyEvt;

  TMouseEvt = packed record
    Kind: Byte;       // 0 = move, 1 = down, 2 = up, 3 = wheel
    Btn: Byte;        // 1 = L, 2 = R, 3 = M (ignored for move/wheel)
    X: LongInt;
    Y: LongInt;
    Delta: SmallInt;  // wheel delta
  end;
  PMouseEvt = ^TMouseEvt;

const
  MAX_KEY_EVENTS   = 256;
  MAX_MOUSE_EVENTS = 1024;

type
  TKeyEvtBuf  = array[0..MAX_KEY_EVENTS - 1] of TKeyEvt;
  TMouseEvtBuf = array[0..MAX_MOUSE_EVENTS - 1] of TMouseEvt;

var
  HooksEnabled: Boolean = True;   // consulted by hook procs (cheap master switch)

procedure InstallHooks(KbNotifyWnd, MouseNotifyWnd: HWND);
procedure UninstallHooks;
function  DrainKeyEvents(var buf: TKeyEvtBuf): Integer;
function  DrainMouseEvents(var buf: TMouseEvtBuf): Integer;

implementation

type
  TKbLLRec = packed record
    vkCode: DWORD;
    scanCode: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: PtrUInt;
  end;
  PKbLLRec = ^TKbLLRec;

  TMsLLRec = packed record
    pt: TPoint;
    mouseData: DWORD;
    flags: DWORD;
    time: DWORD;
    dwExtraInfo: PtrUInt;
  end;
  PMsLLRec = ^TMsLLRec;

const
  WM_KEYBOARD_DOWN = $0100;
  WM_KEYBOARD_UP   = $0101;
  WM_SYSKEY_DOWN   = $0104;
  WM_SYSKEY_UP     = $0105;
  WH_KEYBOARD_LL   = 13;   // not declared by FPC's Windows unit
  WH_MOUSE_LL      = 14;

var
  KbHook: HHOOK = 0;
  MouseHook: HHOOK = 0;
  KbWnd: HWND = 0;
  MouseWnd: HWND = 0;
  CS: TCriticalSection;

  KbBuf: TKeyEvtBuf;
  KbRead: Integer = 0;
  KbWrite: Integer = 0;
  MouseBuf: TMouseEvtBuf;
  MouseRead: Integer = 0;
  MouseWrite: Integer = 0;

function KbdHookProc(nCode: LongInt; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  rec: PKbLLRec;
  e: TKeyEvt;
  empty: Boolean;
begin
  if (nCode >= 0) and HooksEnabled then
  begin
    rec := PKbLLRec(lParam);
    e.Kind := 0;
    case wParam of
      WM_KEYBOARD_DOWN, WM_SYSKEY_DOWN: e.Kind := 0;
      WM_KEYBOARD_UP, WM_SYSKEY_UP:     e.Kind := 1;
    else
      e.Kind := $FF;
    end;
    if e.Kind <> $FF then
    begin
      e.VK := Word(rec^.vkCode);
      e.Scan := Word(rec^.scanCode);
      CS.Enter;
      try
        empty := KbRead = KbWrite;
        KbBuf[KbWrite] := e;
        KbWrite := (KbWrite + 1) mod MAX_KEY_EVENTS;
        if KbWrite = KbRead then   // overflow: drop oldest
          KbRead := (KbRead + 1) mod MAX_KEY_EVENTS;
      finally
        CS.Leave;
      end;
      if empty then
        PostMessage(KbWnd, HOOK_MSG_KB, 0, 0);
    end;
  end;
  Result := CallNextHookEx(KbHook, nCode, wParam, lParam);
end;

function MouseHookProc(nCode: LongInt; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
const
  WM_MOUSEMOVE   = $0200;
  WM_LBUTTONDOWN = $0201;
  WM_LBUTTONUP   = $0202;
  WM_RBUTTONDOWN = $0204;
  WM_RBUTTONUP   = $0205;
  WM_MBUTTONDOWN = $0207;
  WM_MBUTTONUP   = $0208;
  WM_MOUSEWHEEL  = $020A;
var
  rec: PMsLLRec;
  e: TMouseEvt;
  empty: Boolean;
begin
  if (nCode >= 0) and HooksEnabled then
  begin
    rec := PMsLLRec(lParam);
    e.Kind := $FF;
    e.Btn := 0;
    e.Delta := 0;
    case wParam of
      WM_MOUSEMOVE:
        begin e.Kind := 0; e.Btn := 0; end;
      WM_LBUTTONDOWN: begin e.Kind := 1; e.Btn := 1; end;
      WM_LBUTTONUP:   begin e.Kind := 2; e.Btn := 1; end;
      WM_RBUTTONDOWN: begin e.Kind := 1; e.Btn := 2; end;
      WM_RBUTTONUP:   begin e.Kind := 2; e.Btn := 2; end;
      WM_MBUTTONDOWN: begin e.Kind := 1; e.Btn := 3; end;
      WM_MBUTTONUP:   begin e.Kind := 2; e.Btn := 3; end;
      WM_MOUSEWHEEL:
        begin
          e.Kind := 3;
          e.Delta := SmallInt((rec^.mouseData shr 16) and $FFFF);
        end;
    end;
    if e.Kind <> $FF then
    begin
      e.X := rec^.pt.X;
      e.Y := rec^.pt.Y;
      CS.Enter;
      try
        empty := MouseRead = MouseWrite;
        MouseBuf[MouseWrite] := e;
        MouseWrite := (MouseWrite + 1) mod MAX_MOUSE_EVENTS;
        if MouseWrite = MouseRead then
          MouseRead := (MouseRead + 1) mod MAX_MOUSE_EVENTS;
      finally
        CS.Leave;
      end;
      if empty then
        PostMessage(MouseWnd, HOOK_MSG_MOUSE, 0, 0);
    end;
  end;
  Result := CallNextHookEx(MouseHook, nCode, wParam, lParam);
end;

procedure InstallHooks(KbNotifyWnd, MouseNotifyWnd: HWND);
begin
  KbWnd := KbNotifyWnd;
  MouseWnd := MouseNotifyWnd;
  if KbHook = 0 then
    KbHook := SetWindowsHookEx(WH_KEYBOARD_LL, TFNHookProc(@KbdHookProc),
      HInstance, 0);
  if MouseHook = 0 then
    MouseHook := SetWindowsHookEx(WH_MOUSE_LL, TFNHookProc(@MouseHookProc),
      HInstance, 0);
end;

procedure UninstallHooks;
begin
  if KbHook <> 0 then
  begin
    UnhookWindowsHookEx(KbHook);
    KbHook := 0;
  end;
  if MouseHook <> 0 then
  begin
    UnhookWindowsHookEx(MouseHook);
    MouseHook := 0;
  end;
end;

function DrainKeyEvents(var buf: TKeyEvtBuf): Integer;
begin
  Result := 0;
  CS.Enter;
  try
    while (KbRead <> KbWrite) and (Result < MAX_KEY_EVENTS) do
    begin
      buf[Result] := KbBuf[KbRead];
      KbRead := (KbRead + 1) mod MAX_KEY_EVENTS;
      Inc(Result);
    end;
  finally
    CS.Leave;
  end;
end;

function DrainMouseEvents(var buf: TMouseEvtBuf): Integer;
begin
  Result := 0;
  CS.Enter;
  try
    while (MouseRead <> MouseWrite) and (Result < MAX_MOUSE_EVENTS) do
    begin
      buf[Result] := MouseBuf[MouseRead];
      MouseRead := (MouseRead + 1) mod MAX_MOUSE_EVENTS;
      Inc(Result);
    end;
  finally
    CS.Leave;
  end;
end;

initialization
  CS := TCriticalSection.Create;

finalization
  UninstallHooks;
  CS.Free;

end.
