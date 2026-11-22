unit keymap;

{ VK code -> keycap label mapping, plus normalization of L/R modifier codes. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

const
  // modifier groups (fixed display order: Ctrl, Alt, Shift, Win)
  MOG_CTRL = 0;
  MOG_ALT  = 1;
  MOG_SHIFT = 2;
  MOG_WIN  = 3;
  NOT_MOD  = -1;

type
  TKeyCap = record
    Text: string;
    Glyph: Word;       // when <> 0, draw this codepoint with the symbol font
    Symbol: Boolean;
    IsMod: Boolean;
  end;

// map L/R variants to a single VK (160->16, 161->16, 162->17, ...)
function NormalizeVK(VK: Integer): Integer;
function IsModifierVK(VK: Integer): Boolean;
function ModGroupOf(VK: Integer): Integer;   // NOT_MOD when not a modifier
function KeyCapFor(VK, Scan: Integer): TKeyCap;
function VKFromKeyName(const AName: string): Integer;  // for the blacklist
function Sym(code: Integer): string;         // Unicode codepoint -> UTF-8

implementation

// Unicode codepoint -> UTF-8 project string (manual encoding: immune to
// system codepage conversions, which mangle >= $80 codepoints)
function Sym(code: Integer): string;
begin
  Result := '';
  case code of
    $00..$7F:
      begin SetLength(Result, 1); Result[1] := Chr(code); end;
    $80..$7FF:
      begin
        SetLength(Result, 2);
        Result[1] := Chr($C0 or (code shr 6));
        Result[2] := Chr($80 or (code and $3F));
      end;
  else
    begin
      SetLength(Result, 3);
      Result[1] := Chr($E0 or (code shr 12));
      Result[2] := Chr($80 or ((code shr 6) and $3F));
      Result[3] := Chr($80 or (code and $3F));
    end;
  end;
end;

function LayoutChar(VK, Scan: Integer; out ch: string): Boolean;
var
  st: TKeyboardState;
  buf: array[0..7] of WideChar;
  n: Integer;
  us: UnicodeString;
begin
  Result := False;
  FillChar(st, SizeOf(st), 0);
  n := ToUnicode(VK, Scan, st, buf, 8, 0);
  if n <= 0 then
    Exit;
  us := '';
  SetString(us, PWideChar(@buf[0]), n);
  ch := UTF8Encode(us);   // project strings are UTF-8
  Result := Length(ch) > 0;
end;

function KeyCapFor(VK, Scan: Integer): TKeyCap;
var
  c: string;
begin
  Result.Text := '';
  Result.Glyph := 0;
  Result.Symbol := False;
  Result.IsMod := IsModifierVK(VK);
  case VK of
    VK_LSHIFT, VK_RSHIFT, VK_SHIFT:
      begin Result.Glyph := $21E7; Result.Symbol := True; end;
    VK_LCONTROL, VK_RCONTROL, VK_CONTROL:
      Result.Text := 'Ctrl';
    VK_LMENU, VK_RMENU, VK_MENU:
      Result.Text := 'Alt';
    VK_LWIN, VK_RWIN:
      Result.Text := 'Win';
    VK_RETURN:
      begin Result.Glyph := $21B5; Result.Symbol := True; end;
    VK_BACK:
      begin Result.Glyph := $232B; Result.Symbol := True; end;
    VK_TAB:
      Result.Text := 'Tab';
    VK_ESCAPE:
      Result.Text := 'Esc';
    VK_CAPITAL:
      Result.Text := 'Caps';
    VK_SPACE:
      Result.Text := '';
    VK_UP:
      begin Result.Glyph := $2191; Result.Symbol := True; end;
    VK_DOWN:
      begin Result.Glyph := $2193; Result.Symbol := True; end;
    VK_LEFT:
      begin Result.Glyph := $2190; Result.Symbol := True; end;
    VK_RIGHT:
      begin Result.Glyph := $2192; Result.Symbol := True; end;
    VK_PRIOR:
      Result.Text := 'PgUp';
    VK_NEXT:
      Result.Text := 'PgDn';
    VK_HOME:
      Result.Text := 'Home';
    VK_END:
      Result.Text := 'End';
    VK_INSERT:
      Result.Text := 'Ins';
    VK_DELETE:
      Result.Text := 'Del';
    VK_SNAPSHOT:
      Result.Text := 'PrtSc';
    VK_SCROLL:
      Result.Text := 'ScrLk';
    VK_PAUSE:
      Result.Text := 'Pause';
    VK_NUMLOCK:
      Result.Text := 'NumLk';
    VK_APPS:
      Result.Text := 'Menu';
    VK_NUMPAD0..VK_NUMPAD9:
      Result.Text := Chr(Ord('0') + VK - VK_NUMPAD0);
    VK_MULTIPLY:
      Result.Text := '*';
    VK_ADD:
      Result.Text := '+';
    VK_SUBTRACT:
      Result.Text := '-';
    VK_DECIMAL:
      Result.Text := '.';
    VK_DIVIDE:
      Result.Text := '/';
    VK_F1..VK_F24:
      Result.Text := 'F' + IntToStr(VK - VK_F1 + 1);
    Ord('A')..Ord('Z'):
      Result.Text := Chr(VK);
    Ord('0')..Ord('9'):
      Result.Text := Chr(VK);
    VK_OEM_1:            // ;:  (US)
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := ';';
    VK_OEM_PLUS:         // =+
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '=';
    VK_OEM_COMMA:
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := ',';
    VK_OEM_MINUS:
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '-';
    VK_OEM_PERIOD:
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '.';
    VK_OEM_2:            // /?
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '/';
    VK_OEM_3:            // `~
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '`';
    VK_OEM_4:            // [{
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '[';
    VK_OEM_5:            // \|
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '\';
    VK_OEM_6:            // ]}
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := ']';
    VK_OEM_7:            // '"
      if LayoutChar(VK, Scan, c) then Result.Text := c else Result.Text := '''';
  else
    Result.Text := 'VK' + IntToStr(VK);
  end;
end;

function NormalizeVK(VK: Integer): Integer;
begin
  case VK of
    VK_LSHIFT, VK_RSHIFT:   Result := VK_SHIFT;
    VK_LCONTROL, VK_RCONTROL: Result := VK_CONTROL;
    VK_LMENU, VK_RMENU:     Result := VK_MENU;
    VK_LWIN, VK_RWIN:       Result := VK_LWIN;
  else
    Result := VK;
  end;
end;

function IsModifierVK(VK: Integer): Boolean;
begin
  case NormalizeVK(VK) of
    VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN: Result := True;
  else
    Result := False;
  end;
end;

function ModGroupOf(VK: Integer): Integer;
begin
  case NormalizeVK(VK) of
    VK_CONTROL: Result := MOG_CTRL;
    VK_MENU:    Result := MOG_ALT;
    VK_SHIFT:   Result := MOG_SHIFT;
    VK_LWIN:    Result := MOG_WIN;
  else
    Result := NOT_MOD;
  end;
end;

function VKFromKeyName(const AName: string): Integer;
var
  up, t: string;
  vk: Integer;
  i: Integer;
  cap: TKeyCap;
begin
  up := UpperCase(Trim(AName));
  if up = '' then
    Exit(0);
  // direct lookups
  if up = 'CTRL' then Exit(VK_CONTROL);
  if up = 'ALT' then Exit(VK_MENU);
  if up = 'SHIFT' then Exit(VK_SHIFT);
  if up = 'WIN' then Exit(VK_LWIN);
  if (up = 'SPACE') or (up = 'SPACEBAR') then Exit(VK_SPACE);
  if up = 'ENTER' then Exit(VK_RETURN);
  if up = 'ESC' then Exit(VK_ESCAPE);
  if up = 'TAB' then Exit(VK_TAB);
  // F-keys
  if (Length(up) > 1) and (up[1] = 'F') and TryStrToInt(Copy(up, 2, MaxInt), vk)
      and (vk >= 1) and (vk <= 24) then
    Exit(VK_F1 + vk - 1);
  // single letters / digits
  if (Length(up) = 1) then
  begin
    case up[1] of
      'A'..'Z', '0'..'9': Exit(Ord(up[1]));
    end;
  end;
  // scan the common table for a matching label
  for i := 8 to 254 do
  begin
    if not ((i in [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN]) or
            (i in [VK_PRIOR, VK_NEXT, VK_HOME, VK_END, VK_INSERT, VK_DELETE]) or
            (i in [VK_BACK, VK_TAB, VK_RETURN, VK_ESCAPE, VK_CAPITAL,
                   VK_SPACE, VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT]) or
            (i in [VK_SNAPSHOT, VK_SCROLL, VK_PAUSE, VK_NUMLOCK, VK_APPS]) or
            (i in [VK_MULTIPLY, VK_ADD, VK_SUBTRACT, VK_DECIMAL, VK_DIVIDE]) or
            (i in [VK_NUMPAD0..VK_NUMPAD9]) or
            (i in [VK_F1..VK_F24]) or
            (i in [Ord('0')..Ord('9'), Ord('A')..Ord('Z')]) or
            (i in [VK_OEM_1..VK_OEM_7])) then
      Continue;
    cap := KeyCapFor(i, 0);
    t := UpperCase(cap.Text);
    if (t <> '') and (t = up) then
      Exit(i);
  end;
  Result := 0;
end;

end.
