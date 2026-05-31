# Proton11 中文字体配置

## 原理

Wine 显示中文方框(□)的原因：游戏请求的字体（如 Tahoma、MS Shell Dlg）不含中文字形，且没有配置回退字体。

修复采用三层机制：

### 1. FontSubstitutes — 字体替换
`HKLM\...\FontSubstitutes`

直接把常用字体名映射为 WenQuanYi Micro Hei（含中文字形的字体）。

### 2. FontLink\SystemLink — 字体链接（最关键）
`HKLM\...\FontLink\SystemLink`

Windows 字体链接机制：当 Tahoma 渲染中文字符时，从 wqy-microhei.ttc 取字形。这是最优雅的 fallback 方案，不影响英文字体渲染。

### 3. Replacements — Wine 专属替换
`HKCU\Software\Wine\Fonts\Replacements`

Wine 特有的第一优先级替换层，覆盖 Windows 默认规则。

## 使用

```bash
# 安装/重装中文字体
~/proton11/proton11-fonts

# 在创建前缀时也会自动调用
~/proton11/proton11-init
```

## 涉及文件

| 文件 | 作用 |
|------|------|
| `Fonts/wqy-microhei.ttc` | 文泉驿微米黑字体文件 (5MB) |
| `system.reg` | HKLM 注册表（FontSubstitutes + FontLink + Fonts） |
| `user.reg` | HKCU 注册表（Replacements） |
| `proton11-fonts` | 安装脚本 |
| `proton11-init` | 初始化和字体安装集成 |

## 检查是否生效

```bash
# 验证注册表条目数（正常 > 50）
grep -c "wqy-microhei\|WenQuanYi" ~/proton11/p11prefix/system.reg
```
