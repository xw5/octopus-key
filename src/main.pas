unit main;

{ Settings window + tray icon. All controls are built in code (no .lfm),
  changes apply live to the overlays and are persisted to config.json. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs, Graphics, Menus, Registry,
  config, langstrings, keymap, overlay, mouseoverlay;

type
  TSettingsForm = class(TForm)
  public
    constructor Create(AOwner: TComponent); override;
    procedure PrepareTray;
    procedure ApplyLanguage;
  private
    Tray: TTrayIcon;
    TrayMenu: TPopupMenu;
    miSettings: TMenuItem;
    miToggle: TMenuItem;
    miExit: TMenuItem;
    PageCtrl: TPageControl;
    PanelBottom: TPanel;
    TabGeneral, TabStyle, TabPosition, TabFilter: TTabSheet;
    cbEnabled, cbMouse, cbModsAlone, cbIgnoreRepeat, cbCombosOnly,
      cbAutostart: TCheckBox;
    seTrail: TSpinEdit;
    cbLang: TComboBox;
    cbTheme: TComboBox;
    shBg, shMod, shText, shBorder: TShape;
    btnBg, btnMod, btnText, btnBorder: TButton;
    seRadius, seOpacity, seScale, seFont: TSpinEdit;
    posBtns: array[0..8] of TToggleBox;
    seMargin: TSpinEdit;
    btnTry: TButton;
    edBlacklist: TEdit;
    lblStatus: TLabel;
    btnClose: TButton;
    ColorDlg: TColorDialog;
    Building: Boolean;
    procedure BuildUI;
    procedure BuildGeneralTab;
    procedure BuildStyleTab;
    procedure BuildPositionTab;
    procedure BuildFilterTab;
    procedure ApplyThemeComboItems;
    procedure LoadUIFromCfg;
    procedure ReadControls;
    procedure ApplyAll;
    procedure CfgChanged(Sender: TObject);
    procedure ThemeChanged(Sender: TObject);
    procedure ColorPick(Sender: TObject);
    procedure PosClicked(Sender: TObject);
    procedure TryClicked(Sender: TObject);
    procedure LangChanged(Sender: TObject);
    procedure CloseClicked(Sender: TObject);
    procedure DoFormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure TrayClicked(Sender: TObject);
    procedure TrayToggleClicked(Sender: TObject);
    procedure TrayExitClicked(Sender: TObject);
    procedure UpdateStatus;
    procedure ApplyAutostart;
    procedure HexToShapeColor(const hex: string; shp: TShape);
    function  ShapeColorToHex(shp: TShape): string;
  end;

var
  SettingsForm: TSettingsForm;

implementation

{ ---------- helpers ---------- }

// labels carry their string id in Tag, so ApplyLanguage can find them again
function MkLabel(parent: TWinControl; x, y: Integer; strId: Integer;
  w: Integer = 130): TLabel;
begin
  Result := TLabel.Create(parent);
  Result.Parent := parent;
  Result.Left := x;
  Result.Top := y + 4;
  Result.Width := w;
  Result.Tag := strId;
  Result.Caption := S(strId);
  Result.Transparent := False;
end;

function MkCheck(parent: TWinControl; x, y: Integer; w: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(parent);
  Result.Parent := parent;
  Result.Left := x;
  Result.Top := y;
  Result.Width := w;
end;

function MkSpin(parent: TWinControl; x, y, lo, hi: Integer): TSpinEdit;
begin
  Result := TSpinEdit.Create(parent);
  Result.Parent := parent;
  Result.Left := x;
  Result.Top := y;
  Result.Width := 70;
  Result.MinValue := lo;
  Result.MaxValue := hi;
end;

{ ---------- lifecycle ---------- }

constructor TSettingsForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := 'OctopusKey';
  Position := poScreenCenter;
  ClientWidth := 470;
  ClientHeight := 520;
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu, biMinimize];
  ColorDlg := TColorDialog.Create(Self);
  Building := True;
  BuildUI;
  LoadUIFromCfg;
  OnClose := @DoFormClose;
  Building := False;
  UpdateStatus;
end;

procedure TSettingsForm.PrepareTray;
var
  bmp: TBitmap;
begin
  TrayMenu := TPopupMenu.Create(Self);
  miSettings := TMenuItem.Create(TrayMenu);
  miSettings.OnClick := @TrayClicked;
  TrayMenu.Items.Add(miSettings);
  miToggle := TMenuItem.Create(TrayMenu);
  miToggle.OnClick := @TrayToggleClicked;
  TrayMenu.Items.Add(miToggle);
  TrayMenu.Items.AddSeparator;
  miExit := TMenuItem.Create(TrayMenu);
  miExit.Caption := S(SID_TRAY_EXIT);
  miExit.OnClick := @TrayExitClicked;
  TrayMenu.Items.Add(miExit);

  Tray := TTrayIcon.Create(Self);
  Tray.PopUpMenu := TrayMenu;
  Tray.OnClick := @TrayClicked;
  Tray.Hint := 'OctopusKey';
  // embedded exe icon (res/octopuskey.ico, resource #1); drawn tile as fallback
  bmp := nil;
  try
    try
      Tray.Icon.LoadFromResourceID(HInstance, 1);
    except
      bmp := TBitmap.Create;
      bmp.SetSize(32, 32);
      bmp.Canvas.Brush.Color := RGB(26, 26, 34);
      bmp.Canvas.FillRect(Rect(0, 0, 32, 32));
      bmp.Canvas.Brush.Color := RGB(52, 124, 246);
      bmp.Canvas.RoundRect(4, 4, 28, 28, 10, 10);
      bmp.Canvas.Font.Name := 'Segoe UI';
      bmp.Canvas.Font.Style := [fsBold];
      bmp.Canvas.Font.Size := 14;
      bmp.Canvas.Font.Color := clWhite;
      bmp.Canvas.TextOut(11, 6, 'K');
      Tray.Icon.Assign(bmp);
    end;
  finally
    bmp.Free;
  end;
  Icon.Assign(Tray.Icon);   // settings window title bar / taskbar
  Tray.Visible := True;
  ApplyLanguage;
end;

procedure TSettingsForm.DoFormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

{ ---------- UI construction ---------- }

procedure TSettingsForm.BuildUI;
begin
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 40;
  PanelBottom.BevelOuter := bvNone;

  PageCtrl := TPageControl.Create(Self);
  PageCtrl.Parent := Self;
  PageCtrl.Align := alClient;

  TabGeneral := TTabSheet.Create(PageCtrl);
  TabGeneral.PageControl := PageCtrl;
  TabStyle := TTabSheet.Create(PageCtrl);
  TabStyle.PageControl := PageCtrl;
  TabPosition := TTabSheet.Create(PageCtrl);
  TabPosition.PageControl := PageCtrl;
  TabFilter := TTabSheet.Create(PageCtrl);
  TabFilter.PageControl := PageCtrl;

  BuildGeneralTab;
  BuildStyleTab;
  BuildPositionTab;
  BuildFilterTab;

  lblStatus := TLabel.Create(PanelBottom);
  lblStatus.Parent := PanelBottom;
  lblStatus.Left := 16;
  lblStatus.Top := 14;

  btnClose := TButton.Create(PanelBottom);
  btnClose.Parent := PanelBottom;
  btnClose.Width := 90;
  btnClose.Top := 8;
  btnClose.Left := PanelBottom.Width - 106;
  btnClose.Anchors := [akRight, akBottom];
  btnClose.OnClick := @CloseClicked;
end;

procedure TSettingsForm.BuildGeneralTab;
var
  y: Integer;
begin
  y := 16;
  cbEnabled := MkCheck(TabGeneral, 16, y, 420);
  cbEnabled.OnChange := @CfgChanged;
  Inc(y, 28);
  cbMouse := MkCheck(TabGeneral, 16, y, 420);
  cbMouse.OnChange := @CfgChanged;
  Inc(y, 28);
  cbModsAlone := MkCheck(TabGeneral, 16, y, 420);
  cbModsAlone.OnChange := @CfgChanged;
  Inc(y, 28);
  cbIgnoreRepeat := MkCheck(TabGeneral, 16, y, 420);
  cbIgnoreRepeat.OnChange := @CfgChanged;
  Inc(y, 28);
  cbCombosOnly := MkCheck(TabGeneral, 16, y, 420);
  cbCombosOnly.OnChange := @CfgChanged;
  Inc(y, 36);
  MkLabel(TabGeneral, 16, y, SID_TRAIL);
  seTrail := MkSpin(TabGeneral, 150, y, 0, 5);
  seTrail.OnChange := @CfgChanged;
  Inc(y, 36);
  MkLabel(TabGeneral, 16, y, SID_LANGUAGE);
  cbLang := TComboBox.Create(TabGeneral);
  cbLang.Parent := TabGeneral;
  cbLang.Left := 150;
  cbLang.Top := y;
  cbLang.Width := 160;
  cbLang.Style := csDropDownList;
  cbLang.Items.Add('跟随系统 / System');
  cbLang.Items.Add('中文');
  cbLang.Items.Add('English');
  cbLang.OnChange := @LangChanged;
  Inc(y, 36);
  cbAutostart := MkCheck(TabGeneral, 16, y, 420);
  cbAutostart.OnChange := @CfgChanged;
end;

procedure TSettingsForm.BuildStyleTab;
var
  y: Integer;

  function MkColorRow(x, yy, strId: Integer; var shp: TShape;
    var btn: TButton): Integer;
  begin
    MkLabel(TabStyle, x, yy, strId);
    shp := TShape.Create(TabStyle);
    shp.Parent := TabStyle;
    shp.Left := 150;
    shp.Top := yy + 2;
    shp.Width := 46;
    shp.Height := 22;
    btn := TButton.Create(TabStyle);
    btn.Parent := TabStyle;
    btn.Left := 204;
    btn.Top := yy;
    btn.Width := 56;
    btn.Caption := '...';
    btn.OnClick := @ColorPick;
    Result := yy + 32;
  end;
begin
  y := 16;
  MkLabel(TabStyle, 16, y, SID_THEME);
  cbTheme := TComboBox.Create(TabStyle);
  cbTheme.Parent := TabStyle;
  cbTheme.Left := 150;
  cbTheme.Top := y;
  cbTheme.Width := 160;
  cbTheme.Style := csDropDownList;
  cbTheme.OnChange := @ThemeChanged;
  Inc(y, 36);
  y := MkColorRow(16, y, SID_BG_COLOR, shBg, btnBg);
  y := MkColorRow(16, y, SID_MOD_COLOR, shMod, btnMod);
  y := MkColorRow(16, y, SID_TEXT_COLOR, shText, btnText);
  y := MkColorRow(16, y, SID_BORDER_COLOR, shBorder, btnBorder);
  MkLabel(TabStyle, 16, y, SID_RADIUS);
  seRadius := MkSpin(TabStyle, 150, y, 0, 24);
  seRadius.OnChange := @CfgChanged;
  MkLabel(TabStyle, 240, y, -1, 24).Caption := 'px';
  Inc(y, 34);
  MkLabel(TabStyle, 16, y, SID_OPACITY);
  seOpacity := MkSpin(TabStyle, 150, y, 30, 100);
  seOpacity.OnChange := @CfgChanged;
  MkLabel(TabStyle, 240, y, -1, 24).Caption := '%';
  Inc(y, 34);
  MkLabel(TabStyle, 16, y, SID_SCALE);
  seScale := MkSpin(TabStyle, 150, y, 50, 200);
  seScale.OnChange := @CfgChanged;
  MkLabel(TabStyle, 240, y, -1, 24).Caption := '%';
  Inc(y, 34);
  MkLabel(TabStyle, 16, y, SID_FONT_SIZE);
  seFont := MkSpin(TabStyle, 150, y, 14, 40);
  seFont.OnChange := @CfgChanged;
  MkLabel(TabStyle, 240, y, -1, 24).Caption := 'px';
end;

procedure TSettingsForm.BuildPositionTab;
var
  i: Integer;
begin
  MkLabel(TabPosition, 16, 10, SID_POS_HINT, 420);
  for i := 0 to 8 do
  begin
    posBtns[i] := TToggleBox.Create(TabPosition);
    posBtns[i].Parent := TabPosition;
    posBtns[i].Left := 16 + (i mod 3) * 44;
    posBtns[i].Top := 40 + (i div 3) * 44;
    posBtns[i].Width := 40;
    posBtns[i].Height := 40;
    case i of
      0: posBtns[i].Caption := Sym($2196);
      1: posBtns[i].Caption := Sym($2191);
      2: posBtns[i].Caption := Sym($2197);
      3: posBtns[i].Caption := Sym($2190);
      4: posBtns[i].Caption := Sym($2022);
      5: posBtns[i].Caption := Sym($2192);
      6: posBtns[i].Caption := Sym($2199);
      7: posBtns[i].Caption := Sym($2193);
      8: posBtns[i].Caption := Sym($2198);
    end;
    posBtns[i].Font.Size := 14;
    posBtns[i].OnClick := @PosClicked;
  end;
  MkLabel(TabPosition, 16, 180, SID_MARGIN);
  seMargin := MkSpin(TabPosition, 150, 176, 0, 200);
  seMargin.OnChange := @CfgChanged;
  MkLabel(TabPosition, 240, 180, -1, 24).Caption := 'px';
  btnTry := TButton.Create(TabPosition);
  btnTry.Parent := TabPosition;
  btnTry.Left := 16;
  btnTry.Top := 220;
  btnTry.Width := 120;
  btnTry.Tag := SID_TRY;
  btnTry.Caption := S(SID_TRY);
  btnTry.OnClick := @TryClicked;
end;

procedure TSettingsForm.BuildFilterTab;
begin
  MkLabel(TabFilter, 16, 16, SID_BLACKLIST, 420);
  edBlacklist := TEdit.Create(TabFilter);
  edBlacklist.Parent := TabFilter;
  edBlacklist.Left := 16;
  edBlacklist.Top := 40;
  edBlacklist.Width := 420;
  edBlacklist.OnChange := @CfgChanged;
  with MkLabel(TabFilter, 16, 66, SID_BLACKLIST_HINT, 420) do
    Font.Color := clGray;
end;

{ ---------- config <-> UI ---------- }

// compare '#AARRGGBB' colors ignoring the alpha byte
function SameRGB(const a, b: string): Boolean;
begin
  Result := (Length(a) >= 9) and (Length(b) >= 9) and
    (Copy(a, 4, 6) = Copy(b, 4, 6));
end;

procedure TSettingsForm.ApplyThemeComboItems;
var
  sel: Integer;
begin
  sel := cbTheme.ItemIndex;
  cbTheme.Items.Clear;
  cbTheme.Items.Add(S(SID_DARK));
  cbTheme.Items.Add(S(SID_LIGHT));
  cbTheme.Items.Add(S(SID_CUSTOM));
  cbTheme.ItemIndex := sel;
end;

procedure TSettingsForm.LoadUIFromCfg;
var
  i: Integer;
begin
  cbEnabled.Checked := Cfg.Enabled;
  cbMouse.Checked := Cfg.MouseEnabled;
  cbModsAlone.Checked := Cfg.ShowModsAlone;
  cbIgnoreRepeat.Checked := Cfg.IgnoreRepeat;
  cbCombosOnly.Checked := Cfg.CombosOnly;
  seTrail.Value := Cfg.TrailCount;
  cbLang.ItemIndex := Cfg.Lang + 1;   // 0=system, 1=zh, 2=en
  cbAutostart.Checked := Cfg.Autostart;
  ApplyThemeComboItems;
  if SameRGB(Cfg.ColBgKey, '#E61C1C24') and SameRGB(Cfg.ColBgMod, '#F0347CF6') then
    cbTheme.ItemIndex := 0
  else if SameRGB(Cfg.ColBgKey, '#F0F5F5FA') and SameRGB(Cfg.ColBgMod, '#F02563EB') then
    cbTheme.ItemIndex := 1
  else
    cbTheme.ItemIndex := 2;
  HexToShapeColor(Cfg.ColBgKey, shBg);
  HexToShapeColor(Cfg.ColBgMod, shMod);
  HexToShapeColor(Cfg.ColText, shText);
  HexToShapeColor(Cfg.ColBorder, shBorder);
  seRadius.Value := Cfg.RadiusPx;
  seOpacity.Value := Cfg.OpacityPct;
  seScale.Value := Cfg.ScalePct;
  seFont.Value := Cfg.FontPx;
  seMargin.Value := Cfg.MarginPx;
  edBlacklist.Text := Cfg.Blacklist;
  for i := 0 to 8 do
    posBtns[i].Checked := ((i mod 3) = Cfg.AnchorX) and ((i div 3) = Cfg.AnchorY);
end;

procedure TSettingsForm.ReadControls;
var
  i, sel: Integer;
begin
  Cfg.Enabled := cbEnabled.Checked;
  Cfg.MouseEnabled := cbMouse.Checked;
  Cfg.ShowModsAlone := cbModsAlone.Checked;
  Cfg.IgnoreRepeat := cbIgnoreRepeat.Checked;
  Cfg.CombosOnly := cbCombosOnly.Checked;
  Cfg.TrailCount := seTrail.Value;
  Cfg.Lang := cbLang.ItemIndex - 1;   // -1=system, 0=zh, 1=en
  Cfg.Autostart := cbAutostart.Checked;
  Cfg.RadiusPx := seRadius.Value;
  Cfg.OpacityPct := seOpacity.Value;
  Cfg.ScalePct := seScale.Value;
  Cfg.FontPx := seFont.Value;
  Cfg.MarginPx := seMargin.Value;
  Cfg.Blacklist := Trim(edBlacklist.Text);
  sel := -1;
  for i := 0 to 8 do
    if posBtns[i].Checked then
      sel := i;
  if sel >= 0 then
  begin
    Cfg.AnchorX := sel mod 3;
    Cfg.AnchorY := sel div 3;
  end;
  Cfg.ColBgKey := ShapeColorToHex(shBg);
  Cfg.ColBgMod := ShapeColorToHex(shMod);
  Cfg.ColText := ShapeColorToHex(shText);
  Cfg.ColBorder := ShapeColorToHex(shBorder);
end;

procedure TSettingsForm.ApplyAll;
begin
  SaveConfig;
  OverlayApplyConfig;
  MouseOverlayApplyConfig;
  ApplyAutostart;
  UpdateStatus;
end;

procedure TSettingsForm.CfgChanged(Sender: TObject);
begin
  if Building then
    Exit;
  ReadControls;
  ApplyAll;
end;

procedure TSettingsForm.ThemeChanged(Sender: TObject);
begin
  if Building then
    Exit;
  case cbTheme.ItemIndex of
    0: ApplyTheme('dark');
    1: ApplyTheme('light');
  else
    Exit;  // custom: keep current colors
  end;
  Building := True;
  HexToShapeColor(Cfg.ColBgKey, shBg);
  HexToShapeColor(Cfg.ColBgMod, shMod);
  HexToShapeColor(Cfg.ColText, shText);
  HexToShapeColor(Cfg.ColBorder, shBorder);
  Building := False;
  ReadControls;
  ApplyAll;
end;

procedure TSettingsForm.ColorPick(Sender: TObject);
var
  shp: TShape;
begin
  if Building then
    Exit;
  shp := nil;
  if Sender = btnBg then shp := shBg
  else if Sender = btnMod then shp := shMod
  else if Sender = btnText then shp := shText
  else if Sender = btnBorder then shp := shBorder;
  if shp = nil then
    Exit;
  ColorDlg.Color := shp.Brush.Color;
  if not ColorDlg.Execute then
    Exit;
  shp.Brush.Color := ColorDlg.Color;
  if cbTheme.ItemIndex < 2 then
    cbTheme.ItemIndex := 2;   // custom
  CfgChanged(Sender);
end;

procedure TSettingsForm.PosClicked(Sender: TObject);
var
  i: Integer;
begin
  if Building then
    Exit;
  // LCL fires OnClick on programmatic Checked changes too; guard against
  // the check/uncheck ping-pong between the 9 exclusive buttons
  Building := True;
  try
    for i := 0 to 8 do
      if posBtns[i] <> Sender then
        posBtns[i].Checked := False;
    TToggleBox(Sender).Checked := True;
  finally
    Building := False;
  end;
  CfgChanged(Sender);
end;

procedure TSettingsForm.TryClicked(Sender: TObject);
begin
  ShowDemoCombo([VK_CONTROL, Ord('C')]);
end;

procedure TSettingsForm.LangChanged(Sender: TObject);
begin
  if Building then
    Exit;
  Cfg.Lang := cbLang.ItemIndex - 1;
  ApplyLanguage;
  SaveConfig;
end;

procedure TSettingsForm.CloseClicked(Sender: TObject);
begin
  Close;
end;

procedure TSettingsForm.ApplyLanguage;
var
  i: Integer;
begin
  Caption := S(SID_TITLE);
  TabGeneral.Caption := S(SID_GENERAL);
  TabStyle.Caption := S(SID_STYLE);
  TabPosition.Caption := S(SID_POSITION);
  TabFilter.Caption := S(SID_FILTER);
  cbEnabled.Caption := S(SID_ENABLE_VIZ);
  cbMouse.Caption := S(SID_ENABLE_MOUSE);
  cbModsAlone.Caption := S(SID_SHOW_MODS);
  cbIgnoreRepeat.Caption := S(SID_IGNORE_REPEAT);
  cbCombosOnly.Caption := S(SID_COMBOS_ONLY);
  cbAutostart.Caption := S(SID_AUTOSTART);
  for i := 0 to TabGeneral.ControlCount - 1 do
    if (TabGeneral.Controls[i] is TLabel) and
       (TLabel(TabGeneral.Controls[i]).Tag > 0) then
      TLabel(TabGeneral.Controls[i]).Caption := S(TLabel(TabGeneral.Controls[i]).Tag);
  ApplyThemeComboItems;
  for i := 0 to TabStyle.ControlCount - 1 do
    if (TabStyle.Controls[i] is TLabel) and
       (TLabel(TabStyle.Controls[i]).Tag > 0) then
      TLabel(TabStyle.Controls[i]).Caption := S(TLabel(TabStyle.Controls[i]).Tag);
  for i := 0 to TabPosition.ControlCount - 1 do
    if (TabPosition.Controls[i] is TLabel) and
       (TLabel(TabPosition.Controls[i]).Tag > 0) then
      TLabel(TabPosition.Controls[i]).Caption := S(TLabel(TabPosition.Controls[i]).Tag);
  for i := 0 to TabFilter.ControlCount - 1 do
    if (TabFilter.Controls[i] is TLabel) and
       (TLabel(TabFilter.Controls[i]).Tag > 0) then
      TLabel(TabFilter.Controls[i]).Caption := S(TLabel(TabFilter.Controls[i]).Tag);
  if btnTry <> nil then
    btnTry.Caption := S(SID_TRY);
  btnClose.Caption := S(SID_CLOSE);
  miSettings.Caption := S(SID_TRAY_SETTINGS);
  if miExit <> nil then
    miExit.Caption := S(SID_TRAY_EXIT);
  UpdateStatus;
end;

procedure TSettingsForm.UpdateStatus;
begin
  if Cfg.Enabled then
  begin
    if lblStatus <> nil then
    begin
      lblStatus.Caption := S(SID_STATUS_ON);
      lblStatus.Font.Color := clGreen;
    end;
    if miToggle <> nil then
      miToggle.Caption := S(SID_TRAY_TOGGLE_ON);
  end
  else
  begin
    if lblStatus <> nil then
    begin
      lblStatus.Caption := S(SID_STATUS_OFF);
      lblStatus.Font.Color := clGray;
    end;
    if miToggle <> nil then
      miToggle.Caption := S(SID_TRAY_TOGGLE_OFF);
  end;
end;

procedure TSettingsForm.ApplyAutostart;
var
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    if reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', False) then
    begin
      if Cfg.Autostart then
        reg.WriteString('OctopusKey', '"' + ParamStr(0) + '"')
      else if reg.ValueExists('OctopusKey') then
        reg.DeleteValue('OctopusKey');
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

{ ---------- color helpers ---------- }

procedure TSettingsForm.HexToShapeColor(const hex: string; shp: TShape);
var
  c: DWORD;
begin
  c := HexToARGB(hex);
  shp.Brush.Color := RGB((c shr 16) and $FF, (c shr 8) and $FF, c and $FF);
end;

function TSettingsForm.ShapeColorToHex(shp: TShape): string;
var
  c: TColor;
begin
  c := TColor(shp.Brush.Color and $FFFFFF);
  Result := ARGBToHex((DWORD($FF) shl 24) or (DWORD(c and $FF) shl 16) or
    (DWORD((c shr 8) and $FF) shl 8) or DWORD((c shr 16) and $FF));
end;

{ ---------- tray ---------- }

procedure TSettingsForm.TrayClicked(Sender: TObject);
begin
  Show;
  SetForegroundWindow(Handle);
end;

procedure TSettingsForm.TrayToggleClicked(Sender: TObject);
begin
  Cfg.Enabled := not Cfg.Enabled;
  cbEnabled.Checked := Cfg.Enabled;  // fires OnChange -> CfgChanged
end;

procedure TSettingsForm.TrayExitClicked(Sender: TObject);
begin
  SaveConfig;
  Application.Terminate;
end;

end.
