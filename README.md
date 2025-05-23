# Magisk 模块仓库

**注意：使用本项目请注明源作者信息。**

这个仓库用于管理多个 Magisk 模块，通过分支管理不同模块，并支持自动打包和更新检测功能，还支持实时同步所有分支代码到Gitee。

## 仓库结构

- 每个分支对应一个独立的 Magisk 模块
- `main` 分支包含共享的工作流和脚本
- 所有模块遵循标准的 Magisk 模块结构

## 使用方法

### 创建新模块

1. 从 `main` 分支创建新分支，命名为模块名称
2. 按照 Magisk 模块标准结构添加文件
3. 修改 `module.prop` 文件中的模块信息
4. 推送更改到 GitHub

### 自动打包

当推送代码到任何模块分支时，GitHub Actions 会自动：

1. 验证模块结构
2. 打包模块为 zip 文件
3. 创建 release 并上传 zip 文件

### 更新检测

模块中的更新检测通过以下方式实现：

1. `module.prop` 中设置 `updateJson` 指向 GitHub 上的 JSON 文件
2. 每次发布新版本时，自动更新该 JSON 文件

## 模块开发指南

请参考 [Magisk 模块开发文档](https://topjohnwu.github.io/Magisk/guides.html) 了解更多信息。
