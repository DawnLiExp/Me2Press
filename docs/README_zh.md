# Me2Press

[![Swift-6](https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white)](#) [![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)

[English](../README.md) | [中文](README_zh.md)

Me2Press 是一款 macOS 本地 Kindle 书籍制作工具，支持将 TXT 小说、图片文件夹（漫画）和 EPUB 电子书转换为可直接发送至 Kindle 的格式。主要为自用而做。

## 📸 界面预览

<div align="center">
  <img src="screenshot1.png" width="58%" alt="screenshot1"/>
  <img src="screenshot2.png" width="38%" alt="screenshot2"/>
</div>


## ✨ 功能

**TXT 书籍**：TXT → EPUB / AZW3

- 自动识别章节标题（正则规则可自定义，支持多级标题）
- 自动生成封面，支持自定义封面图片
- 可选首行缩进、保留原始换行
- 支持 UTF-8 / GB18030 / UTF-16 自动编码检测

**漫画书籍**：图片文件夹 → MOBI（固定布局）
- 拖入含图片的文件夹，打包为单本 MOBI；拖入父目录自动展开子文件夹批量处理
- 图片总体积超过 380 MB 自动分卷（`Vol.1` / `Vol.2` …）
- 打包逻辑参考了 [KCC](https://github.com/ciromattia/kcc)（仅打包部分，不含图片处理）；图片预处理我会先用 [Me2Comic](https://github.com/DawnLiExp/Me2Comic) 完成

**EPUB 转换**：EPUB → AZW3
- 直接将现有 EPUB 转换为 AZW3 格式

三个功能均支持：
- 并发任务处理（1–6）
- 批量拖入，顺序可调
- 修复 MOBI/AZW3 元数据（CDEType / ASIN），使 Kindle 正确识别为书籍

## 🖥 系统要求

- macOS 14+
- kindlegen（AZW3 / MOBI 输出必需，EPUB 导出不需要）：可安装 [Kindle Previewer](https://www.amazon.com/Kindle-Previewer/b?ie=UTF8&node=21381691011) 获取，或自行在 archive.org 等渠道下载 kindlegen 独立版

## 🛠 技术栈

- Swift 6 + SwiftUI，严格并发安全
- `@Observable` 状态管理
- 结构化并发（async/await、TaskGroup）
- CoreGraphics / CoreText 封面生成（无 AppKit 依赖）

## 🙏 感谢

漫画打包格式参考了 [KCC (Kindle Comic Converter)](https://github.com/ciromattia/kcc)。
