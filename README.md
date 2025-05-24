# Magisk模块说明

## 目录结构
- `Online/`: 在线更新相关文件
- `Source/`: 源代码文件
- `install.sh`: 安装脚本
- `module.prop`: 模块属性
- `version`: 版本信息
- `changelog`: 更新日志

## 功能说明

- 循环启动支付宝
- 支持自定义黑名单
- 支持自定义启动时间
- 支持自动更新检测

## 使用方法

1. 下载最新的模块zip文件
2. 在Magisk Manager中安装
3. 重启设备以应用

## 自定义

自定义黑名单：

1. 配置文件路径:/Android/start_alipay
2. 黑名单的App在前台时,不会启动支付宝
3. 请正确填写App包名

## 更新记录
请查看 `changelog` 文件
