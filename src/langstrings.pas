unit langstrings;

{$mode objfpc}{$H+}

interface

const
  SID_TITLE            = 1;
  SID_GENERAL          = 2;
  SID_STYLE            = 3;
  SID_POSITION         = 4;
  SID_FILTER           = 5;
  SID_ENABLE_VIZ       = 6;
  SID_ENABLE_MOUSE     = 7;
  SID_SHOW_MODS        = 8;
  SID_IGNORE_REPEAT    = 9;
  SID_COMBOS_ONLY      = 10;
  SID_TRAIL            = 11;
  SID_AUTOSTART        = 12;
  SID_LANGUAGE         = 13;
  SID_THEME            = 14;
  SID_DARK             = 15;
  SID_LIGHT            = 16;
  SID_CUSTOM           = 17;
  SID_BG_COLOR         = 18;
  SID_MOD_COLOR        = 19;
  SID_TEXT_COLOR       = 20;
  SID_BORDER_COLOR     = 21;
  SID_RADIUS           = 22;
  SID_OPACITY          = 23;
  SID_SCALE            = 24;
  SID_FONT_SIZE        = 25;
  SID_MARGIN           = 26;
  SID_TRY              = 27;
  SID_BLACKLIST        = 28;
  SID_BLACKLIST_HINT   = 29;
  SID_TRAY_SETTINGS    = 30;
  SID_TRAY_TOGGLE_ON   = 31;
  SID_TRAY_TOGGLE_OFF  = 32;
  SID_TRAY_EXIT        = 33;
  SID_CLOSE            = 34;
  SID_POS_HINT         = 35;
  SID_STATUS_ON        = 36;
  SID_STATUS_OFF       = 37;
  SID_RESET            = 38;
  SID_THEME_HINT       = 39;

function S(id: Integer): string;

implementation

uses
  SysUtils, config;

function GetUserDefaultUILanguage: Word; stdcall;
  external 'kernel32.dll';

var
  SysLang: Integer = -2;   // resolved once: 0 = zh, 1 = en

// resolve "follow system" to zh or en
function EffectiveLang: Integer;
var
  prim: Word;
begin
  if Cfg.Lang = LANG_SYSTEM then
  begin
    if SysLang < 0 then
    begin
      prim := GetUserDefaultUILanguage and $03FF;
      if prim = $04 then      // Chinese
        SysLang := LANG_ZH
      else
        SysLang := LANG_EN;   // everything else falls back to English
    end;
    Result := SysLang;
  end
  else
    Result := Cfg.Lang;
end;

const
  ZH: array[1..39] of string = (
    'OctopusKey 设置',                       // 1
    '常规',                                  // 2
    '样式',                                  // 3
    '位置',                                  // 4
    '过滤',                                  // 5
    '启用按键可视化',                        // 6
    '显示鼠标点击提示',                      // 7
    '修饰键单独按下时也显示',                // 8
    '忽略按键自动重复',                      // 9
    '仅显示组合键(修饰键 + 按键)',          // 10
    '历史轨迹条数',                          // 11
    '开机自动启动',                          // 12
    '语言 Language',                         // 13
    '主题',                                  // 14
    '深色',                                  // 15
    '浅色',                                  // 16
    '自定义',                                // 17
    '普通键背景',                            // 18
    '修饰键背景',                            // 19
    '文字颜色',                              // 20
    '边框颜色',                              // 21
    '圆角半径',                              // 22
    '不透明度',                              // 23
    '缩放',                                  // 24
    '字号',                                  // 25
    '屏幕边距',                              // 26
    '试一试',                                // 27
    '忽略按键(逗号分隔,如 Win,F5)',        // 28
    '列表中的按键不会显示',                  // 29
    '显示设置',                              // 30
    '停用可视化',                            // 31
    '启用可视化',                            // 32
    '退出',                                  // 33
    '关闭',                                  // 34
    '选择键帽出现的位置',                    // 35
    '可视化运行中',                          // 36
    '可视化已停用',                          // 37
    '恢复默认',                              // 38
    '修改颜色后主题变为自定义'              // 39
  );

  EN: array[1..39] of string = (
    'OctopusKey Settings',
    'General',
    'Style',
    'Position',
    'Filter',
    'Enable keyboard visualization',
    'Show mouse click indicator',
    'Show modifiers pressed alone',
    'Ignore auto-repeat',
    'Show only combos (modifier + key)',
    'History trail count',
    'Start with Windows',
    '语言 Language',
    'Theme',
    'Dark',
    'Light',
    'Custom',
    'Key background',
    'Modifier background',
    'Text color',
    'Border color',
    'Corner radius',
    'Opacity',
    'Scale',
    'Font size',
    'Screen margin',
    'Try it',
    'Ignored keys (comma separated, e.g. Win,F5)',
    'These keys will never be shown',
    'Show settings',
    'Disable visualization',
    'Enable visualization',
    'Exit',
    'Close',
    'Choose where keycaps appear',
    'Visualization running',
    'Visualization disabled',
    'Reset defaults',
    'Changing colors switches theme to custom'
  );

function S(id: Integer): string;
begin
  if (id < Low(ZH)) or (id > High(ZH)) then
    Exit('');
  if EffectiveLang = LANG_ZH then
    Result := ZH[id]
  else
    Result := EN[id];
end;

end.
