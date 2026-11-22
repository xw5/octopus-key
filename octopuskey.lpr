program octopuskey;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Windows, SysUtils,
  config, langstrings, keymap, gdip, hooks, render, overlay, mouseoverlay, main;

{$R octopuskey.rc}

procedure SetProcessDPIAware; stdcall; external 'user32.dll' name 'SetProcessDPIAware';

begin
  SetProcessDPIAware;
  Application.Title := 'OctopusKey';
  Application.ShowMainForm := False;
  RequireDerivedFormResource := False;
  Application.Initialize;
  LoadConfig;
  GDIPlusInit;
  InitOverlay;
  InitMouseOverlay;
  InstallHooks(OverlayWnd, MouseOverlayWnd);
  Application.CreateForm(TSettingsForm, SettingsForm);
  SettingsForm.PrepareTray;
  if FirstRun then
    SettingsForm.Show   // show settings on very first launch
  else if (ParamCount > 0) and (ParamStr(1) = '--show-settings') then
    SettingsForm.Show;  // OctopusKey.exe --show-settings
  Application.Run;
  UninstallHooks;
  DoneOverlay;
  DoneMouseOverlay;
  GDIPlusDone;
end.
