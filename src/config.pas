unit config;

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, Classes, fpjson, jsonparser;

const
  // anchor X: 0=left 1=center 2=right ; anchor Y: 0=top 1=middle 2=bottom
  ANCHOR_LEFT   = 0;
  ANCHOR_CENTER = 1;
  ANCHOR_RIGHT  = 2;
  ANCHOR_TOP    = 0;
  ANCHOR_MIDDLE = 1;
  ANCHOR_BOTTOM = 2;

  // language: -1 = follow system, 0 = zh, 1 = en
  LANG_SYSTEM = -1;
  LANG_ZH     = 0;
  LANG_EN     = 1;

type
  TConfig = record
    Lang: Integer;            // 0 = zh, 1 = en
    Enabled: Boolean;         // keyboard visualization master switch
    MouseEnabled: Boolean;    // mouse click indicator switch
    ShowModsAlone: Boolean;   // show modifiers pressed alone
    IgnoreRepeat: Boolean;    // ignore auto-repeat keydowns
    CombosOnly: Boolean;      // only show modifier+key combos
    TrailCount: Integer;      // history trail rows (0..5)
    HoldMs: Integer;          // hold time after release before fade-out
    EntryMs: Integer;         // appear animation duration
    ExitMs: Integer;          // disappear animation duration
    AnchorX: Integer;
    AnchorY: Integer;
    MarginPx: Integer;        // distance to screen edge
    ScalePct: Integer;        // 50..200, multiplies base sizes
    RadiusPx: Integer;        // keycap corner radius (base)
    OpacityPct: Integer;      // 30..100, applied on top of color alphas
    FontPx: Integer;          // base font size in pixels
    ColBgKey: string;         // '#AARRGGBB'
    ColBgMod: string;
    ColText: string;
    ColBorder: string;
    ColPlus: string;          // '+' separator color
    Blacklist: string;        // comma separated key names, never shown
    Autostart: Boolean;
  end;

var
  Cfg: TConfig;
  ConfigDir: string;
  FirstRun: Boolean;

procedure LoadConfig;
procedure SaveConfig;
function  HexToARGB(const s: string): DWORD;
function  ARGBToHex(c: DWORD): string;
procedure ApplyTheme(const theme: string);   // 'dark' | 'light'

implementation

const
  CONFIG_FILE = 'config.json';

function ConfigPath: string;
begin
  Result := ConfigDir + PathDelim + CONFIG_FILE;
end;

procedure SetDefaults;
begin
  Cfg.Lang          := LANG_SYSTEM;
  Cfg.Enabled       := True;
  Cfg.MouseEnabled  := True;
  Cfg.ShowModsAlone := True;
  Cfg.IgnoreRepeat  := True;
  Cfg.CombosOnly    := False;
  Cfg.TrailCount    := 3;
  Cfg.HoldMs        := 1200;
  Cfg.EntryMs       := 150;
  Cfg.ExitMs        := 200;
  Cfg.AnchorX       := ANCHOR_CENTER;
  Cfg.AnchorY       := ANCHOR_BOTTOM;
  Cfg.MarginPx      := 40;
  Cfg.ScalePct      := 100;
  Cfg.RadiusPx      := 12;
  Cfg.OpacityPct    := 85;
  Cfg.FontPx        := 22;
  Cfg.Blacklist     := '';
  Cfg.Autostart     := False;
  ApplyTheme('dark');
end;

procedure ApplyTheme(const theme: string);
begin
  if theme = 'light' then
  begin
    Cfg.ColBgKey   := '#F0F5F5FA';
    Cfg.ColBgMod   := '#F02563EB';
    Cfg.ColText    := '#FF16161E';
    Cfg.ColBorder  := '#28000000';
    Cfg.ColPlus    := '#9060606E';
  end
  else // dark (default)
  begin
    Cfg.ColBgKey   := '#E61C1C24';
    Cfg.ColBgMod   := '#F0347CF6';
    Cfg.ColText    := '#FFF5F5FA';
    Cfg.ColBorder  := '#30FFFFFF';
    Cfg.ColPlus    := '#90B9B9C8';
  end;
end;

procedure LoadConfig;
var
  j: TJSONData;
  o: TJSONObject;
  fs: TFileStream;
begin
  SetDefaults;
  ConfigDir := GetEnvironmentVariable('APPDATA') + '\OctopusKey';
  FirstRun := True;
  try
    ForceDirectories(ConfigDir);
  except
  end;
  if not FileExists(ConfigPath) then
    Exit;
  try
    fs := TFileStream.Create(ConfigPath, fmOpenRead or fmShareDenyWrite);
    try
      j := GetJSON(fs);
    finally
      fs.Free;
    end;
    try
      if not (j is TJSONObject) then Exit;
      o := TJSONObject(j);
      FirstRun := False;
      Cfg.Lang          := o.Get('lang', Cfg.Lang);
      Cfg.Enabled       := o.Get('enabled', Cfg.Enabled);
      Cfg.MouseEnabled  := o.Get('mouse', Cfg.MouseEnabled);
      Cfg.ShowModsAlone := o.Get('modsAlone', Cfg.ShowModsAlone);
      Cfg.IgnoreRepeat  := o.Get('ignoreRepeat', Cfg.IgnoreRepeat);
      Cfg.CombosOnly    := o.Get('combosOnly', Cfg.CombosOnly);
      Cfg.TrailCount    := o.Get('trail', Cfg.TrailCount);
      Cfg.HoldMs        := o.Get('holdMs', Cfg.HoldMs);
      Cfg.EntryMs       := o.Get('entryMs', Cfg.EntryMs);
      Cfg.ExitMs        := o.Get('exitMs', Cfg.ExitMs);
      Cfg.AnchorX       := o.Get('anchorX', Cfg.AnchorX);
      Cfg.AnchorY       := o.Get('anchorY', Cfg.AnchorY);
      Cfg.MarginPx      := o.Get('margin', Cfg.MarginPx);
      Cfg.ScalePct      := o.Get('scale', Cfg.ScalePct);
      Cfg.RadiusPx      := o.Get('radius', Cfg.RadiusPx);
      Cfg.OpacityPct    := o.Get('opacity', Cfg.OpacityPct);
      Cfg.FontPx        := o.Get('fontPx', Cfg.FontPx);
      Cfg.ColBgKey      := o.Get('colBgKey', Cfg.ColBgKey);
      Cfg.ColBgMod      := o.Get('colBgMod', Cfg.ColBgMod);
      Cfg.ColText       := o.Get('colText', Cfg.ColText);
      Cfg.ColBorder     := o.Get('colBorder', Cfg.ColBorder);
      Cfg.ColPlus       := o.Get('colPlus', Cfg.ColPlus);
      Cfg.Blacklist     := o.Get('blacklist', Cfg.Blacklist);
      Cfg.Autostart     := o.Get('autostart', Cfg.Autostart);
    finally
      j.Free;
    end;
  except
    // corrupted config -> fall back to defaults
    SetDefaults;
  end;
end;

procedure SaveConfig;
var
  o: TJSONObject;
  fs: TFileStream;
  json: AnsiString;
begin
  try
    ForceDirectories(ConfigDir);
    o := TJSONObject.Create;
    try
      o.Add('lang', Cfg.Lang);
      o.Add('enabled', Cfg.Enabled);
      o.Add('mouse', Cfg.MouseEnabled);
      o.Add('modsAlone', Cfg.ShowModsAlone);
      o.Add('ignoreRepeat', Cfg.IgnoreRepeat);
      o.Add('combosOnly', Cfg.CombosOnly);
      o.Add('trail', Cfg.TrailCount);
      o.Add('holdMs', Cfg.HoldMs);
      o.Add('entryMs', Cfg.EntryMs);
      o.Add('exitMs', Cfg.ExitMs);
      o.Add('anchorX', Cfg.AnchorX);
      o.Add('anchorY', Cfg.AnchorY);
      o.Add('margin', Cfg.MarginPx);
      o.Add('scale', Cfg.ScalePct);
      o.Add('radius', Cfg.RadiusPx);
      o.Add('opacity', Cfg.OpacityPct);
      o.Add('fontPx', Cfg.FontPx);
      o.Add('colBgKey', Cfg.ColBgKey);
      o.Add('colBgMod', Cfg.ColBgMod);
      o.Add('colText', Cfg.ColText);
      o.Add('colBorder', Cfg.ColBorder);
      o.Add('colPlus', Cfg.ColPlus);
      o.Add('blacklist', Cfg.Blacklist);
      o.Add('autostart', Cfg.Autostart);
      fs := TFileStream.Create(ConfigPath, fmCreate);
      try
        json := UTF8Encode(o.AsJSON);
        if json <> '' then
          fs.WriteBuffer(json[1], Length(json));
      finally
        fs.Free;
      end;
    finally
      o.Free;
    end;
  except
    // never let saving config crash the app
  end;
end;

function HexToARGB(const s: string): DWORD;
var
  t: string;
  v: Int64;
begin
  t := Trim(s);
  if Copy(t, 1, 1) = '#' then
    t := Copy(t, 2, MaxInt);
  if Length(t) < 8 then
    t := StringOfChar('F', 8 - Length(t)) + t;
  if not TryStrToInt64('$' + t, v) then
    v := $FF000000;
  Result := DWORD(v);
end;

function ARGBToHex(c: DWORD): string;
begin
  Result := '#' + IntToHex(c, 8);
end;

end.
